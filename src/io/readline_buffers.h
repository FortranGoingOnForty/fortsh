! ==============================================================================
! Readline buffer access macros for pooled vs non-pooled compilation
! Use C preprocessor to handle buffer references cleanly
! ==============================================================================

#ifdef USE_MEMORY_POOL
  ! Pooled memory - use string_ref%data pointers
  #define BUFFER_DATA(state) state%buffer_ref%data
  #define ORIGINAL_BUFFER_DATA(state) state%original_buffer_ref%data
  #define KILL_BUFFER_DATA(state) state%kill_buffer_ref%data
  #define COMPLETION_BUFFER_DATA(state) state%last_completion_buffer_ref%data
  #define SEARCH_STRING_DATA(state) state%search_string_ref%data
  #define VI_COMMAND_DATA(state) state%vi_command_buffer_ref%data
  #define VI_YANK_DATA(state) state%vi_yank_buffer_ref%data
  #define VI_SEARCH_DATA(state) state%vi_search_pattern_ref%data
  #define MENU_PREFIX_DATA(state) state%menu_prefix_ref%data
  #define PROCESS_NAME_DATA(state) state%selected_process_name_ref%data
#else
  ! Traditional allocatable strings
  #define BUFFER_DATA(state) state%buffer
  #define ORIGINAL_BUFFER_DATA(state) state%original_buffer
  #define KILL_BUFFER_DATA(state) state%kill_buffer
  #define COMPLETION_BUFFER_DATA(state) state%last_completion_buffer
  #define SEARCH_STRING_DATA(state) state%search_string
  #define VI_COMMAND_DATA(state) state%vi_command_buffer
  #define VI_YANK_DATA(state) state%vi_yank_buffer
  #define VI_SEARCH_DATA(state) state%vi_search_pattern
  #define MENU_PREFIX_DATA(state) state%menu_prefix
  #define PROCESS_NAME_DATA(state) state%selected_process_name
#endif
