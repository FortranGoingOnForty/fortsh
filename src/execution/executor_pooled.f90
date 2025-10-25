! ==============================================================================
! Module: executor_pooled - Memory-pooled version of executor module
! ==============================================================================
!
! This module provides pooled memory management for the executor module,
! focusing on large buffer allocations for command output and pipeline data.
!
! Key pooling targets:
! - Command output buffers (4KB-16KB)
! - Pipeline data buffers
! - Token arrays
! - Reconstructed command strings
! - Redirection file names
!
module executor_pooled
  use shell_types
  use string_pool
  use memory_dashboard
  use pooled_types
  use system_interface
  use builtins
  use parser
  use parser_pooled
  use job_control
  use variables
  use control_flow
  use error_handling
  use performance
  use shell_options
  use signal_handling
  use better_errors
  use iso_fortran_env, only: error_unit, input_unit, output_unit
  use iso_c_binding
  implicit none

contains

  ! Execute a pipeline with pooled memory management
  subroutine execute_pipeline_pooled(pipeline, shell, original_input)
    type(pipeline_t), intent(inout) :: pipeline
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input

    integer :: i
    logical :: should_continue
    type(string_ref) :: original_input_ref

    ! Track entry into executor
    call dashboard_track_entry(MOD_EXECUTOR)

    ! Pool the original input for internal use
    original_input_ref = pool_get_string(len(original_input))
    call dashboard_track_allocation(MOD_EXECUTOR, len(original_input), get_bucket_for_size(len(original_input)))
    call pool_copy_to_ref(original_input_ref, original_input)

    should_continue = .true.
    i = 1

    do while (i <= pipeline%num_commands .and. should_continue)
      select case(pipeline%commands(i)%separator)
      case(SEP_PIPE)
        call execute_pipe_chain_pooled(pipeline, i, shell, original_input_ref)
        call check_errexit(shell, shell%last_exit_status)
        if (.not. shell%running) exit
        do while (i <= pipeline%num_commands)
          if (pipeline%commands(i)%separator /= SEP_PIPE) exit
          i = i + 1
        end do
        i = i + 1

      case(SEP_SEMICOLON, SEP_NONE)
        call execute_single_pooled(pipeline%commands(i), shell, original_input_ref)
        if (shell%should_source) then
          call process_source_inline(shell)
        end if
        call check_errexit(shell, shell%last_exit_status)
        if (.not. shell%running) exit
        i = i + 1

      case(SEP_AND)
        call execute_single_pooled(pipeline%commands(i), shell, original_input_ref)
        should_continue = (shell%last_exit_status == 0)
        if (.not. shell%running) exit
        i = i + 1

      case(SEP_OR)
        call execute_single_pooled(pipeline%commands(i), shell, original_input_ref)
        should_continue = (shell%last_exit_status /= 0)
        if (.not. shell%running) exit
        i = i + 1
      end select
    end do

    ! Release pooled input
    call pool_release_string(original_input_ref)
    call dashboard_track_deallocation(MOD_EXECUTOR, len(original_input), get_bucket_for_size(len(original_input)))

    ! Track exit from executor
    call dashboard_track_exit(MOD_EXECUTOR)
  end subroutine execute_pipeline_pooled

  ! Execute single command with pooled memory
  subroutine execute_single_pooled(cmd, shell, original_input_ref)
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell
    type(string_ref), intent(in) :: original_input_ref

    logical :: should_execute
    type(string_ref) :: reconstructed_cmd_ref
    type(string_ref), allocatable :: temp_token_refs(:)
    integer :: i

    ! Track entry
    call dashboard_track_entry(MOD_EXECUTOR)

    ! Initialize
    should_execute = .true.

    ! Handle command reconstruction with pooled buffer
    if (allocated(cmd%tokens) .and. cmd%num_tokens > 0) then
      ! Allocate pooled buffer for reconstructed command
      reconstructed_cmd_ref = pool_get_string(4096)
      call dashboard_track_allocation(MOD_EXECUTOR, 4096, get_bucket_for_size(4096))

      call reconstruct_command_pooled(cmd, reconstructed_cmd_ref)

      ! Check for control flow
      if (is_control_flow_keyword(cmd%tokens(1))) then
        call process_control_flow(cmd, shell, should_execute)
        if (.not. should_execute) then
          call pool_release_string(reconstructed_cmd_ref)
          call dashboard_track_deallocation(MOD_EXECUTOR, 4096, get_bucket_for_size(4096))
          call dashboard_track_exit(MOD_EXECUTOR)
          return
        end if
      end if
    end if

    ! Handle heredoc with pooled buffer
    if (allocated(cmd%heredoc_delimiter) .and. .not. allocated(cmd%heredoc_content)) then
      call read_heredoc_pooled(cmd%heredoc_delimiter, cmd)
    end if

    ! Expand tokens with pooling
    call expand_tokens_pooled(cmd, shell)

    ! Execute the command (delegate to existing logic)
    if (cmd%num_tokens > 0) then
      if (is_builtin(cmd%tokens(1))) then
        call execute_builtin(cmd, shell)
      else
        ! External command - use existing exec_child
        call setup_redirections(cmd, shell)
        call exec_child(cmd%tokens, cmd%num_tokens)
      end if
    end if

    ! Clean up pooled resources
    if (reconstructed_cmd_ref%pool_index /= 0) then
      call pool_release_string(reconstructed_cmd_ref)
      call dashboard_track_deallocation(MOD_EXECUTOR, 4096, get_bucket_for_size(4096))
    end if

    call dashboard_track_exit(MOD_EXECUTOR)
  end subroutine execute_single_pooled

  ! Execute pipe chain with pooled memory
  subroutine execute_pipe_chain_pooled(pipeline, start_idx, shell, original_input_ref)
    type(pipeline_t), intent(inout) :: pipeline
    integer, intent(in) :: start_idx
    type(shell_state_t), intent(inout) :: shell
    type(string_ref), intent(in) :: original_input_ref

    integer :: i, pipe_count, end_idx
    integer(c_int), allocatable :: pipefd(:,:)
    integer(c_pid_t), allocatable :: pids(:)
    type(string_ref) :: pipe_buffer_ref

    ! Track entry
    call dashboard_track_entry(MOD_EXECUTOR)

    ! Count pipes
    pipe_count = 0
    end_idx = start_idx
    do i = start_idx, pipeline%num_commands - 1
      if (pipeline%commands(i)%separator == SEP_PIPE) then
        pipe_count = pipe_count + 1
        end_idx = i + 1
      else
        exit
      end if
    end do

    ! Allocate pipe descriptors and process IDs
    allocate(pipefd(2, pipe_count))
    allocate(pids(pipe_count + 1))

    ! Allocate pooled buffer for pipe data transfer (16KB for large outputs)
    pipe_buffer_ref = pool_get_string(16384)
    call dashboard_track_allocation(MOD_EXECUTOR, 16384, get_bucket_for_size(16384))

    ! Execute pipe chain (simplified - delegate to existing logic)
    ! The actual pipe execution logic would go here, using pooled buffers
    ! for data transfer between processes

    ! Clean up
    call pool_release_string(pipe_buffer_ref)
    call dashboard_track_deallocation(MOD_EXECUTOR, 16384, get_bucket_for_size(16384))

    deallocate(pipefd)
    deallocate(pids)

    call dashboard_track_exit(MOD_EXECUTOR)
  end subroutine execute_pipe_chain_pooled

  ! Reconstruct command from tokens using pooled buffer
  subroutine reconstruct_command_pooled(cmd, result_ref)
    type(command_t), intent(in) :: cmd
    type(string_ref), intent(inout) :: result_ref

    integer :: i, pos
    character(len=4096) :: temp_buffer

    ! Build command string in temp buffer
    temp_buffer = ""
    pos = 1

    do i = 1, cmd%num_tokens
      if (i > 1) then
        temp_buffer(pos:pos) = ' '
        pos = pos + 1
      end if

      ! Add token
      temp_buffer(pos:pos+len_trim(cmd%tokens(i))-1) = trim(cmd%tokens(i))
      pos = pos + len_trim(cmd%tokens(i))
    end do

    ! Copy to pooled reference
    call pool_copy_to_ref(result_ref, temp_buffer(1:pos-1))
  end subroutine reconstruct_command_pooled

  ! Read heredoc content into pooled buffer
  subroutine read_heredoc_pooled(delimiter, cmd)
    character(len=*), intent(in) :: delimiter
    type(command_t), intent(inout) :: cmd

    type(string_ref) :: content_ref
    character(len=4096) :: buffer
    integer :: total_len

    ! Allocate pooled buffer for heredoc content
    content_ref = pool_get_string(4096)
    call dashboard_track_allocation(MOD_EXECUTOR, 4096, get_bucket_for_size(4096))

    ! Read heredoc content (simplified - would read from stdin)
    ! In real implementation, this would read line by line until delimiter
    buffer = ""
    total_len = 0

    ! Copy to pooled buffer
    call pool_copy_to_ref(content_ref, buffer(1:total_len))

    ! Store in command (would need to modify command_t to use string_ref)
    if (.not. allocated(cmd%heredoc_content)) then
      allocate(character(len=total_len) :: cmd%heredoc_content)
    end if
    cmd%heredoc_content = buffer(1:total_len)

    ! Release pooled buffer after copying
    call pool_release_string(content_ref)
    call dashboard_track_deallocation(MOD_EXECUTOR, 4096, get_bucket_for_size(4096))
  end subroutine read_heredoc_pooled

  ! Expand command tokens with pooled memory
  subroutine expand_tokens_pooled(cmd, shell)
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell

    type(string_ref), allocatable :: expanded_refs(:)
    integer :: i

    if (.not. allocated(cmd%tokens)) return

    ! Allocate pooled references for expanded tokens
    allocate(expanded_refs(cmd%num_tokens))

    do i = 1, cmd%num_tokens
      ! Allocate pooled buffer for each expanded token
      expanded_refs(i) = pool_get_string(1024)
      call dashboard_track_allocation(MOD_EXECUTOR, 1024, get_bucket_for_size(1024))

      ! Expand the token (simplified - would call expansion functions)
      call pool_copy_to_ref(expanded_refs(i), cmd%tokens(i))

      ! Copy back to token (in real implementation, would modify to use refs)
      cmd%tokens(i) = expanded_refs(i)%data
    end do

    ! Release pooled buffers
    do i = 1, cmd%num_tokens
      call pool_release_string(expanded_refs(i))
      call dashboard_track_deallocation(MOD_EXECUTOR, 1024, get_bucket_for_size(1024))
    end do

    deallocate(expanded_refs)
  end subroutine expand_tokens_pooled

  ! Execute command substitution with pooled output buffer
  function execute_command_substitution_pooled(shell, command) result(output_ref)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command
    type(string_ref) :: output_ref

    type(string_ref) :: buffer_ref
    character(len=4096) :: temp_output
    integer :: output_len

    ! Track entry
    call dashboard_track_entry(MOD_EXECUTOR)

    ! Allocate large pooled buffer for command output
    buffer_ref = pool_get_string(16384)
    call dashboard_track_allocation(MOD_EXECUTOR, 16384, get_bucket_for_size(16384))

    ! Execute command and capture output (simplified)
    ! In real implementation, this would use popen/pipe to capture output
    temp_output = ""
    output_len = 0

    ! Allocate result buffer of appropriate size
    output_ref = pool_get_string(output_len + 1)
    call dashboard_track_allocation(MOD_EXECUTOR, output_len + 1, get_bucket_for_size(output_len + 1))

    ! Copy output to result
    call pool_copy_to_ref(output_ref, temp_output(1:output_len))

    ! Release temporary buffer
    call pool_release_string(buffer_ref)
    call dashboard_track_deallocation(MOD_EXECUTOR, 16384, get_bucket_for_size(16384))

    call dashboard_track_exit(MOD_EXECUTOR)
  end function execute_command_substitution_pooled

  ! Helper: Get bucket index for size
  function get_bucket_for_size(size_bytes) result(bucket_idx)
    integer, intent(in) :: size_bytes
    integer :: bucket_idx

    if (size_bytes <= 64) then
      bucket_idx = 1
    else if (size_bytes <= 256) then
      bucket_idx = 2
    else if (size_bytes <= 1024) then
      bucket_idx = 3
    else if (size_bytes <= 4096) then
      bucket_idx = 4
    else if (size_bytes <= 16384) then
      bucket_idx = 5
    else
      bucket_idx = 0  ! Direct allocation
    end if
  end function get_bucket_for_size

  ! Clean up all executor pooled resources
  subroutine cleanup_executor_pooled()
    ! Any module-level cleanup would go here
    call dashboard_track_exit(MOD_EXECUTOR)
  end subroutine cleanup_executor_pooled

end module executor_pooled