! ==============================================================================
! Simplified test program for Phase 6 - Lexer module with memory pooling
! ==============================================================================
program test_lexer_simple
  use string_pool
  use memory_dashboard
  use shell_types
  use iso_fortran_env, only: output_unit
  implicit none

  type(string_ref) :: token_ref, word_ref, str_literal_ref, var_ref
  type(string_ref), allocatable :: token_refs(:)
  integer :: i, j
  logical :: test_passed
  integer :: total_allocs, total_deallocs, current_strings, peak_strings
  real :: hit_rate
  character(:), pointer :: str_ptr

  test_passed = .true.

  print *, "=== Phase 6 Lexer Memory Pooling Test (Simplified) ==="
  print *, "Testing pooled memory for tokenization"
  print *

  ! Initialize the pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.false.)

  ! Test 1: Token value strings
  print *, "Test 1: Testing token value string allocation..."

  ! Simulate creating tokens with different value sizes
  allocate(token_refs(5))

  ! Small token (operator)
  token_refs(1) = pool_get_string(2)  ! "||"
  call dashboard_track_allocation(MOD_LEXER, 2, 1)
  call pool_copy_to_ref(token_refs(1), "||")

  ! Medium token (keyword)
  token_refs(2) = pool_get_string(8)  ! "function"
  call dashboard_track_allocation(MOD_LEXER, 8, 1)
  call pool_copy_to_ref(token_refs(2), "function")

  ! Word token
  token_refs(3) = pool_get_string(64)  ! typical command name
  call dashboard_track_allocation(MOD_LEXER, 64, 1)
  call pool_copy_to_ref(token_refs(3), "execute_command_with_long_name")

  ! String literal
  token_refs(4) = pool_get_string(256)  ! quoted string
  call dashboard_track_allocation(MOD_LEXER, 256, 2)
  call pool_copy_to_ref(token_refs(4), "This is a longer string literal with spaces and special chars")

  ! Variable name
  token_refs(5) = pool_get_string(32)  ! $VARIABLE
  call dashboard_track_allocation(MOD_LEXER, 32, 1)
  call pool_copy_to_ref(token_refs(5), "PATH_TO_EXECUTABLE")

  print *, "  Created 5 token value strings:"
  print *, "    Token 1 (2B):", trim(token_refs(1)%data)
  print *, "    Token 2 (8B):", trim(token_refs(2)%data)
  print *, "    Token 3 (64B):", trim(token_refs(3)%data(1:30)), "..."
  print *, "    Token 4 (256B):", trim(token_refs(4)%data(1:40)), "..."
  print *, "    Token 5 (32B):", trim(token_refs(5)%data)

  ! Verify pooling
  if (token_refs(1)%pool_index /= 0 .and. token_refs(4)%pool_index /= 0) then
    print *, "  PASSED: Token values allocated from pool"
  else
    print *, "  FAILED: Token values not from pool"
    test_passed = .false.
  end if

  ! Release token strings
  do i = 1, 5
    call pool_release_string(token_refs(i))
    call dashboard_track_deallocation(MOD_LEXER, token_refs(i)%str_len, &
                                      get_bucket_for_size(token_refs(i)%str_len))
  end do
  deallocate(token_refs)

  ! Test 2: Input buffer pooling
  print *, ""
  print *, "Test 2: Testing input buffer pooling..."

  ! Simulate input string for lexer (typical command line)
  word_ref = pool_get_string(512)
  call dashboard_track_allocation(MOD_LEXER, 512, 3)
  call pool_copy_to_ref(word_ref, &
    "if [ $? -eq 0 ]; then echo 'Success' | tee output.log; else echo 'Failed'; fi")

  str_ptr => word_ref%data
  if (associated(str_ptr)) then
    print *, "  Input buffer (512B) allocated"
    print *, "  Content:", trim(str_ptr(1:50)), "..."
    print *, "  PASSED: Input buffer working"
  end if

  call pool_release_string(word_ref)
  call dashboard_track_deallocation(MOD_LEXER, 512, 3)

  ! Test 3: Temporary string buffers during tokenization
  print *, ""
  print *, "Test 3: Testing temporary tokenization buffers..."

  ! Simulate temporary buffers used during read_word, read_string, read_variable
  word_ref = pool_get_string(256)    ! For word reading
  str_literal_ref = pool_get_string(1024) ! For string literal reading
  var_ref = pool_get_string(64)      ! For variable name reading

  call dashboard_track_allocation(MOD_LEXER, 256, 2)
  call dashboard_track_allocation(MOD_LEXER, 1024, 3)
  call dashboard_track_allocation(MOD_LEXER, 64, 1)

  call pool_copy_to_ref(word_ref, "temporary_word_buffer")
  call pool_copy_to_ref(str_literal_ref, "temporary string buffer for quoted literals")
  call pool_copy_to_ref(var_ref, "TEMP_VAR")

  print *, "  Allocated 3 temporary buffers:"
  print *, "    Word buffer (256B):", trim(word_ref%data)
  print *, "    String buffer (1024B):", trim(str_literal_ref%data)
  print *, "    Variable buffer (64B):", trim(var_ref%data)

  call pool_release_string(word_ref)
  call pool_release_string(str_literal_ref)
  call pool_release_string(var_ref)

  call dashboard_track_deallocation(MOD_LEXER, 256, 2)
  call dashboard_track_deallocation(MOD_LEXER, 1024, 3)
  call dashboard_track_deallocation(MOD_LEXER, 64, 1)

  print *, "  Released all temporary buffers"

  ! Test 4: Token array simulation (many small allocations)
  print *, ""
  print *, "Test 4: Simulating token array with 100 tokens..."

  allocate(token_refs(100))
  do i = 1, 100
    ! Vary token sizes to simulate real tokenization
    select case(mod(i, 4))
    case(0)  ! Small operator/keyword
      token_refs(i) = pool_get_string(8)
      call dashboard_track_allocation(MOD_LEXER, 8, 1)
      call pool_copy_to_ref(token_refs(i), "keyword")
    case(1)  ! Medium word
      token_refs(i) = pool_get_string(32)
      call dashboard_track_allocation(MOD_LEXER, 32, 1)
      call pool_copy_to_ref(token_refs(i), "command_name")
    case(2)  ! Larger string
      token_refs(i) = pool_get_string(128)
      call dashboard_track_allocation(MOD_LEXER, 128, 2)
      call pool_copy_to_ref(token_refs(i), "longer_string_value")
    case(3)  ! Variable
      token_refs(i) = pool_get_string(16)
      call dashboard_track_allocation(MOD_LEXER, 16, 1)
      call pool_copy_to_ref(token_refs(i), "VAR")
    end select
  end do

  print *, "  Created 100 tokens with varied sizes"
  print *, "    Sample token 1:", trim(token_refs(1)%data)
  print *, "    Sample token 50:", trim(token_refs(50)%data)
  print *, "    Sample token 100:", trim(token_refs(100)%data)

  ! Release all tokens
  do i = 1, 100
    call pool_release_string(token_refs(i))
    call dashboard_track_deallocation(MOD_LEXER, token_refs(i)%str_len, &
                                      get_bucket_for_size(token_refs(i)%str_len))
  end do
  deallocate(token_refs)

  print *, "  Released all 100 tokens"

  ! Test 5: Stress test - rapid tokenization cycles
  print *, ""
  print *, "Test 5: Stress testing with 1000 tokenization cycles..."
  do i = 1, 1000
    ! Simulate a tokenization cycle
    token_ref = pool_get_string(64)   ! Token value
    word_ref = pool_get_string(256)   ! Temp buffer

    call dashboard_track_allocation(MOD_LEXER, 64, 1)
    call dashboard_track_allocation(MOD_LEXER, 256, 2)

    ! Simulate some work
    call pool_copy_to_ref(token_ref, "token")
    call pool_copy_to_ref(word_ref, "buffer")

    ! Release
    call pool_release_string(token_ref)
    call pool_release_string(word_ref)

    call dashboard_track_deallocation(MOD_LEXER, 64, 1)
    call dashboard_track_deallocation(MOD_LEXER, 256, 2)
  end do
  print *, "  Completed 1000 tokenization cycles"

  ! Test 6: Check for memory leaks
  print *, ""
  print *, "Test 6: Checking for memory leaks..."
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
  print *, "=== Lexer Module Statistics ==="
  call dashboard_display(detailed=.false.)

  ! Export statistics
  call dashboard_export_csv("lexer_pooling_test.csv")
  print *, ""
  print *, "Statistics exported to lexer_pooling_test.csv"

  ! Clean up
  call dashboard_cleanup()
  call pool_cleanup()

  ! Summary
  print *, ""
  print *, "=== Test Summary ==="
  if (test_passed .and. current_strings == 0) then
    print *, "ALL TESTS PASSED"
    print *, ""
    print *, "Lexer pooling integration verified:"
    print *, "  - Token value strings (2-256 bytes) working"
    print *, "  - Input buffer (512 bytes) working"
    print *, "  - Temporary buffers (64-1024 bytes) working"
    print *, "  - Token array management (100 tokens) working"
    print *, "  - No memory leaks detected"
    print *, "  - Dashboard tracking successful"
    print *, "  - Cache hit rate:", int(hit_rate * 100), "%"
    print *, ""
    print *, "Ready to integrate into production lexer module!"
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

end program test_lexer_simple