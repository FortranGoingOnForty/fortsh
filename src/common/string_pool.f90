! ==============================================================================
! Module: string_pool_v2
! Purpose: Efficient string memory management with true zero-copy pooling
!
! This implements Phase 3 of the memory pooling project - eliminating double
! allocation by using direct pointers to pool memory.
! ==============================================================================
module string_pool
  use iso_fortran_env, only: int32, int64
  implicit none
  private

  ! Public interface
  public :: pool_get_string, pool_release_string, pool_intern_string
  public :: pool_statistics, pool_cleanup, pool_init
  public :: string_ref, pool_copy_to_ref, pool_get_string_ptr

  ! Constants
  integer, parameter :: NUM_BUCKETS = 5
  integer, parameter :: BUCKET_SIZES(NUM_BUCKETS) = [64, 256, 1024, 4096, 16384]
  integer, parameter :: INITIAL_SLOTS = 100
  integer, parameter :: MAX_SLOTS = 10000

  ! String reference type - points directly to pool memory
  type :: string_ref
    integer :: pool_index = 0     ! Encoded bucket and slot index
    integer :: ref_count = 0
    integer :: str_len = 0        ! Actual string length
    character(:), pointer :: data => null()
  end type string_ref

  ! Pool statistics
  type :: pool_stats
    integer(int64) :: total_allocations = 0
    integer(int64) :: total_deallocations = 0
    integer :: current_strings = 0
    integer :: peak_strings = 0
    integer(int64) :: cache_hits = 0
    integer(int64) :: cache_misses = 0
  end type pool_stats

  ! MODULE-LEVEL TARGET STORAGE - This is the key!
  ! We declare these at module level with TARGET so we can point to them
  character(len=64), target, allocatable :: pool_64(:)
  character(len=256), target, allocatable :: pool_256(:)
  character(len=1024), target, allocatable :: pool_1024(:)
  character(len=4096), target, allocatable :: pool_4096(:)
  character(len=16384), target, allocatable :: pool_16384(:)

  ! Tracking arrays for each pool
  logical, allocatable :: in_use_64(:), in_use_256(:), in_use_1024(:), in_use_4096(:), in_use_16384(:)
  integer, allocatable :: ref_counts_64(:), ref_counts_256(:), ref_counts_1024(:), ref_counts_4096(:), ref_counts_16384(:)

  ! Pool sizes
  integer :: size_64 = 0, size_256 = 0, size_1024 = 0, size_4096 = 0, size_16384 = 0

  ! Interned strings for deduplication
  character(len=256), allocatable :: interned_strings(:)
  integer, allocatable :: interned_refs(:)
  integer :: num_interned = 0

  ! Global statistics
  type(pool_stats) :: stats
  logical :: pool_initialized = .false.

