program test_tilde_expansion
  use iso_c_binding
  implicit none

  ! Password database entry for getpwnam
  type, bind(C) :: passwd_t
    type(c_ptr) :: pw_name
    type(c_ptr) :: pw_passwd
    integer(c_int) :: pw_uid
    integer(c_int) :: pw_gid
    type(c_ptr) :: pw_gecos
    type(c_ptr) :: pw_dir
    type(c_ptr) :: pw_shell
  end type passwd_t

  interface
    function c_getpwnam(name) bind(C, name="getpwnam")
      use iso_c_binding
      import :: passwd_t
      character(kind=c_char), dimension(*), intent(in) :: name
      type(c_ptr) :: c_getpwnam
    end function c_getpwnam
  end interface

  integer :: test_count, pass_count
  character(256) :: home, pwd, oldpwd
  character(:), allocatable :: expected_home, expected_pwd, expected_oldpwd
  integer :: status

  test_count = 0
  pass_count = 0

  ! Get actual environment variables
  call get_environment_variable('HOME', home, status=status)
  if (status /= 0 .or. len_trim(home) == 0) then
    print *, "WARNING: HOME not set, using default"
    home = "/home/testuser"
  end if
  expected_home = trim(home)

  call get_environment_variable('PWD', pwd, status=status)
  if (status == 0 .and. len_trim(pwd) > 0) then
    expected_pwd = trim(pwd)
  else
    expected_pwd = expected_home  ! fallback
  end if

  call get_environment_variable('OLDPWD', oldpwd, status=status)
  if (status == 0 .and. len_trim(oldpwd) > 0) then
    expected_oldpwd = trim(oldpwd)
  else
    expected_oldpwd = expected_home  ! fallback
  end if

  print *, "=== Tilde Expansion Tests ==="
  print *, "HOME=", trim(expected_home)
  print *, "PWD=", trim(expected_pwd)
  print *, "OLDPWD=", trim(expected_oldpwd)
  print *, ""

  ! Test 1: Simple ~
  test_count = test_count + 1
  if (test_expansion("~", expected_home)) pass_count = pass_count + 1

  ! Test 2: ~/path
  test_count = test_count + 1
  if (test_expansion("~/documents", trim(expected_home) // "/documents")) pass_count = pass_count + 1

  ! Test 3: ~+
  test_count = test_count + 1
  if (test_expansion("~+", expected_pwd)) pass_count = pass_count + 1

  ! Test 4: ~-
  test_count = test_count + 1
  if (test_expansion("~-", expected_oldpwd)) pass_count = pass_count + 1

  ! Test 5: No tilde
  test_count = test_count + 1
  if (test_expansion("notilde", "notilde")) pass_count = pass_count + 1

  ! Test 6: ~root (if root user exists)
  test_count = test_count + 1
  if (test_user_expansion("~root")) pass_count = pass_count + 1

  ! Print summary
  print *, ""
  print *, "=== Test Summary ==="
  print *, "Passed:", pass_count, "/", test_count
  if (pass_count == test_count) then
    print *, "✓ All tests PASSED!"
    stop 0
  else
    print *, "✗", test_count - pass_count, "tests FAILED"
    stop 1
  end if

contains

  logical function test_expansion(input, expected)
    character(*), intent(in) :: input, expected
    character(:), allocatable :: result

    result = expand_tilde_standalone(input)
    test_expansion = (trim(result) == trim(expected))

    if (test_expansion) then
      print *, "✓ '", trim(input), "' → '", trim(result), "'"
    else
      print *, "✗ '", trim(input), "' → '", trim(result), "', expected '", trim(expected), "'"
    end if
  end function test_expansion

  logical function test_user_expansion(input)
    character(*), intent(in) :: input
    character(:), allocatable :: result

    result = expand_tilde_standalone(input)
    ! Just check it got expanded (doesn't still have ~)
    test_user_expansion = (result(1:1) /= '~')

    if (test_user_expansion) then
      print *, "✓ '", trim(input), "' → '", trim(result), "'"
    else
      print *, "✗ '", trim(input), "' was not expanded"
    end if
  end function test_user_expansion

  ! Standalone expand_tilde function for testing
  function expand_tilde_standalone(word) result(expanded)
    character(*), intent(in) :: word
    character(:), allocatable :: expanded
    character(256) :: home_buf, username, pwd_buf, oldpwd_buf
    character(:), allocatable :: home, pwd, oldpwd
    character(256) :: c_str
    type(c_ptr) :: passwd_ptr, dir_ptr
    type(passwd_t), pointer :: passwd
    integer :: slash_pos, i, status
    character(1) :: next_char

    expanded = word

    if (len_trim(word) == 0 .or. word(1:1) /= '~') return

    ! Handle single ~
    if (len_trim(word) == 1) then
      call get_environment_variable('HOME', home_buf, status=status)
      if (status == 0 .and. len_trim(home_buf) > 0) then
        expanded = trim(home_buf)
      else
        expanded = word
      end if
      return
    end if

    next_char = word(2:2)

    ! ~/path
    if (next_char == '/') then
      call get_environment_variable('HOME', home_buf, status=status)
      if (status == 0 .and. len_trim(home_buf) > 0) then
        expanded = trim(home_buf) // word(2:)
      else
        expanded = word
      end if
      return
    end if

    ! ~+
    if (next_char == '+') then
      if (len_trim(word) == 2 .or. (len_trim(word) > 2 .and. word(3:3) == '/')) then
        call get_environment_variable('PWD', pwd_buf, status=status)
        if (status == 0 .and. len_trim(pwd_buf) > 0) then
          if (len_trim(word) == 2) then
            expanded = trim(pwd_buf)
          else
            expanded = trim(pwd_buf) // word(3:)
          end if
        else
          expanded = word
        end if
        return
      end if
    end if

    ! ~-
    if (next_char == '-') then
      if (len_trim(word) == 2 .or. (len_trim(word) > 2 .and. word(3:3) == '/')) then
        call get_environment_variable('OLDPWD', oldpwd_buf, status=status)
        if (status == 0 .and. len_trim(oldpwd_buf) > 0) then
          if (len_trim(word) == 2) then
            expanded = trim(oldpwd_buf)
          else
            expanded = trim(oldpwd_buf) // word(3:)
          end if
        else
          expanded = word
        end if
        return
      end if
    end if

    ! ~username
    slash_pos = index(word, '/')
    if (slash_pos > 0) then
      username = word(2:slash_pos-1)
    else
      username = word(2:)
    end if

    c_str = trim(username) // c_null_char
    passwd_ptr = c_getpwnam(c_str)

    if (c_associated(passwd_ptr)) then
      call c_f_pointer(passwd_ptr, passwd)
      dir_ptr = passwd%pw_dir

      if (c_associated(dir_ptr)) then
        ! Convert C string pointer to Fortran string
        home = c_to_f_string(dir_ptr)

        if (slash_pos > 0) then
          expanded = trim(home) // word(slash_pos:)
        else
          expanded = home
        end if
        return
      end if
    end if

    expanded = word
  end function expand_tilde_standalone

  ! Convert C string pointer to Fortran string
  function c_to_f_string(c_str_ptr) result(f_str)
    type(c_ptr), intent(in) :: c_str_ptr
    character(:), allocatable :: f_str
    character(kind=c_char), dimension(:), pointer :: c_str
    integer :: i, str_len

    call c_f_pointer(c_str_ptr, c_str, [256])

    ! Find length (look for null terminator)
    str_len = 0
    do i = 1, 256
      if (c_str(i) == c_null_char) exit
      str_len = i
    end do

    ! Allocate and copy
    allocate(character(str_len) :: f_str)
    do i = 1, str_len
      f_str(i:i) = c_str(i)
    end do
  end function c_to_f_string

end program test_tilde_expansion
