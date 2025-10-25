! ==============================================================================
! Phase 6: Pooled memory implementation for variables module
! ==============================================================================
module variables_pooled
  use shell_types
  use string_pool
  use memory_dashboard
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none

  private
  public :: shell_pooled_t
  public :: set_shell_variable_pooled
  public :: get_shell_variable_pooled
  public :: expand_variables_pooled
  public :: init_shell_pooled
  public :: cleanup_variables_pooled
  public :: set_array_element_pooled
  public :: get_array_element_pooled
  public :: set_function_pooled
  public :: get_function_pooled

  ! Pooled variable type
  type :: variable_pooled_t
    character(len=256) :: name = ""  ! Variable name (not pooled - small fixed size)
    type(string_ref) :: value_ref    ! Pooled value reference
    logical :: is_array = .false.
    logical :: is_function = .false.
    logical :: is_exported = .false.
    logical :: is_readonly = .false.
    logical :: is_assoc_array = .false.
    type(string_ref), allocatable :: array_refs(:)  ! Pooled array values
    type(string_ref), allocatable :: function_refs(:)  ! Pooled function body
    type(string_ref), allocatable :: assoc_keys(:)    ! Pooled associative array keys
    type(string_ref), allocatable :: assoc_values(:)  ! Pooled associative array values
  end type variable_pooled_t

  ! Pooled shell type (for variables only)
  type :: shell_pooled_t
    type(variable_pooled_t), allocatable :: variables(:)
    integer :: var_count = 0
    integer :: var_capacity = 100
  end type shell_pooled_t