contains

  ! Initialize the string pool
  subroutine pool_init()
    if (pool_initialized) return

    ! Allocate initial pool storage
    allocate(pool_64(INITIAL_SLOTS))
    allocate(pool_256(INITIAL_SLOTS))
    allocate(pool_1024(INITIAL_SLOTS))
    allocate(pool_4096(INITIAL_SLOTS))
    allocate(pool_16384(INITIAL_SLOTS/10))  ! Fewer slots for large strings

    ! Allocate tracking arrays
    allocate(in_use_64(INITIAL_SLOTS))
    allocate(in_use_256(INITIAL_SLOTS))
    allocate(in_use_1024(INITIAL_SLOTS))
    allocate(in_use_4096(INITIAL_SLOTS))
    allocate(in_use_16384(INITIAL_SLOTS/10))

    allocate(ref_counts_64(INITIAL_SLOTS))
    allocate(ref_counts_256(INITIAL_SLOTS))
    allocate(ref_counts_1024(INITIAL_SLOTS))
    allocate(ref_counts_4096(INITIAL_SLOTS))
    allocate(ref_counts_16384(INITIAL_SLOTS/10))

    ! Initialize tracking arrays
    in_use_64 = .false.
    in_use_256 = .false.
    in_use_1024 = .false.
    in_use_4096 = .false.
    in_use_16384 = .false.

    ref_counts_64 = 0
    ref_counts_256 = 0
    ref_counts_1024 = 0
    ref_counts_4096 = 0
    ref_counts_16384 = 0

    size_64 = INITIAL_SLOTS
    size_256 = INITIAL_SLOTS
    size_1024 = INITIAL_SLOTS
    size_4096 = INITIAL_SLOTS
    size_16384 = INITIAL_SLOTS/10

    ! Initialize interned strings
    allocate(interned_strings(100))
    allocate(interned_refs(100))
    interned_refs = 0
    num_interned = 0

    pool_initialized = .true.
  end subroutine pool_init

  ! Get a string from the pool - ZERO COPY VERSION!
  recursive function pool_get_string(length) result(ref)
    integer, intent(in) :: length
    type(string_ref) :: ref
    integer :: bucket_idx, slot_idx

    if (.not. pool_initialized) call pool_init()

    ! Determine which bucket to use
    if (length <= 64) then
      bucket_idx = 1
      slot_idx = find_free_slot_64()
      if (slot_idx > 0) then
        in_use_64(slot_idx) = .true.
        ref_counts_64(slot_idx) = 1
        ! DIRECT POINTER - NO ALLOCATION!
        ref%data => pool_64(slot_idx)(1:length)
      end if
    else if (length <= 256) then
      bucket_idx = 2
      slot_idx = find_free_slot_256()
      if (slot_idx > 0) then
        in_use_256(slot_idx) = .true.
        ref_counts_256(slot_idx) = 1
        ! DIRECT POINTER - NO ALLOCATION!
        ref%data => pool_256(slot_idx)(1:length)
      end if
    else if (length <= 1024) then
      bucket_idx = 3
      slot_idx = find_free_slot_1024()
      if (slot_idx > 0) then
        in_use_1024(slot_idx) = .true.
        ref_counts_1024(slot_idx) = 1
        ! DIRECT POINTER - NO ALLOCATION!
        ref%data => pool_1024(slot_idx)(1:length)
      end if
    else if (length <= 4096) then
      bucket_idx = 4
      slot_idx = find_free_slot_4096()
      if (slot_idx > 0) then
        in_use_4096(slot_idx) = .true.
        ref_counts_4096(slot_idx) = 1
        ! DIRECT POINTER - NO ALLOCATION!
        ref%data => pool_4096(slot_idx)(1:length)
      end if
    else if (length <= 16384) then
      bucket_idx = 5
      slot_idx = find_free_slot_16384()
      if (slot_idx > 0) then
        in_use_16384(slot_idx) = .true.
        ref_counts_16384(slot_idx) = 1
        ! DIRECT POINTER - NO ALLOCATION!
        ref%data => pool_16384(slot_idx)(1:length)
      end if
    else
      ! Too large for pool - allocate directly
      ! NOTE: Direct allocation on macOS ARM64 (flang-new) should be avoided
      ! for strings >127 bytes due to compiler limitations UNLESS the C string
      ! library is enabled (which handles dangerous operations safely)
      bucket_idx = 0
      slot_idx = -1
#if defined(__APPLE__) && !defined(USE_C_STRINGS)
      ! On macOS WITHOUT C string library, cap direct allocations at 127 bytes
      ! When USE_C_STRINGS is defined, the C library handles large strings safely
      if (length > 127) then
        ! Allocation would exceed safe limit - return null ref
        ref%pool_index = 0
        ref%ref_count = 0
        ref%str_len = 0
        ref%data => null()
        stats%cache_misses = stats%cache_misses + 1
        return
      end if
