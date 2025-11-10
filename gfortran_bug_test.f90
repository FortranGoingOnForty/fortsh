! gfortran stack corruption bug reproducer for macOS ARM64
!
! Compile: gfortran -o bug_test gfortran_bug_test.f90
! Run: ./bug_test
! Expected: Should print "SUCCESS: Test completed"
! Actual on macOS ARM64: Segmentation fault
!
! Bug: gfortran incorrectly handles large derived types on macOS ARM64,
!      corrupting the stack frame during function returns

program gfortran_macos_arm64_bug
  implicit none

  ! Define a large derived type (>8KB)
  type :: large_state_type
    character(len=1024) :: input_buffer
    character(len=1024) :: output_buffer
    character(len=256) :: temp_strings(20)
    integer :: counters(100)
    logical :: flags(50)
    real :: metrics(50)
  end type large_state_type

  type(large_state_type) :: state
  integer :: i

  print *, "Testing gfortran on macOS ARM64..."
  print *, "Size of derived type:", sizeof(state), "bytes"

  ! Initialize the state
  state%input_buffer = "Initial input"
  state%output_buffer = ""
  do i = 1, 20
    write(state%temp_strings(i), '(a,i0)') "String_", i
  end do
  state%counters = 0
  state%flags = .false.
  state%metrics = 0.0

  ! Test 1: Pass to subroutine (often crashes on return)
  print *, "Test 1: Passing to subroutine..."
  call process_with_parameter(state)
  print *, "  Passed!"

  ! Test 2: Function returning modified copy (often crashes)
  print *, "Test 2: Function with large type..."
  state = modify_and_return(state)
  print *, "  Passed!"

  ! Test 3: Multiple nested calls (stress test)
  print *, "Test 3: Nested calls..."
  call nested_level1(state)
  print *, "  Passed!"

  print *, "SUCCESS: Test completed without segfault!"

contains

  ! Subroutine that takes large type as parameter
  subroutine process_with_parameter(s)
    type(large_state_type), intent(inout) :: s
    character(len=100) :: local_work  ! Local variable to check stack corruption

    local_work = "Processing..."
    s%counters(1) = s%counters(1) + 1
    s%output_buffer = trim(s%input_buffer) // "_processed"

    ! Stack corruption often happens here during return
  end subroutine process_with_parameter

  ! Function that returns large type
  function modify_and_return(s) result(modified)
    type(large_state_type), intent(in) :: s
    type(large_state_type) :: modified

    modified = s
    modified%counters(2) = modified%counters(2) + 10
    modified%flags(1) = .true.

    ! Return with large structure often corrupts stack
  end function modify_and_return

  ! Nested calls to stress test stack handling
  subroutine nested_level1(s)
    type(large_state_type), intent(inout) :: s

    s%counters(3) = s%counters(3) + 1
    call nested_level2(s)
  end subroutine nested_level1

  subroutine nested_level2(s)
    type(large_state_type), intent(inout) :: s

    s%counters(4) = s%counters(4) + 1
    call nested_level3(s)
  end subroutine nested_level2

  subroutine nested_level3(s)
    type(large_state_type), intent(inout) :: s

    s%counters(5) = s%counters(5) + 1
    s%metrics(1) = 3.14159
  end subroutine nested_level3

end program gfortran_macos_arm64_bug