contains

  ! Initialize pooled shell structure
  subroutine init_shell_pooled(shell_pooled)
    type(shell_pooled_t), intent(inout) :: shell_pooled

    allocate(shell_pooled%variables(shell_pooled%var_capacity))
    shell_pooled%var_count = 0
  end subroutine init_shell_pooled

  ! Set shell variable with pooled memory
  subroutine set_shell_variable_pooled(shell_pooled, name, value, export, readonly)
    type(shell_pooled_t), intent(inout) :: shell_pooled
    character(len=*), intent(in) :: name, value
    logical, optional, intent(in) :: export, readonly

    integer :: i, value_len
    type(string_ref) :: new_value_ref
    type(variable_pooled_t), allocatable :: temp_vars(:)
    logical :: found

    ! Get pooled string for value
    value_len = len_trim(value)
    if (value_len > 0) then
      new_value_ref = pool_get_string(value_len)
      call dashboard_track_allocation(MOD_VARIABLES, value_len, &
                                      get_bucket_for_size(value_len))
      call pool_copy_to_ref(new_value_ref, trim(value))
    else
      new_value_ref%data => null()
      new_value_ref%str_len = 0
      new_value_ref%pool_index = 0
    end if

    ! Find existing variable
    found = .false.
    do i = 1, shell_pooled%var_count
      if (shell_pooled%variables(i)%name == name) then
        ! Release old value
        if (shell_pooled%variables(i)%value_ref%pool_index > 0) then
          call pool_release_string(shell_pooled%variables(i)%value_ref)
          call dashboard_track_deallocation(MOD_VARIABLES, &
                                           shell_pooled%variables(i)%value_ref%str_len, &
                                           get_bucket_for_size(shell_pooled%variables(i)%value_ref%str_len))
        end if

        ! Set new value
        shell_pooled%variables(i)%value_ref = new_value_ref
        if (present(export)) shell_pooled%variables(i)%is_exported = export
        if (present(readonly)) shell_pooled%variables(i)%is_readonly = readonly
        found = .true.
        exit
      end if
    end do

    ! Add new variable if not found
    if (.not. found) then
      ! Grow array if needed
      if (shell_pooled%var_count >= shell_pooled%var_capacity) then
        shell_pooled%var_capacity = shell_pooled%var_capacity * 2
        allocate(temp_vars(shell_pooled%var_capacity))
        temp_vars(1:shell_pooled%var_count) = shell_pooled%variables(1:shell_pooled%var_count)
        deallocate(shell_pooled%variables)
        shell_pooled%variables = temp_vars
      end if

      shell_pooled%var_count = shell_pooled%var_count + 1
      shell_pooled%variables(shell_pooled%var_count)%name = name
      shell_pooled%variables(shell_pooled%var_count)%value_ref = new_value_ref
      shell_pooled%variables(shell_pooled%var_count)%is_array = .false.
      shell_pooled%variables(shell_pooled%var_count)%is_function = .false.
      if (present(export)) then
        shell_pooled%variables(shell_pooled%var_count)%is_exported = export
      else
        shell_pooled%variables(shell_pooled%var_count)%is_exported = .false.
      end if
      if (present(readonly)) then
        shell_pooled%variables(shell_pooled%var_count)%is_readonly = readonly
      else
        shell_pooled%variables(shell_pooled%var_count)%is_readonly = .false.
      end if
    end if
  end subroutine set_shell_variable_pooled

  ! Get shell variable value with pooled memory
  function get_shell_variable_pooled(shell_pooled, name) result(value_ref)
    type(shell_pooled_t), intent(in) :: shell_pooled
    character(len=*), intent(in) :: name
    type(string_ref) :: value_ref

    integer :: i

    ! Initialize result
    value_ref%data => null()
    value_ref%str_len = 0
    value_ref%pool_index = 0

    ! Search for variable
    do i = 1, shell_pooled%var_count
      if (shell_pooled%variables(i)%name == name) then
        if (shell_pooled%variables(i)%is_array) then
          ! For arrays, return first element or empty
          if (allocated(shell_pooled%variables(i)%array_refs)) then
            if (size(shell_pooled%variables(i)%array_refs) > 0) then
              value_ref = shell_pooled%variables(i)%array_refs(1)
            end if
          end if
        else
          value_ref = shell_pooled%variables(i)%value_ref
        end if
        return
      end if
    end do
  end function get_shell_variable_pooled

  ! Expand variables in string using pooled memory
  function expand_variables_pooled(shell_pooled, input_str) result(expanded_ref)
    type(shell_pooled_t), intent(in) :: shell_pooled
    character(len=*), intent(in) :: input_str
    type(string_ref) :: expanded_ref

    character(len=4096) :: temp_result  ! Temporary buffer for expansion
    character(len=256) :: var_name
    integer :: i, j, input_len, result_len, var_start
    type(string_ref) :: var_value_ref
    logical :: in_var

    temp_result = ""
    result_len = 0
    input_len = len_trim(input_str)
    i = 1
    in_var = .false.
    var_start = 0

    do while (i <= input_len)
      if (input_str(i:i) == "$" .and. i < input_len) then
        if (input_str(i+1:i+1) == "{") then
          ! ${VAR} form
          var_start = i + 2
          j = index(input_str(var_start:), "}")
          if (j > 0) then
            var_name = input_str(var_start:var_start+j-2)
            var_value_ref = get_shell_variable_pooled(shell_pooled, trim(var_name))
            if (associated(var_value_ref%data)) then
              temp_result(result_len+1:result_len+var_value_ref%str_len) = &
                var_value_ref%data(1:var_value_ref%str_len)
              result_len = result_len + var_value_ref%str_len
            end if
            i = var_start + j
          else
            ! No closing brace - copy literally
            result_len = result_len + 1
            temp_result(result_len:result_len) = "$"
            i = i + 1
          end if
        else if (is_valid_var_char(input_str(i+1:i+1))) then
          ! $VAR form
          var_start = i + 1
          j = var_start
          do while (j <= input_len .and. is_valid_var_char(input_str(j:j)))
            j = j + 1
          end do
          var_name = input_str(var_start:j-1)
          var_value_ref = get_shell_variable_pooled(shell_pooled, trim(var_name))
          if (associated(var_value_ref%data)) then
            temp_result(result_len+1:result_len+var_value_ref%str_len) = &
              var_value_ref%data(1:var_value_ref%str_len)
            result_len = result_len + var_value_ref%str_len
          end if
          i = j
        else
          ! Just a dollar sign
          result_len = result_len + 1
          temp_result(result_len:result_len) = "$"
          i = i + 1
        end if
      else
        ! Regular character
        result_len = result_len + 1
        temp_result(result_len:result_len) = input_str(i:i)
        i = i + 1
      end if
    end do

    ! Get pooled string for result
    if (result_len > 0) then
      expanded_ref = pool_get_string(result_len)
      call dashboard_track_allocation(MOD_VARIABLES, result_len, &
                                      get_bucket_for_size(result_len))
      call pool_copy_to_ref(expanded_ref, temp_result(1:result_len))
    else
      expanded_ref%data => null()
      expanded_ref%str_len = 0
      expanded_ref%pool_index = 0
    end if
  end function expand_variables_pooled

  ! Set array element with pooled memory
  recursive subroutine set_array_element_pooled(shell_pooled, array_name, index, value)
    type(shell_pooled_t), intent(inout) :: shell_pooled
    character(len=*), intent(in) :: array_name, value
    integer, intent(in) :: index

    integer :: i, j, value_len
    type(string_ref) :: new_value_ref
    type(string_ref), allocatable :: temp_refs(:)

    ! Get pooled string for value
    value_len = len_trim(value)
    new_value_ref = pool_get_string(value_len)
    call dashboard_track_allocation(MOD_VARIABLES, value_len, &
                                    get_bucket_for_size(value_len))
    call pool_copy_to_ref(new_value_ref, trim(value))

    ! Find array variable
    do i = 1, shell_pooled%var_count
      if (shell_pooled%variables(i)%name == array_name) then
        shell_pooled%variables(i)%is_array = .true.

        ! Ensure array is allocated and sized correctly
        if (.not. allocated(shell_pooled%variables(i)%array_refs)) then
          allocate(shell_pooled%variables(i)%array_refs(index))
          ! Initialize all to empty
          do j = 1, index-1
            shell_pooled%variables(i)%array_refs(j)%data => null()
            shell_pooled%variables(i)%array_refs(j)%str_len = 0
            shell_pooled%variables(i)%array_refs(j)%pool_index = 0
          end do
        else if (size(shell_pooled%variables(i)%array_refs) < index) then
          ! Grow array
          allocate(temp_refs(index))
          temp_refs(1:size(shell_pooled%variables(i)%array_refs)) = &
            shell_pooled%variables(i)%array_refs
          ! Initialize new elements to empty
          do j = size(shell_pooled%variables(i)%array_refs)+1, index-1
            temp_refs(j)%data => null()
            temp_refs(j)%str_len = 0
            temp_refs(j)%pool_index = 0
          end do
          deallocate(shell_pooled%variables(i)%array_refs)
          shell_pooled%variables(i)%array_refs = temp_refs
        end if

        ! Release old value at index if exists
        if (shell_pooled%variables(i)%array_refs(index)%pool_index > 0) then
          call pool_release_string(shell_pooled%variables(i)%array_refs(index))
          call dashboard_track_deallocation(MOD_VARIABLES, &
                                           shell_pooled%variables(i)%array_refs(index)%str_len, &
                                           get_bucket_for_size(shell_pooled%variables(i)%array_refs(index)%str_len))
        end if

        ! Set new value
        shell_pooled%variables(i)%array_refs(index) = new_value_ref
        return
      end if
    end do

    ! Variable not found - create it
    call set_shell_variable_pooled(shell_pooled, array_name, "", .false., .false.)
    ! Recursively call to set array element
    call set_array_element_pooled(shell_pooled, array_name, index, value)
  end subroutine set_array_element_pooled

  ! Get array element with pooled memory
  function get_array_element_pooled(shell_pooled, array_name, index) result(value_ref)
    type(shell_pooled_t), intent(in) :: shell_pooled
    character(len=*), intent(in) :: array_name
    integer, intent(in) :: index
    type(string_ref) :: value_ref

    integer :: i

    ! Initialize result
    value_ref%data => null()
    value_ref%str_len = 0
    value_ref%pool_index = 0

    ! Find array variable
    do i = 1, shell_pooled%var_count
      if (shell_pooled%variables(i)%name == array_name) then
        if (shell_pooled%variables(i)%is_array .and. &
            allocated(shell_pooled%variables(i)%array_refs)) then
          if (index > 0 .and. index <= size(shell_pooled%variables(i)%array_refs)) then
            value_ref = shell_pooled%variables(i)%array_refs(index)
          end if
        end if
        return
      end if
    end do
  end function get_array_element_pooled

  ! Set function with pooled memory
  recursive subroutine set_function_pooled(shell_pooled, func_name, body_lines)
    type(shell_pooled_t), intent(inout) :: shell_pooled
    character(len=*), intent(in) :: func_name
    character(len=*), dimension(:), intent(in) :: body_lines

    integer :: i, j, line_len
    type(string_ref), allocatable :: temp_refs(:)

    ! Find or create function variable
    do i = 1, shell_pooled%var_count
      if (shell_pooled%variables(i)%name == func_name) then
        ! Release old function body if exists
        if (allocated(shell_pooled%variables(i)%function_refs)) then
          do j = 1, size(shell_pooled%variables(i)%function_refs)
            if (shell_pooled%variables(i)%function_refs(j)%pool_index > 0) then
              call pool_release_string(shell_pooled%variables(i)%function_refs(j))
              call dashboard_track_deallocation(MOD_VARIABLES, &
                                               shell_pooled%variables(i)%function_refs(j)%str_len, &
                                               get_bucket_for_size(shell_pooled%variables(i)%function_refs(j)%str_len))
            end if
          end do
          deallocate(shell_pooled%variables(i)%function_refs)
        end if

        ! Set new function body
        shell_pooled%variables(i)%is_function = .true.
        allocate(shell_pooled%variables(i)%function_refs(size(body_lines)))
        do j = 1, size(body_lines)
          line_len = len_trim(body_lines(j))
          shell_pooled%variables(i)%function_refs(j) = pool_get_string(line_len)
          call dashboard_track_allocation(MOD_VARIABLES, line_len, &
                                          get_bucket_for_size(line_len))
          call pool_copy_to_ref(shell_pooled%variables(i)%function_refs(j), &
                                trim(body_lines(j)))
        end do
        return
      end if
    end do

    ! Function not found - create it
    call set_shell_variable_pooled(shell_pooled, func_name, "", .false., .false.)
    ! Recursively call to set function
    call set_function_pooled(shell_pooled, func_name, body_lines)
  end subroutine set_function_pooled

  ! Get function body with pooled memory
  function get_function_pooled(shell_pooled, func_name) result(body_refs)
    type(shell_pooled_t), intent(in) :: shell_pooled
    character(len=*), intent(in) :: func_name
    type(string_ref), allocatable :: body_refs(:)

    integer :: i

    ! Search for function
    do i = 1, shell_pooled%var_count
      if (shell_pooled%variables(i)%name == func_name) then
        if (shell_pooled%variables(i)%is_function .and. &
            allocated(shell_pooled%variables(i)%function_refs)) then
          allocate(body_refs(size(shell_pooled%variables(i)%function_refs)))
          body_refs = shell_pooled%variables(i)%function_refs
        end if
        return
      end if
    end do
  end function get_function_pooled

  ! Cleanup all pooled variables
  subroutine cleanup_variables_pooled(shell_pooled)
    type(shell_pooled_t), intent(inout) :: shell_pooled

    integer :: i, j

    do i = 1, shell_pooled%var_count
      ! Release value
      if (shell_pooled%variables(i)%value_ref%pool_index > 0) then
        call pool_release_string(shell_pooled%variables(i)%value_ref)
        call dashboard_track_deallocation(MOD_VARIABLES, &
                                         shell_pooled%variables(i)%value_ref%str_len, &
                                         get_bucket_for_size(shell_pooled%variables(i)%value_ref%str_len))
      end if

      ! Release array values
      if (allocated(shell_pooled%variables(i)%array_refs)) then
        do j = 1, size(shell_pooled%variables(i)%array_refs)
          if (shell_pooled%variables(i)%array_refs(j)%pool_index > 0) then
            call pool_release_string(shell_pooled%variables(i)%array_refs(j))
            call dashboard_track_deallocation(MOD_VARIABLES, &
                                             shell_pooled%variables(i)%array_refs(j)%str_len, &
                                             get_bucket_for_size(shell_pooled%variables(i)%array_refs(j)%str_len))
          end if
        end do
        deallocate(shell_pooled%variables(i)%array_refs)
      end if

      ! Release function body
      if (allocated(shell_pooled%variables(i)%function_refs)) then
        do j = 1, size(shell_pooled%variables(i)%function_refs)
          if (shell_pooled%variables(i)%function_refs(j)%pool_index > 0) then
            call pool_release_string(shell_pooled%variables(i)%function_refs(j))
            call dashboard_track_deallocation(MOD_VARIABLES, &
                                             shell_pooled%variables(i)%function_refs(j)%str_len, &
                                             get_bucket_for_size(shell_pooled%variables(i)%function_refs(j)%str_len))
          end if
        end do
        deallocate(shell_pooled%variables(i)%function_refs)
      end if

      ! Release associative arrays
      if (allocated(shell_pooled%variables(i)%assoc_keys)) then
        do j = 1, size(shell_pooled%variables(i)%assoc_keys)
          if (shell_pooled%variables(i)%assoc_keys(j)%pool_index > 0) then
            call pool_release_string(shell_pooled%variables(i)%assoc_keys(j))
            call dashboard_track_deallocation(MOD_VARIABLES, &
                                             shell_pooled%variables(i)%assoc_keys(j)%str_len, &
                                             get_bucket_for_size(shell_pooled%variables(i)%assoc_keys(j)%str_len))
          end if
        end do
        deallocate(shell_pooled%variables(i)%assoc_keys)
      end if

      if (allocated(shell_pooled%variables(i)%assoc_values)) then
        do j = 1, size(shell_pooled%variables(i)%assoc_values)
          if (shell_pooled%variables(i)%assoc_values(j)%pool_index > 0) then
            call pool_release_string(shell_pooled%variables(i)%assoc_values(j))
            call dashboard_track_deallocation(MOD_VARIABLES, &
                                             shell_pooled%variables(i)%assoc_values(j)%str_len, &
                                             get_bucket_for_size(shell_pooled%variables(i)%assoc_values(j)%str_len))
          end if
        end do
        deallocate(shell_pooled%variables(i)%assoc_values)
      end if
    end do

    if (allocated(shell_pooled%variables)) then
      deallocate(shell_pooled%variables)
    end if

    shell_pooled%var_count = 0
  end subroutine cleanup_variables_pooled

  ! Helper: Check if character is valid for variable name
  function is_valid_var_char(ch) result(is_valid)
    character(len=1), intent(in) :: ch
    logical :: is_valid

    is_valid = (ch >= 'a' .and. ch <= 'z') .or. &
               (ch >= 'A' .and. ch <= 'Z') .or. &
               (ch >= '0' .and. ch <= '9') .or. &
               ch == '_'
  end function is_valid_var_char

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

end module variables_pooled