#endif
      allocate(character(len=length) :: ref%data)
      stats%cache_misses = stats%cache_misses + 1
    end if

    ! Set up reference
    if (slot_idx > 0) then
      ref%pool_index = bucket_idx * 10000 + slot_idx
      ref%ref_count = 1
      ref%str_len = length
      stats%cache_hits = stats%cache_hits + 1
    else if (bucket_idx > 0) then
      ! Pool was full, need to expand
      call expand_pool(bucket_idx)
      ! Retry after expansion
      ref = pool_get_string(length)
      return
    else
      ! Direct allocation
      ref%pool_index = -1
      ref%ref_count = 1
      ref%str_len = length
    end if

    ! Update statistics
    stats%total_allocations = stats%total_allocations + 1
    stats%current_strings = stats%current_strings + 1
    if (stats%current_strings > stats%peak_strings) then
      stats%peak_strings = stats%current_strings
    end if

  end function pool_get_string

  ! Find a free slot in the 64-byte pool
  function find_free_slot_64() result(slot)
    integer :: slot, i
    slot = 0
    do i = 1, size_64
      if (.not. in_use_64(i)) then
        slot = i
        exit
      end if
    end do
  end function find_free_slot_64

  ! Find a free slot in the 256-byte pool
  function find_free_slot_256() result(slot)
    integer :: slot, i
    slot = 0
    do i = 1, size_256
      if (.not. in_use_256(i)) then
        slot = i
        exit
      end if
    end do
  end function find_free_slot_256

  ! Find a free slot in the 1024-byte pool
  function find_free_slot_1024() result(slot)
    integer :: slot, i
    slot = 0
    do i = 1, size_1024
      if (.not. in_use_1024(i)) then
        slot = i
        exit
      end if
    end do
  end function find_free_slot_1024

  ! Find a free slot in the 4096-byte pool
  function find_free_slot_4096() result(slot)
    integer :: slot, i
    slot = 0
    do i = 1, size_4096
      if (.not. in_use_4096(i)) then
        slot = i
        exit
      end if
    end do
  end function find_free_slot_4096

  ! Find a free slot in the 16384-byte pool
  function find_free_slot_16384() result(slot)
    integer :: slot, i
    slot = 0
    do i = 1, size_16384
      if (.not. in_use_16384(i)) then
        slot = i
        exit
      end if
    end do
  end function find_free_slot_16384

  ! Expand a pool when it's full
  subroutine expand_pool(bucket_idx)
    integer, intent(in) :: bucket_idx
    integer :: old_size, new_size

    select case(bucket_idx)
    case(1)  ! 64-byte pool
      old_size = size_64
      new_size = min(old_size * 2, MAX_SLOTS)
      if (new_size > old_size) then
        call resize_pool_64(new_size)
        size_64 = new_size
      end if
    case(2)  ! 256-byte pool
      old_size = size_256
      new_size = min(old_size * 2, MAX_SLOTS)
      if (new_size > old_size) then
        call resize_pool_256(new_size)
        size_256 = new_size
      end if
    case(3)  ! 1024-byte pool
      old_size = size_1024
      new_size = min(old_size * 2, MAX_SLOTS)
      if (new_size > old_size) then
        call resize_pool_1024(new_size)
        size_1024 = new_size
      end if
    case(4)  ! 4096-byte pool
      old_size = size_4096
      new_size = min(old_size * 2, MAX_SLOTS)
      if (new_size > old_size) then
        call resize_pool_4096(new_size)
        size_4096 = new_size
      end if
    case(5)  ! 16384-byte pool
      old_size = size_16384
      new_size = min(old_size * 2, MAX_SLOTS/10)
      if (new_size > old_size) then
        call resize_pool_16384(new_size)
        size_16384 = new_size
      end if
    end select
  end subroutine expand_pool

  ! Resize helper functions for each pool
  subroutine resize_pool_64(new_size)
    integer, intent(in) :: new_size
    character(len=64), allocatable, target :: temp(:)
    logical, allocatable :: temp_use(:)
    integer, allocatable :: temp_refs(:)
    integer :: old_size

    old_size = size(pool_64)

    ! Save old data
    allocate(temp(old_size))
    allocate(temp_use(old_size))
    allocate(temp_refs(old_size))
    temp = pool_64
    temp_use = in_use_64
    temp_refs = ref_counts_64

    ! Reallocate
    deallocate(pool_64, in_use_64, ref_counts_64)
    allocate(pool_64(new_size))
    allocate(in_use_64(new_size))
    allocate(ref_counts_64(new_size))

    ! Restore data
    pool_64(1:old_size) = temp
    in_use_64(1:old_size) = temp_use
    in_use_64(old_size+1:) = .false.
    ref_counts_64(1:old_size) = temp_refs
    ref_counts_64(old_size+1:) = 0

    deallocate(temp, temp_use, temp_refs)
  end subroutine resize_pool_64

  subroutine resize_pool_256(new_size)
    integer, intent(in) :: new_size
    character(len=256), allocatable, target :: temp(:)
    logical, allocatable :: temp_use(:)
    integer, allocatable :: temp_refs(:)
    integer :: old_size

    old_size = size(pool_256)

    allocate(temp(old_size))
    allocate(temp_use(old_size))
    allocate(temp_refs(old_size))
    temp = pool_256
    temp_use = in_use_256
    temp_refs = ref_counts_256

    deallocate(pool_256, in_use_256, ref_counts_256)
    allocate(pool_256(new_size))
    allocate(in_use_256(new_size))
    allocate(ref_counts_256(new_size))

    pool_256(1:old_size) = temp
    in_use_256(1:old_size) = temp_use
    in_use_256(old_size+1:) = .false.
    ref_counts_256(1:old_size) = temp_refs
    ref_counts_256(old_size+1:) = 0

    deallocate(temp, temp_use, temp_refs)
  end subroutine resize_pool_256

  subroutine resize_pool_1024(new_size)
    integer, intent(in) :: new_size
    character(len=1024), allocatable, target :: temp(:)
    logical, allocatable :: temp_use(:)
    integer, allocatable :: temp_refs(:)
    integer :: old_size

    old_size = size(pool_1024)

    allocate(temp(old_size))
    allocate(temp_use(old_size))
    allocate(temp_refs(old_size))
    temp = pool_1024
    temp_use = in_use_1024
    temp_refs = ref_counts_1024

    deallocate(pool_1024, in_use_1024, ref_counts_1024)
    allocate(pool_1024(new_size))
    allocate(in_use_1024(new_size))
    allocate(ref_counts_1024(new_size))

    pool_1024(1:old_size) = temp
    in_use_1024(1:old_size) = temp_use
    in_use_1024(old_size+1:) = .false.
    ref_counts_1024(1:old_size) = temp_refs
    ref_counts_1024(old_size+1:) = 0

    deallocate(temp, temp_use, temp_refs)
  end subroutine resize_pool_1024

  subroutine resize_pool_4096(new_size)
    integer, intent(in) :: new_size
    character(len=4096), allocatable, target :: temp(:)
    logical, allocatable :: temp_use(:)
    integer, allocatable :: temp_refs(:)
    integer :: old_size

    old_size = size(pool_4096)

    allocate(temp(old_size))
    allocate(temp_use(old_size))
    allocate(temp_refs(old_size))
    temp = pool_4096
    temp_use = in_use_4096
    temp_refs = ref_counts_4096

    deallocate(pool_4096, in_use_4096, ref_counts_4096)
    allocate(pool_4096(new_size))
    allocate(in_use_4096(new_size))
    allocate(ref_counts_4096(new_size))

    pool_4096(1:old_size) = temp
    in_use_4096(1:old_size) = temp_use
    in_use_4096(old_size+1:) = .false.
    ref_counts_4096(1:old_size) = temp_refs
    ref_counts_4096(old_size+1:) = 0

    deallocate(temp, temp_use, temp_refs)
  end subroutine resize_pool_4096

  subroutine resize_pool_16384(new_size)
    integer, intent(in) :: new_size
    character(len=16384), allocatable, target :: temp(:)
    logical, allocatable :: temp_use(:)
    integer, allocatable :: temp_refs(:)
    integer :: old_size

    old_size = size(pool_16384)

    allocate(temp(old_size))
    allocate(temp_use(old_size))
    allocate(temp_refs(old_size))
    temp = pool_16384
    temp_use = in_use_16384
    temp_refs = ref_counts_16384

    deallocate(pool_16384, in_use_16384, ref_counts_16384)
    allocate(pool_16384(new_size))
    allocate(in_use_16384(new_size))
    allocate(ref_counts_16384(new_size))

    pool_16384(1:old_size) = temp
    in_use_16384(1:old_size) = temp_use
    in_use_16384(old_size+1:) = .false.
    ref_counts_16384(1:old_size) = temp_refs
    ref_counts_16384(old_size+1:) = 0

    deallocate(temp, temp_use, temp_refs)
  end subroutine resize_pool_16384

  ! Release a string back to the pool
  subroutine pool_release_string(ref)
    type(string_ref), intent(inout) :: ref
    integer :: bucket_idx, slot_idx

    if (ref%pool_index == 0) then
      ! Never allocated
      return
    else if (ref%pool_index == -1) then
      ! Direct allocation
      if (associated(ref%data)) deallocate(ref%data)
      stats%total_deallocations = stats%total_deallocations + 1
      stats%current_strings = stats%current_strings - 1
    else
      ! From pool
      bucket_idx = ref%pool_index / 10000
      slot_idx = mod(ref%pool_index, 10000)

      select case(bucket_idx)
      case(1)
        ref_counts_64(slot_idx) = ref_counts_64(slot_idx) - 1
        if (ref_counts_64(slot_idx) <= 0) then
          in_use_64(slot_idx) = .false.
          pool_64(slot_idx) = ''  ! Clear content
        end if
      case(2)
        ref_counts_256(slot_idx) = ref_counts_256(slot_idx) - 1
        if (ref_counts_256(slot_idx) <= 0) then
          in_use_256(slot_idx) = .false.
          pool_256(slot_idx) = ''
        end if
      case(3)
        ref_counts_1024(slot_idx) = ref_counts_1024(slot_idx) - 1
        if (ref_counts_1024(slot_idx) <= 0) then
          in_use_1024(slot_idx) = .false.
          pool_1024(slot_idx) = ''
        end if
      case(4)
        ref_counts_4096(slot_idx) = ref_counts_4096(slot_idx) - 1
        if (ref_counts_4096(slot_idx) <= 0) then
          in_use_4096(slot_idx) = .false.
          pool_4096(slot_idx) = ''
        end if
      case(5)
        ref_counts_16384(slot_idx) = ref_counts_16384(slot_idx) - 1
        if (ref_counts_16384(slot_idx) <= 0) then
          in_use_16384(slot_idx) = .false.
          pool_16384(slot_idx) = ''
        end if
      end select

      stats%total_deallocations = stats%total_deallocations + 1
      stats%current_strings = stats%current_strings - 1
    end if

    ! Clear reference
    ref%pool_index = 0
    ref%ref_count = 0
    ref%str_len = 0
    ref%data => null()

  end subroutine pool_release_string

  ! Copy data to a pooled string reference
  subroutine pool_copy_to_ref(ref, source_str)
    type(string_ref), intent(inout) :: ref
    character(len=*), intent(in) :: source_str
    integer :: copy_len

    if (.not. associated(ref%data)) return

    copy_len = min(len(source_str), ref%str_len)
    ref%data = ' '  ! Clear first
    ref%data(1:copy_len) = source_str(1:copy_len)

  end subroutine pool_copy_to_ref

  ! Get a pointer to the string data
  function pool_get_string_ptr(ref) result(ptr)
    type(string_ref), intent(in) :: ref
    character(:), pointer :: ptr

    if (associated(ref%data)) then
      ptr => ref%data
    else
      ptr => null()
    end if

  end function pool_get_string_ptr

  ! Intern a string for deduplication
  ! WARNING: Uses allocatable strings - may be problematic on macOS ARM64 with flang-new
  function pool_intern_string(str) result(ref)
    character(len=*), intent(in) :: str
    type(string_ref) :: ref
    integer :: i
    integer :: str_len

    if (.not. pool_initialized) call pool_init()

    str_len = len_trim(str)

