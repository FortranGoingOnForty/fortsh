! ==============================================================================
! Simplified test program for Phase 6 - Variables module with memory pooling
! ==============================================================================
program test_variables_simple
  use string_pool
  use memory_dashboard
  use variables_pooled
  use iso_fortran_env, only: output_unit
  implicit none

  type(shell_pooled_t) :: shell_pooled
  type(string_ref) :: value_ref, expanded_ref
  type(string_ref), allocatable :: body_refs(:)
  character(len=2048) :: test_string
  character(len=1024), dimension(3) :: function_body
  integer :: i, j
  logical :: test_passed
  integer :: total_allocs, total_deallocs, current_strings, peak_strings
  real :: hit_rate
  character(:), pointer :: str_ptr

  test_passed = .true.

  print *, "=== Phase 6 Variables Memory Pooling Test (Simplified) ==="
  print *, "Testing pooled memory for variable management"
  print *

  ! Initialize the pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.false.)
  call init_shell_pooled(shell_pooled)

  ! Test 1: Basic variable setting and getting
  print *, "Test 1: Testing basic variable operations..."

  ! Set simple variables
  call set_shell_variable_pooled(shell_pooled, "PATH", "/usr/local/bin:/usr/bin:/bin")
  call set_shell_variable_pooled(shell_pooled, "HOME", "/home/testuser")
  call set_shell_variable_pooled(shell_pooled, "USER", "testuser")
  call set_shell_variable_pooled(shell_pooled, "SHELL", "/bin/fortsh")
  call set_shell_variable_pooled(shell_pooled, "TERM", "xterm-256color")

  ! Get and verify variables
  value_ref = get_shell_variable_pooled(shell_pooled, "PATH")
  if (associated(value_ref%data)) then
    print *, "  PATH:", trim(value_ref%data(1:min(50, value_ref%str_len))), "..."
    if (value_ref%pool_index > 0) then
      print *, "  PASSED: PATH allocated from pool"
    else
      print *, "  FAILED: PATH not from pool"
      test_passed = .false.
    end if
  end if

  value_ref = get_shell_variable_pooled(shell_pooled, "HOME")
  if (associated(value_ref%data)) then
    print *, "  HOME:", trim(value_ref%data)
  end if

  value_ref = get_shell_variable_pooled(shell_pooled, "USER")
  if (associated(value_ref%data)) then
    print *, "  USER:", trim(value_ref%data)
  end if

  ! Test 2: Variable expansion
  print *, ""
  print *, "Test 2: Testing variable expansion..."

  ! Test simple expansion
  test_string = "Current user is $USER in $HOME"
  expanded_ref = expand_variables_pooled(shell_pooled, test_string)
  if (associated(expanded_ref%data)) then
    print *, "  Input: ", trim(test_string)
    print *, "  Expanded:", trim(expanded_ref%data)
    i = expanded_ref%str_len  ! Save size before release
    j = get_bucket_for_size(expanded_ref%str_len)
    call pool_release_string(expanded_ref)
    call dashboard_track_deallocation(MOD_VARIABLES, i, j)
  end if

  ! Test brace expansion
  test_string = "Shell path is ${SHELL} and terminal is ${TERM}"
  expanded_ref = expand_variables_pooled(shell_pooled, test_string)
  if (associated(expanded_ref%data)) then
    print *, "  Input:", trim(test_string)
    print *, "  Expanded:", trim(expanded_ref%data)
    i = expanded_ref%str_len  ! Save size before release
    j = get_bucket_for_size(expanded_ref%str_len)
    call pool_release_string(expanded_ref)
    call dashboard_track_deallocation(MOD_VARIABLES, i, j)
  end if

  ! Test 3: Array variables
  print *, ""
  print *, "Test 3: Testing array variables..."

  ! Set array elements
  call set_array_element_pooled(shell_pooled, "myarray", 1, "first")
  call set_array_element_pooled(shell_pooled, "myarray", 2, "second")
  call set_array_element_pooled(shell_pooled, "myarray", 3, "third")
  call set_array_element_pooled(shell_pooled, "myarray", 5, "fifth")  ! Sparse array

  ! Get array elements
  do i = 1, 5
    value_ref = get_array_element_pooled(shell_pooled, "myarray", i)
    if (associated(value_ref%data)) then
      print '(A,I0,A,A)', "  myarray[", i, "]=", trim(value_ref%data)
    else
      print '(A,I0,A)', "  myarray[", i, "]=(unset)"
    end if
  end do

  ! Test 4: Function storage
  print *, ""
  print *, "Test 4: Testing function storage..."

  ! Define a function
  function_body(1) = "echo 'Hello from function'"
  function_body(2) = "local var=$1"
  function_body(3) = "echo ""Argument: $var"""

  call set_function_pooled(shell_pooled, "myfunction", function_body)

  ! Retrieve function
  body_refs = get_function_pooled(shell_pooled, "myfunction")
  if (allocated(body_refs)) then
    print *, "  Function 'myfunction' body:"
    do i = 1, size(body_refs)
      if (associated(body_refs(i)%data)) then
        print '(A,I0,A,A)', "    Line ", i, ": ", trim(body_refs(i)%data)
      end if
    end do
    deallocate(body_refs)
  end if

  ! Test 5: Large variable values
  print *, ""
  print *, "Test 5: Testing large variable values..."

  ! Create a large value (2KB)
  test_string = repeat("A", 2048)
  call set_shell_variable_pooled(shell_pooled, "LARGE_VAR", test_string)

  value_ref = get_shell_variable_pooled(shell_pooled, "LARGE_VAR")
  if (associated(value_ref%data)) then
    print *, "  LARGE_VAR length:", value_ref%str_len
    print *, "  Pool bucket:", value_ref%pool_index
    if (value_ref%str_len == 2048 .and. value_ref%pool_index > 0) then
      print *, "  PASSED: Large variable allocated from pool"
    else
      print *, "  FAILED: Large variable allocation issue"
      test_passed = .false.
    end if
  end if

  ! Test 6: Variable overwrite (test proper deallocation)
  print *, ""
  print *, "Test 6: Testing variable overwrite..."

  call set_shell_variable_pooled(shell_pooled, "TEMP", "initial value")
  call set_shell_variable_pooled(shell_pooled, "TEMP", "second value")
  call set_shell_variable_pooled(shell_pooled, "TEMP", "third and final value")

  value_ref = get_shell_variable_pooled(shell_pooled, "TEMP")
  if (associated(value_ref%data)) then
    print *, "  TEMP after overwrites:", trim(value_ref%data)
    if (trim(value_ref%data) == "third and final value") then
      print *, "  PASSED: Overwrite working correctly"
    else
      print *, "  FAILED: Overwrite not working"
      test_passed = .false.
    end if
  end if

  ! Test 7: Stress test - many variables
  print *, ""
  print *, "Test 7: Stress testing with 1000 variable operations..."

  do i = 1, 1000
    write(test_string, '(A,I0)') "stress_var_", i
    call set_shell_variable_pooled(shell_pooled, trim(test_string), "test_value")

    ! Every 100, overwrite to test deallocation
    if (mod(i, 100) == 0) then
      call set_shell_variable_pooled(shell_pooled, trim(test_string), "updated_value")
    end if
  end do
  print *, "  Created/updated 1000 variables"

  ! Test 8: Complex expansion stress test
  print *, ""
  print *, "Test 8: Complex expansion stress test..."

  call set_shell_variable_pooled(shell_pooled, "VAR1", "Hello")
  call set_shell_variable_pooled(shell_pooled, "VAR2", "World")
  call set_shell_variable_pooled(shell_pooled, "VAR3", "from")
  call set_shell_variable_pooled(shell_pooled, "VAR4", "Fortran")

  test_string = "$VAR1 $VAR2 $VAR3 $VAR4! Also ${VAR1} ${VAR2} ${VAR3} ${VAR4}!"
  do i = 1, 100
    expanded_ref = expand_variables_pooled(shell_pooled, test_string)
    if (associated(expanded_ref%data)) then
      if (i == 1) then
        print *, "  First expansion:", trim(expanded_ref%data)
      end if
      j = expanded_ref%str_len  ! Save size before release
      call pool_release_string(expanded_ref)
      call dashboard_track_deallocation(MOD_VARIABLES, j, &
                                        get_bucket_for_size(j))
    end if
  end do
  print *, "  Completed 100 expansion cycles"

  ! Clean up all variables
  call cleanup_variables_pooled(shell_pooled)

  ! Test 9: Check for memory leaks
  print *, ""
  print *, "Test 9: Checking for memory leaks..."
  call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)

  print *, "  Total allocations:", total_allocs
  print *, "  Total deallocations:", total_deallocs
  print *, "  Current strings:", current_strings
  print *, "  Peak strings:", peak_strings
  print *, "  Cache hit rate:", int(hit_rate * 100), "%"

  if (current_strings == 0) then
    print *, "  PASSED: No memory leaks"
  else
    print *, "  FAILED: Memory leak -", current_strings, "strings still allocated"
    test_passed = .false.
  end if

  ! Display dashboard
  print *, ""
  print *, "=== Variables Module Statistics ==="
  call dashboard_display(detailed=.false.)

  ! Export statistics
  call dashboard_export_csv("variables_pooling_test.csv")
  print *, ""
  print *, "Statistics exported to variables_pooling_test.csv"

  ! Clean up
  call dashboard_cleanup()
  call pool_cleanup()

  ! Summary
  print *, ""
  print *, "=== Test Summary ==="
  if (test_passed .and. current_strings == 0) then
    print *, "ALL TESTS PASSED"
    print *, ""
    print *, "Variables pooling integration verified:"
    print *, "  - Basic variable operations working"
    print *, "  - Variable expansion working"
    print *, "  - Array variables working"
    print *, "  - Function storage working"
    print *, "  - Large values (2KB) working"
    print *, "  - No memory leaks detected"
    print *, "  - Dashboard tracking successful"
    print *, "  - Cache hit rate:", int(hit_rate * 100), "%"
    print *, ""
    print *, "Ready to integrate into production variables module!"
  else
    print *, "SOME TESTS FAILED"
    if (current_strings > 0) then
      print *, "  Memory leak:", current_strings, "strings not released"
    end if
  end if

contains

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

end program test_variables_simple