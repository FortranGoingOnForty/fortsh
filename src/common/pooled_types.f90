! ==============================================================================
! Module: pooled_types
! Purpose: Memory-pooled versions of shell types for Phase 6 integration
! ==============================================================================
module pooled_types
  use shell_types
  use string_pool
  use memory_dashboard
  implicit none

  ! Pooled version of command_t
  type :: pooled_command_t
    ! Token storage using pool references
    type(string_ref), allocatable :: pooled_tokens(:)
    integer :: num_tokens = 0

    ! File redirections using pool references
    type(string_ref) :: input_file
    type(string_ref) :: output_file
    type(string_ref) :: error_file

    ! Heredoc support using pool references
    type(string_ref) :: heredoc_delimiter
    type(string_ref) :: heredoc_content
    logical :: heredoc_quoted = .false.

    ! Here string using pool reference
    type(string_ref) :: here_string

    ! Command grouping using pool references
    type(string_ref) :: group_content
    type(string_ref) :: subshell_content

    ! All the non-allocatable fields remain the same
    logical :: append_output = .false.
    logical :: append_error = .false.
    logical :: force_clobber = .false.
    logical :: redirect_stderr_to_stdout = .false.
    logical :: redirect_stdout_to_stderr = .false.
    logical :: redirect_both_to_file = .false.
    logical :: background = .false.
    integer :: separator = SEP_NONE
    logical :: is_command_group = .false.
    logical :: is_subshell = .false.

    ! Enhanced POSIX file descriptor redirection
    type(redirection_t) :: redirections(10)
    integer :: num_redirections = 0

    ! Prefix assignments remain as fixed-size for now
    character(len=256) :: prefix_assignments(10) = ''
    integer :: num_prefix_assignments = 0
  end type pooled_command_t

  ! Pooled version of pipeline_t
  type :: pooled_pipeline_t
    type(pooled_command_t), allocatable :: commands(:)
    integer :: num_commands = 0
  end type pooled_pipeline_t