#if defined(__APPLE__) && !defined(USE_C_STRINGS)
    ! On macOS WITHOUT C string library, cap interned string length to 127 bytes
    ! When USE_C_STRINGS is defined, the C library handles large strings safely
    if (str_len > 127) then
      ! String too long for safe interning on macOS - use regular pool instead
      ref = pool_get_string(min(str_len, 127))
      if (associated(ref%data)) then
        call pool_copy_to_ref(ref, str(1:min(str_len, 127)))
      end if
      return
    end if
#endif

    ! Check if already interned
    do i = 1, num_interned
      if (interned_strings(i) == str) then
        interned_refs(i) = interned_refs(i) + 1
        ref%pool_index = -10000 - i
        ref%ref_count = interned_refs(i)
        ref%str_len = str_len
        allocate(character(len=str_len) :: ref%data)
        ref%data = trim(str)
        stats%cache_hits = stats%cache_hits + 1
        return
      end if
    end do

    ! Add new interned string
    if (num_interned >= size(interned_strings)) then
      call expand_interned_pool()
    end if

    num_interned = num_interned + 1
    interned_strings(num_interned) = str
    interned_refs(num_interned) = 1

    ref%pool_index = -10000 - num_interned
    ref%ref_count = 1
    ref%str_len = str_len
    allocate(character(len=str_len) :: ref%data)
    ref%data = trim(str)

    stats%cache_misses = stats%cache_misses + 1

  end function pool_intern_string

  ! Expand interned string pool
  subroutine expand_interned_pool()
    character(len=256), allocatable :: temp_strings(:)
    integer, allocatable :: temp_refs(:)
    integer :: old_size, new_size

    old_size = size(interned_strings)
    new_size = old_size * 2

    allocate(temp_strings(old_size))
    allocate(temp_refs(old_size))
    temp_strings = interned_strings
    temp_refs = interned_refs

    deallocate(interned_strings, interned_refs)
    allocate(interned_strings(new_size))
    allocate(interned_refs(new_size))

    interned_strings(1:old_size) = temp_strings
    interned_refs(1:old_size) = temp_refs
    interned_refs(old_size+1:) = 0

    deallocate(temp_strings, temp_refs)
  end subroutine expand_interned_pool

  ! Get pool statistics
  subroutine pool_statistics(total_allocs, total_deallocs, current, peak, hit_rate)
    integer, intent(out) :: total_allocs, total_deallocs, current, peak
    real, intent(out) :: hit_rate

    total_allocs = int(stats%total_allocations)
    total_deallocs = int(stats%total_deallocations)
    current = stats%current_strings
    peak = stats%peak_strings

    if (stats%cache_hits + stats%cache_misses > 0) then
      hit_rate = real(stats%cache_hits) / real(stats%cache_hits + stats%cache_misses)
    else
      hit_rate = 0.0
    end if

  end subroutine pool_statistics

  ! Clean up the entire pool
  subroutine pool_cleanup()
    if (.not. pool_initialized) return

    ! Deallocate all pools
    if (allocated(pool_64)) deallocate(pool_64)
    if (allocated(pool_256)) deallocate(pool_256)
    if (allocated(pool_1024)) deallocate(pool_1024)
    if (allocated(pool_4096)) deallocate(pool_4096)
    if (allocated(pool_16384)) deallocate(pool_16384)

    ! Deallocate tracking arrays
    if (allocated(in_use_64)) deallocate(in_use_64)
    if (allocated(in_use_256)) deallocate(in_use_256)
    if (allocated(in_use_1024)) deallocate(in_use_1024)
    if (allocated(in_use_4096)) deallocate(in_use_4096)
    if (allocated(in_use_16384)) deallocate(in_use_16384)

    if (allocated(ref_counts_64)) deallocate(ref_counts_64)
    if (allocated(ref_counts_256)) deallocate(ref_counts_256)
    if (allocated(ref_counts_1024)) deallocate(ref_counts_1024)
    if (allocated(ref_counts_4096)) deallocate(ref_counts_4096)
    if (allocated(ref_counts_16384)) deallocate(ref_counts_16384)

    ! Clean up interned strings
    if (allocated(interned_strings)) deallocate(interned_strings)
    if (allocated(interned_refs)) deallocate(interned_refs)

    ! Reset statistics
    stats%total_allocations = 0
    stats%total_deallocations = 0
    stats%current_strings = 0
    stats%peak_strings = 0
    stats%cache_hits = 0
    stats%cache_misses = 0
    num_interned = 0

    pool_initialized = .false.

  end subroutine pool_cleanup

end module string_pool