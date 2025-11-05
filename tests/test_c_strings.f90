!===============================================================================
! test_c_strings.f90 - Test program for C string buffer library
!
! This demonstrates that the C interop approach allows strings >128 bytes
! on macOS ARM64 without heap corruption.
!===============================================================================
program test_c_strings
  use, intrinsic :: iso_c_binding
  use fortsh_c_strings
  implicit none

  type(c_string_buffer) :: buf1, buf2, buf3
  character(len=2048) :: fortran_str
  integer :: len, pos
  logical :: success
  character(len=1) :: ch

  print *, '========================================='
  print *, 'Testing C String Buffer Library'
  print *, '========================================='
  print *

  ! Test 1: Create and basic operations
  print *, 'Test 1: Create buffer and set string'
  buf1 = c_string_create(2048)
  if (.not. c_associated(buf1%handle)) then
    print *, 'FAIL: Could not create buffer'
    stop 1
  end if
  print *, 'PASS: Buffer created'

  success = c_string_set(buf1, 'Hello, World!')
  if (.not. success) then
    print *, 'FAIL: Could not set string'
    stop 1
  end if
  print *, 'PASS: String set successfully'

  len = c_string_length(buf1)
  print *, 'Length:', len
  if (len /= 13) then
    print *, 'FAIL: Expected length 13, got', len
    stop 1
  end if
  print *, 'PASS: Length correct'
  print *

  ! Test 2: Long strings (>128 bytes) - THE CRITICAL TEST!
  print *, 'Test 2: Long strings (>128 bytes)'
  print *, 'This is the test that would crash flang-new!'

  ! Create a 500-byte string
  call create_long_string(fortran_str, 500)
  print *, 'Created test string of length:', len_trim(fortran_str)

  success = c_string_set(buf1, fortran_str(1:500))
  if (.not. success) then
    print *, 'FAIL: Could not set long string'
    stop 1
  end if
  print *, 'PASS: Set 500-byte string'

  len = c_string_length(buf1)
  print *, 'Buffer length:', len
  if (len /= 500) then
    print *, 'FAIL: Expected length 500, got', len
    stop 1
  end if
  print *, 'PASS: Long string length correct'
  print *

  ! Test 3: Substring operations (another crash trigger!)
  print *, 'Test 3: Substring operations on long string'
  buf2 = c_string_create(2048)

  ! Extract characters 50-100 (Fortran 1-based)
  success = c_string_substring(buf2, buf1, 50, 100)
  if (.not. success) then
    print *, 'FAIL: Could not extract substring'
    stop 1
  end if
  print *, 'PASS: Extracted substring(50:100)'

  len = c_string_length(buf2)
  if (len /= 51) then  ! 100 - 50 + 1 = 51 characters
    print *, 'FAIL: Expected substring length 51, got', len
    stop 1
  end if
  print *, 'PASS: Substring length correct'
  print *

  ! Test 4: Buffer manipulation
  print *, 'Test 4: Insert, delete, append operations'

  buf3 = c_string_create(2048)
  success = c_string_set(buf3, 'Hello World')

  ! Insert " Beautiful" at position 6 (after "Hello")
  success = c_string_insert(buf3, 7, ' Beautiful')
  if (.not. success) then
    print *, 'FAIL: Could not insert text'
    stop 1
  end if

  call c_string_to_fortran(buf3, fortran_str)
  print *, 'After insert:', trim(fortran_str)
  if (trim(fortran_str) /= 'Hello Beautiful World') then
    print *, 'FAIL: Insert produced wrong result'
    stop 1
  end if
  print *, 'PASS: Insert operation'

  ! Append text
  success = c_string_append(buf3, '!')
  call c_string_to_fortran(buf3, fortran_str)
  print *, 'After append:', trim(fortran_str)
  if (trim(fortran_str) /= 'Hello Beautiful World!') then
    print *, 'FAIL: Append produced wrong result'
    stop 1
  end if
  print *, 'PASS: Append operation'

  ! Delete "Beautiful " (10 characters at position 7)
  success = c_string_delete(buf3, 7, 10)
  call c_string_to_fortran(buf3, fortran_str)
  print *, 'After delete:', trim(fortran_str)
  if (trim(fortran_str) /= 'Hello World!') then
    print *, 'FAIL: Delete produced wrong result'
    stop 1
  end if
  print *, 'PASS: Delete operation'
  print *

  ! Test 5: Character access
  print *, 'Test 5: Individual character access'
  success = c_string_set(buf1, 'ABCDEFGH')

  ch = c_string_get_char(buf1, 5)  ! Should be 'E'
  if (ch /= 'E') then
    print *, 'FAIL: Get char at 5 returned', ch, 'expected E'
    stop 1
  end if
  print *, 'PASS: Get character'

  success = c_string_set_char(buf1, 5, 'X')  ! Change 'E' to 'X'
  call c_string_to_fortran(buf1, fortran_str)
  if (trim(fortran_str) /= 'ABCDXFGH') then
    print *, 'FAIL: Set char produced:', trim(fortran_str)
    stop 1
  end if
  print *, 'PASS: Set character'
  print *

  ! Test 6: Find operation
  print *, 'Test 6: Find substring'
  success = c_string_set(buf1, 'The quick brown fox jumps over the lazy dog')

  pos = c_string_find(buf1, 'fox')
  if (pos /= 17) then  ! 1-based position
    print *, 'FAIL: Find returned', pos, 'expected 17'
    stop 1
  end if
  print *, 'PASS: Find operation (pos=', pos, ')'

  pos = c_string_find(buf1, 'cat')  ! Not present
  if (pos /= 0) then
    print *, 'FAIL: Find should return 0 for not found'
    stop 1
  end if
  print *, 'PASS: Find not-present string'
  print *

  ! Test 7: Fortran interop
  print *, 'Test 7: Fortran string conversion'

  fortran_str = 'Fortran string with spaces    '
  success = c_string_from_fortran(buf1, fortran_str)

  len = c_string_length(buf1)
  call c_string_to_fortran(buf1, fortran_str)
  print *, 'Converted:', trim(fortran_str)
  print *, 'Length:', len

  if (trim(fortran_str) /= 'Fortran string with spaces') then
    print *, 'FAIL: Fortran conversion'
    stop 1
  end if
  print *, 'PASS: Fortran string conversion'
  print *

  ! Test 8: Stress test with very long command lines
  print *, 'Test 8: STRESS TEST - 1024 byte command line'
  call create_long_string(fortran_str, 1024)
  success = c_string_set(buf1, fortran_str(1:1024))
  if (.not. success) then
    print *, 'FAIL: Could not set 1024-byte string'
    stop 1
  end if

  len = c_string_length(buf1)
  if (len /= 1024) then
    print *, 'FAIL: 1024-byte string has wrong length:', len
    stop 1
  end if

  ! Try substring operations on the huge string
  success = c_string_substring(buf2, buf1, 1, 1024)
  if (.not. success) then
    print *, 'FAIL: Could not substring 1024-byte string'
    stop 1
  end if

  ! Try insertion (this would definitely crash flang-new!)
  success = c_string_insert(buf1, 512, ' INSERTED ')
  if (.not. success) then
    print *, 'FAIL: Could not insert into 1024-byte string'
    stop 1
  end if

  len = c_string_length(buf1)
  if (len /= 1034) then  ! 1024 + 10
    print *, 'FAIL: After insert, expected 1034, got', len
    stop 1
  end if

  print *, 'PASS: 1024-byte stress test'
  print *, '***** THIS WOULD HAVE CRASHED FLANG-NEW! *****'
  print *

  ! Cleanup
  call c_string_destroy(buf1)
  call c_string_destroy(buf2)
  call c_string_destroy(buf3)

  print *, '========================================='
  print *, 'ALL TESTS PASSED!'
  print *, '========================================='
  print *, 'The C interop approach successfully'
  print *, 'handles strings >128 bytes without'
  print *, 'triggering flang-new heap corruption!'
  print *, '========================================='

contains

  subroutine create_long_string(str, length)
    character(len=*), intent(out) :: str
    integer, intent(in) :: length
    integer :: i
    character(len=26), parameter :: alphabet = 'abcdefghijklmnopqrstuvwxyz'

    str = ''
    do i = 1, length
      str(i:i) = alphabet(mod(i-1, 26) + 1:mod(i-1, 26) + 1)
    end do
  end subroutine create_long_string

end program test_c_strings