contains

  ! Initialize a pooled command
  subroutine init_pooled_command(cmd)
    type(pooled_command_t), intent(out) :: cmd

    ! Initialize all string refs to empty state
    cmd%input_file%pool_index = 0
    cmd%output_file%pool_index = 0
    cmd%error_file%pool_index = 0
    cmd%heredoc_delimiter%pool_index = 0
    cmd%heredoc_content%pool_index = 0
    cmd%here_string%pool_index = 0
    cmd%group_content%pool_index = 0
    cmd%subshell_content%pool_index = 0

    cmd%num_tokens = 0
    cmd%num_redirections = 0
    cmd%num_prefix_assignments = 0
  end subroutine init_pooled_command

  ! Allocate pooled tokens array
  subroutine allocate_pooled_tokens(cmd, num_tokens, token_size)
    type(pooled_command_t), intent(inout) :: cmd
    integer, intent(in) :: num_tokens, token_size
    integer :: i

    if (allocated(cmd%pooled_tokens)) then
      call release_pooled_tokens(cmd)
    end if

    allocate(cmd%pooled_tokens(num_tokens))
    do i = 1, num_tokens
      cmd%pooled_tokens(i) = pool_get_string(token_size)
      call dashboard_track_allocation(MOD_PARSER, token_size, get_bucket_idx(token_size))
    end do
    cmd%num_tokens = num_tokens
  end subroutine allocate_pooled_tokens

  ! Set a token value
  subroutine set_pooled_token(cmd, idx, value)
    type(pooled_command_t), intent(inout) :: cmd
    integer, intent(in) :: idx
    character(len=*), intent(in) :: value

    if (idx > 0 .and. idx <= cmd%num_tokens) then
      call pool_copy_to_ref(cmd%pooled_tokens(idx), value)
    end if
  end subroutine set_pooled_token

  ! Get a token value (returns pointer to pooled data)
  function get_pooled_token(cmd, idx) result(token)
    type(pooled_command_t), intent(in) :: cmd
    integer, intent(in) :: idx
    character(:), pointer :: token

    if (idx > 0 .and. idx <= cmd%num_tokens) then
      token => cmd%pooled_tokens(idx)%data
    else
      token => null()
    end if
  end function get_pooled_token

  ! Set pooled string field
  subroutine set_pooled_string(ref, value, module_id)
    type(string_ref), intent(inout) :: ref
    character(len=*), intent(in) :: value
    integer, intent(in), optional :: module_id
    integer :: mod_id, size_bytes

    mod_id = MOD_PARSER
    if (present(module_id)) mod_id = module_id

    ! Release old reference if allocated
    if (ref%pool_index /= 0) then
      call pool_release_string(ref)
      call dashboard_track_deallocation(mod_id, ref%str_len, get_bucket_idx(ref%str_len))
    end if

    ! Allocate new pooled string
    size_bytes = len(value)
    ref = pool_get_string(size_bytes)
    call pool_copy_to_ref(ref, value)
    call dashboard_track_allocation(mod_id, size_bytes, get_bucket_idx(size_bytes))
  end subroutine set_pooled_string

  ! Get pooled string value
  function get_pooled_string(ref) result(str)
    type(string_ref), intent(in) :: ref
    character(:), pointer :: str

    if (ref%pool_index /= 0) then
      str => ref%data
    else
      str => null()
    end if
  end function get_pooled_string

  ! Release pooled tokens
  subroutine release_pooled_tokens(cmd)
    type(pooled_command_t), intent(inout) :: cmd
    integer :: i

    if (allocated(cmd%pooled_tokens)) then
      do i = 1, cmd%num_tokens
        if (cmd%pooled_tokens(i)%pool_index /= 0) then
          call dashboard_track_deallocation(MOD_PARSER, &
            cmd%pooled_tokens(i)%str_len, get_bucket_idx(cmd%pooled_tokens(i)%str_len))
          call pool_release_string(cmd%pooled_tokens(i))
        end if
      end do
      deallocate(cmd%pooled_tokens)
    end if
    cmd%num_tokens = 0
  end subroutine release_pooled_tokens

  ! Release all pooled strings in a command
  subroutine release_pooled_command(cmd)
    type(pooled_command_t), intent(inout) :: cmd

    ! Release tokens
    call release_pooled_tokens(cmd)

    ! Release string fields
    if (cmd%input_file%pool_index /= 0) then
      call dashboard_track_deallocation(MOD_PARSER, &
        cmd%input_file%str_len, get_bucket_idx(cmd%input_file%str_len))
      call pool_release_string(cmd%input_file)
    end if

    if (cmd%output_file%pool_index /= 0) then
      call dashboard_track_deallocation(MOD_PARSER, &
        cmd%output_file%str_len, get_bucket_idx(cmd%output_file%str_len))
      call pool_release_string(cmd%output_file)
    end if

    if (cmd%error_file%pool_index /= 0) then
      call dashboard_track_deallocation(MOD_PARSER, &
        cmd%error_file%str_len, get_bucket_idx(cmd%error_file%str_len))
      call pool_release_string(cmd%error_file)
    end if

    if (cmd%heredoc_delimiter%pool_index /= 0) then
      call dashboard_track_deallocation(MOD_PARSER, &
        cmd%heredoc_delimiter%str_len, get_bucket_idx(cmd%heredoc_delimiter%str_len))
      call pool_release_string(cmd%heredoc_delimiter)
    end if

    if (cmd%heredoc_content%pool_index /= 0) then
      call dashboard_track_deallocation(MOD_PARSER, &
        cmd%heredoc_content%str_len, get_bucket_idx(cmd%heredoc_content%str_len))
      call pool_release_string(cmd%heredoc_content)
    end if

    if (cmd%here_string%pool_index /= 0) then
      call dashboard_track_deallocation(MOD_PARSER, &
        cmd%here_string%str_len, get_bucket_idx(cmd%here_string%str_len))
      call pool_release_string(cmd%here_string)
    end if

    if (cmd%group_content%pool_index /= 0) then
      call dashboard_track_deallocation(MOD_PARSER, &
        cmd%group_content%str_len, get_bucket_idx(cmd%group_content%str_len))
      call pool_release_string(cmd%group_content)
    end if

    if (cmd%subshell_content%pool_index /= 0) then
      call dashboard_track_deallocation(MOD_PARSER, &
        cmd%subshell_content%str_len, get_bucket_idx(cmd%subshell_content%str_len))
      call pool_release_string(cmd%subshell_content)
    end if

    ! Reset the command
    call init_pooled_command(cmd)
  end subroutine release_pooled_command

  ! Convert legacy command_t to pooled_command_t
  subroutine convert_to_pooled_command(legacy_cmd, pooled_cmd)
    type(command_t), intent(in) :: legacy_cmd
    type(pooled_command_t), intent(out) :: pooled_cmd
    integer :: i

    ! Initialize the pooled command
    call init_pooled_command(pooled_cmd)

    ! Copy simple fields
    pooled_cmd%append_output = legacy_cmd%append_output
    pooled_cmd%append_error = legacy_cmd%append_error
    pooled_cmd%force_clobber = legacy_cmd%force_clobber
    pooled_cmd%redirect_stderr_to_stdout = legacy_cmd%redirect_stderr_to_stdout
    pooled_cmd%redirect_stdout_to_stderr = legacy_cmd%redirect_stdout_to_stderr
    pooled_cmd%redirect_both_to_file = legacy_cmd%redirect_both_to_file
    pooled_cmd%background = legacy_cmd%background
    pooled_cmd%separator = legacy_cmd%separator
    pooled_cmd%is_command_group = legacy_cmd%is_command_group
    pooled_cmd%is_subshell = legacy_cmd%is_subshell
    pooled_cmd%heredoc_quoted = legacy_cmd%heredoc_quoted
    pooled_cmd%redirections = legacy_cmd%redirections
    pooled_cmd%num_redirections = legacy_cmd%num_redirections
    pooled_cmd%prefix_assignments = legacy_cmd%prefix_assignments
    pooled_cmd%num_prefix_assignments = legacy_cmd%num_prefix_assignments

    ! Convert tokens
    if (allocated(legacy_cmd%tokens)) then
      call allocate_pooled_tokens(pooled_cmd, legacy_cmd%num_tokens, MAX_TOKEN_LEN)
      do i = 1, legacy_cmd%num_tokens
        call set_pooled_token(pooled_cmd, i, legacy_cmd%tokens(i))
      end do
    end if

    ! Convert string fields
    if (allocated(legacy_cmd%input_file)) then
      call set_pooled_string(pooled_cmd%input_file, legacy_cmd%input_file)
    end if

    if (allocated(legacy_cmd%output_file)) then
      call set_pooled_string(pooled_cmd%output_file, legacy_cmd%output_file)
    end if

    if (allocated(legacy_cmd%error_file)) then
      call set_pooled_string(pooled_cmd%error_file, legacy_cmd%error_file)
    end if

    if (allocated(legacy_cmd%heredoc_delimiter)) then
      call set_pooled_string(pooled_cmd%heredoc_delimiter, legacy_cmd%heredoc_delimiter)
    end if

    if (allocated(legacy_cmd%heredoc_content)) then
      call set_pooled_string(pooled_cmd%heredoc_content, legacy_cmd%heredoc_content)
    end if

    if (allocated(legacy_cmd%here_string)) then
      call set_pooled_string(pooled_cmd%here_string, legacy_cmd%here_string)
    end if

    if (allocated(legacy_cmd%group_content)) then
      call set_pooled_string(pooled_cmd%group_content, legacy_cmd%group_content)
    end if

    if (allocated(legacy_cmd%subshell_content)) then
      call set_pooled_string(pooled_cmd%subshell_content, legacy_cmd%subshell_content)
    end if
  end subroutine convert_to_pooled_command

  ! Helper function to get bucket index for a given size
  function get_bucket_idx(size_bytes) result(idx)
    integer, intent(in) :: size_bytes
    integer :: idx

    if (size_bytes <= 64) then
      idx = 1
    else if (size_bytes <= 256) then
      idx = 2
    else if (size_bytes <= 1024) then
      idx = 3
    else if (size_bytes <= 4096) then
      idx = 4
    else if (size_bytes <= 16384) then
      idx = 5
    else
      idx = 0  ! Too large for pool
    end if
  end function get_bucket_idx

end module pooled_types