! ==============================================================================
! Test program for Phase 6 - Expansion module with memory pooling
! ==============================================================================
program test_expansion_pooled
  use shell_types
  use string_pool
  use memory_dashboard
  use expansion_pooled
  use variables
  use iso_fortran_env, only: output_unit
  implicit none

  type(shell_state_t) :: shell
  type(string_ref) :: result_ref
  type(string_ref) :: input_ref, pattern_ref, replacement_ref, output_ref
  integer :: i, j
  logical :: test_passed
  integer :: total_allocs, total_deallocs, current_strings, peak_strings
  real :: hit_rate
  character(len=256) :: test_expressions(10)
  character(:), pointer :: result_ptr

  test_passed = .true.

  print *, "=== Phase 6 Expansion Memory Pooling Test Suite ==="
  print *, "Testing expansion module with zero-copy memory pooling"
  print *

  ! Initialize the pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.false.)

  ! Initialize shell state
  call init_shell_state(shell)

  ! Set up some test variables
  call set_shell_variable(shell, "USER", "testuser")
  call set_shell_variable(shell, "HOME", "/home/testuser")
  call set_shell_variable(shell, "PATH", "/usr/bin:/bin")
  call set_shell_variable(shell, "LANG", "en_US.UTF-8")
  call set_shell_variable(shell, "TEST_VAR", "Hello World")
  call set_shell_variable(shell, "NUMBER", "42")

  ! Define test expressions
  test_expressions(1) = "${USER}"
  test_expressions(2) = "${HOME}"
  test_expressions(3) = "${PATH}"
  test_expressions(4) = "${TEST_VAR@U}"     ! Uppercase transformation
  test_expressions(5) = "${TEST_VAR@L}"     ! Lowercase transformation
  test_expressions(6) = "${NUMBER}"
  test_expressions(7) = "${NONEXISTENT}"    ! Test undefined variable
  test_expressions(8) = "${USER@Q}"         ! Quote value
  test_expressions(9) = "${TEST_VAR@u}"     ! Capitalize first
  test_expressions(10) = "${LANG}"

  ! Test 1: Basic variable expansion
  print *, "Test 1: Basic variable expansion with pooled memory..."
  do i = 1, 6
    print *, "  Expanding:", trim(test_expressions(i))
    result_ref = parameter_expansion_pooled(shell, test_expressions(i))

    if (result_ref%pool_index /= 0) then
      result_ptr => result_ref%data
      if (associated(result_ptr)) then
        print *, "    Result:", trim(result_ptr)

        ! Verify some expected results
        select case(i)
        case(1)
          if (trim(result_ptr) /= "testuser") then
            print *, "    FAILED: Expected 'testuser'"
            test_passed = .false.
          end if
        case(2)
          if (trim(result_ptr) /= "/home/testuser") then
            print *, "    FAILED: Expected '/home/testuser'"
            test_passed = .false.
          end if
        case(4)
          if (trim(result_ptr) /= "HELLO WORLD") then
            print *, "    FAILED: Expected 'HELLO WORLD'"
            test_passed = .false.
          end if
        case(5)
          if (trim(result_ptr) /= "hello world") then
            print *, "    FAILED: Expected 'hello world'"
            test_passed = .false.
          end if
        end select
      else
        print *, "    Result: NULL pointer"
        test_passed = .false.
      end if
    else
      print *, "    Result: Not allocated from pool"
      test_passed = .false.
    end if

    ! Release the result
    call pool_release_string(result_ref)
    call dashboard_track_deallocation(MOD_EXPANSION, result_ref%str_len, get_bucket_idx(result_ref%str_len))
  end do

  ! Test 2: Check memory statistics
  print *, ""
  print *, "Test 2: Checking expansion memory statistics..."
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

  ! Test 3: Pattern substitution
  print *, ""
  print *, "Test 3: Testing pattern substitution with pooled memory..."

  ! Allocate pooled strings for substitution test
  input_ref = pool_get_string(256)
  pattern_ref = pool_get_string(64)
  replacement_ref = pool_get_string(64)
  call dashboard_track_allocation(MOD_EXPANSION, 256, get_bucket_idx(256))
  call dashboard_track_allocation(MOD_EXPANSION, 64, get_bucket_idx(64))
  call dashboard_track_allocation(MOD_EXPANSION, 64, get_bucket_idx(64))

  call pool_copy_to_ref(input_ref, "Hello World, Hello Universe")
  call pool_copy_to_ref(pattern_ref, "Hello")
  call pool_copy_to_ref(replacement_ref, "Goodbye")

  ! Test greedy substitution (replace all)
  call pattern_substitution_pooled(input_ref, pattern_ref, replacement_ref, &
                                   greedy=.true., at_start=.false., output_ref=output_ref)

  if (output_ref%pool_index /= 0) then
    result_ptr => output_ref%data
    if (associated(result_ptr)) then
      print *, "  Input:", trim(input_ref%data)
      print *, "  Pattern:", trim(pattern_ref%data)
      print *, "  Replacement:", trim(replacement_ref%data)
      print *, "  Result:", trim(result_ptr)

      if (trim(result_ptr) == "Goodbye World, Goodbye Universe") then
        print *, "  PASSED: Pattern substitution working"
      else
        print *, "  FAILED: Expected 'Goodbye World, Goodbye Universe'"
        test_passed = .false.
      end if
    end if
  end if

  ! Clean up substitution test
  call pool_release_string(input_ref)
  call pool_release_string(pattern_ref)
  call pool_release_string(replacement_ref)
  call pool_release_string(output_ref)
  call dashboard_track_deallocation(MOD_EXPANSION, 256, get_bucket_idx(256))
  call dashboard_track_deallocation(MOD_EXPANSION, 64, get_bucket_idx(64))
  call dashboard_track_deallocation(MOD_EXPANSION, 64, get_bucket_idx(64))
  call dashboard_track_deallocation(MOD_EXPANSION, 2048, get_bucket_idx(2048))

  ! Test 4: Stress test with rapid expansions
  print *, ""
  print *, "Test 4: Stress testing expansion with 1000 operations..."
  do i = 1, 1000
    ! Cycle through different expressions
    j = mod(i-1, 10) + 1
    result_ref = parameter_expansion_pooled(shell, test_expressions(j))
    call pool_release_string(result_ref)
    call dashboard_track_deallocation(MOD_EXPANSION, result_ref%str_len, get_bucket_idx(result_ref%str_len))
  end do
  print *, "  Completed 1000 expansion/release cycles"

  ! Test 5: Arithmetic evaluation
  print *, ""
  print *, "Test 5: Testing arithmetic evaluation with pooled memory..."
  block
    character(len=64) :: arith_expr
    arith_expr = "42"
    result_ref = evaluate_arithmetic_pooled(shell, arith_expr)

    if (result_ref%pool_index /= 0) then
      result_ptr => result_ref%data
      if (associated(result_ptr)) then
        print *, "  Expression:", trim(arith_expr)
        print *, "  Result:", trim(result_ptr)

        if (trim(result_ptr) == "42") then
          print *, "  PASSED: Arithmetic evaluation working"
        else
          print *, "  FAILED: Expected '42'"
          test_passed = .false.
        end if
      end if
    end if

    call pool_release_string(result_ref)
    call dashboard_track_deallocation(MOD_EXPANSION, result_ref%str_len, get_bucket_idx(result_ref%str_len))
  end block

  ! Display dashboard
  print *, ""
  print *, "=== Expansion Module Statistics ==="
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
  call dashboard_export_csv("expansion_memory_stats.csv")
  print *, ""
  print *, "Statistics exported to expansion_memory_stats.csv"

  ! Clean up shell state
  call cleanup_shell_state(shell)

  ! Clean up pool and dashboard
  call dashboard_cleanup()
  call pool_cleanup()

  ! Summary
  print *, ""
  if (test_passed .and. current_strings == 0) then
    print *, "=== ALL TESTS PASSED ==="
    print *, "Expansion module successfully integrated with memory pooling!"
    print *, ""
    print *, "Key achievements:"
    print *, "  ✓ Variable expansion using pooled memory"
    print *, "  ✓ Pattern substitution with zero-copy strings"
    print *, "  ✓ Transformation operations pooled"
    print *, "  ✓ No memory leaks detected"
    print *, "  ✓ Cache hit rate:", int(hit_rate * 100), "%"
    print *, ""
    print *, "The expansion module is now using pooled memory efficiently!"
  else
    print *, "=== SOME TESTS FAILED ==="
    if (current_strings > 0) then
      print *, "Memory leak detected:", current_strings, "strings not released"
    end if
    print *, "Please review the implementation"
  end if

contains

  subroutine init_shell_state(shell)
    type(shell_state_t), intent(out) :: shell

    ! Initialize basic shell state
    shell%num_variables = 0
    shell%num_aliases = 0
    shell%num_functions = 0
    shell%last_exit_status = 0
    shell%running = .true.
    shell%is_interactive = .false.
  end subroutine init_shell_state

  subroutine cleanup_shell_state(shell)
    type(shell_state_t), intent(inout) :: shell

    ! Clean up any allocated resources
    shell%num_variables = 0
  end subroutine cleanup_shell_state

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
      idx = 0
    end if
  end function get_bucket_idx

end program test_expansion_pooled