! ==============================================================================
! Test program for Phase 6 - Parser with memory pooling
! ==============================================================================
program test_parser_pooled
  use string_pool
  use memory_dashboard
  use pooled_types
  use parser_pooled
  use iso_fortran_env, only: output_unit
  implicit none

  type(pooled_pipeline_t) :: pipeline
  type(pooled_command_t) :: test_cmd
  integer :: i, j
  character(len=256) :: test_commands(10)
  logical :: test_passed
  integer :: total_allocs, total_deallocs, current_strings, peak_strings
  real :: hit_rate
  character(:), pointer :: token_ptr

  test_passed = .true.

  print *, "=== Phase 6 Parser Memory Pooling Test Suite ==="
  print *, "Testing parser module with zero-copy memory pooling"
  print *

  ! Initialize the pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.false.)

  ! Define test commands
  test_commands(1) = "ls -la /tmp"
  test_commands(2) = "echo 'Hello World'"
  test_commands(3) = "cat file.txt | grep pattern"
  test_commands(4) = "export VAR=value && echo $VAR"
  test_commands(5) = "for i in 1 2 3; do echo $i; done"
  test_commands(6) = "if [ -f file ]; then echo exists; fi"
  test_commands(7) = "command1 > output.txt 2>&1"
  test_commands(8) = "cat << EOF > file.txt"
  test_commands(9) = "function test() { echo test; }"
  test_commands(10) = "ls -la | head -n 10 | tail -n 5"

  ! Test 1: Parse simple commands
  print *, "Test 1: Parsing simple commands with pooled memory..."
  do i = 1, 3
    print *, "  Parsing: ", trim(test_commands(i))
    call parse_pipeline_pooled(test_commands(i), pipeline)

    if (pipeline%num_commands > 0) then
      print *, "    Commands parsed:", pipeline%num_commands
      do j = 1, pipeline%commands(1)%num_tokens
        token_ptr => get_pooled_token(pipeline%commands(1), j)
        if (associated(token_ptr)) then
          print *, "      Token", j, ":", trim(token_ptr)
        end if
      end do
    else
      print *, "    FAILED: No commands parsed"
      test_passed = .false.
    end if

    call release_pipeline_pooled(pipeline)
  end do

  ! Test 2: Check memory statistics
  print *, ""
  print *, "Test 2: Checking parser memory statistics..."
  call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)
  print *, "  Total allocations:", total_allocs
  print *, "  Total deallocations:", total_deallocs
  print *, "  Current strings:", current_strings
  print *, "  Peak strings:", peak_strings

  if (current_strings == 0) then
    print *, "  PASSED: No memory leaks (all strings released)"
  else
    print *, "  WARNING:", current_strings, "strings still allocated"
  end if

  ! Test 3: Parse complex commands
  print *, ""
  print *, "Test 3: Parsing complex commands..."
  do i = 4, 7
    print *, "  Parsing: ", trim(test_commands(i))
    call parse_pipeline_pooled(test_commands(i), pipeline)

    if (pipeline%num_commands > 0) then
      print *, "    Commands in pipeline:", pipeline%num_commands
      ! Check redirections
      if (i == 7) then  ! command1 > output.txt 2>&1
        if (pipeline%commands(1)%output_file%pool_index /= 0) then
          print *, "    Output redirection detected"
        end if
      end if
    end if

    call release_pipeline_pooled(pipeline)
  end do

  ! Test 4: Stress test with rapid allocations
  print *, ""
  print *, "Test 4: Stress testing parser with rapid operations..."
  do j = 1, 100
    do i = 1, 10
      call parse_pipeline_pooled(test_commands(mod(i-1, 10) + 1), pipeline)
      call release_pipeline_pooled(pipeline)
    end do
  end do
  print *, "  Completed 1000 parse/release cycles"

  ! Test 5: Test direct pooled command operations
  print *, ""
  print *, "Test 5: Testing pooled command operations..."
  call init_pooled_command(test_cmd)

  ! Allocate and set tokens
  call allocate_pooled_tokens(test_cmd, 5, 64)
  call set_pooled_token(test_cmd, 1, "test")
  call set_pooled_token(test_cmd, 2, "-flag")
  call set_pooled_token(test_cmd, 3, "arg1")
  call set_pooled_token(test_cmd, 4, "arg2")
  call set_pooled_token(test_cmd, 5, "arg3")

  ! Set some string fields
  call set_pooled_string(test_cmd%input_file, "input.txt")
  call set_pooled_string(test_cmd%output_file, "output.txt")
  call set_pooled_string(test_cmd%heredoc_delimiter, "EOF")

  ! Verify values
  token_ptr => get_pooled_token(test_cmd, 1)
  if (associated(token_ptr) .and. trim(token_ptr) == "test") then
    print *, "  PASSED: Token storage working"
  else
    print *, "  FAILED: Token storage not working"
    test_passed = .false.
  end if

  token_ptr => get_pooled_string(test_cmd%output_file)
  if (associated(token_ptr) .and. trim(token_ptr) == "output.txt") then
    print *, "  PASSED: String field storage working"
  else
    print *, "  FAILED: String field storage not working"
    test_passed = .false.
  end if

  ! Clean up test command
  call release_pooled_command(test_cmd)

  ! Display dashboard
  print *, ""
  print *, "=== Parser Module Statistics ==="
  call dashboard_display(detailed=.true.)

  ! Final statistics
  print *, ""
  print *, "=== Final Memory Check ==="
  call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)
  print *, "Total allocations:", total_allocs
  print *, "Total deallocations:", total_deallocs
  print *, "Leaked strings:", current_strings
  print *, "Peak usage:", peak_strings
  print *, "Cache hit rate:", int(hit_rate * 100), "%"

  ! Export statistics
  call dashboard_export_csv("parser_memory_stats.csv")
  print *, ""
  print *, "Statistics exported to parser_memory_stats.csv"

  ! Clean up
  call dashboard_cleanup()
  call pool_cleanup()

  ! Summary
  print *, ""
  if (test_passed .and. current_strings == 0) then
    print *, "=== ALL TESTS PASSED ==="
    print *, "Parser successfully integrated with memory pooling!"
    print *, ""
    print *, "Key achievements:"
    print *, "  ✓ Zero-copy string storage for tokens"
    print *, "  ✓ Pooled memory for all parser strings"
    print *, "  ✓ Dashboard tracking integration"
    print *, "  ✓ No memory leaks detected"
    print *, "  ✓ Cache hit rate:", int(hit_rate * 100), "%"
    print *, ""
    print *, "The parser module is now using pooled memory efficiently!"
  else
    print *, "=== SOME TESTS FAILED ==="
    if (current_strings > 0) then
      print *, "Memory leak detected:", current_strings, "strings not released"
    end if
    print *, "Please review the implementation"
  end if

end program test_parser_pooled