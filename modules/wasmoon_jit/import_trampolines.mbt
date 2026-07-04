/// Built-in import trampolines supported by the native JIT.

///|
/// Trampoline registry - maps (module, field) to function pointer getter.
let import_trampolines : Map[String, Map[String, () -> Int64]] = {
  let m : Map[String, Map[String, () -> Int64]] = {}
  // WASI Preview 1 functions.
  m["wasi_snapshot_preview1"] = {
    "fd_write": get_fd_write_ptr,
    "fd_read": get_fd_read_ptr,
    "fd_close": get_fd_close_ptr,
    "fd_seek": get_fd_seek_ptr,
    "fd_tell": get_fd_tell_ptr,
    "fd_sync": get_fd_sync_ptr,
    "fd_datasync": get_fd_datasync_ptr,
    "fd_fdstat_get": get_fd_fdstat_get_ptr,
    "fd_fdstat_set_flags": get_fd_fdstat_set_flags_ptr,
    "fd_fdstat_set_rights": get_fd_fdstat_set_rights_ptr,
    "fd_prestat_get": get_fd_prestat_get_ptr,
    "fd_prestat_dir_name": get_fd_prestat_dir_name_ptr,
    "fd_filestat_get": get_fd_filestat_get_ptr,
    "fd_filestat_set_size": get_fd_filestat_set_size_ptr,
    "fd_filestat_set_times": get_fd_filestat_set_times_ptr,
    "fd_advise": get_fd_advise_ptr,
    "fd_allocate": get_fd_allocate_ptr,
    "fd_pread": get_fd_pread_ptr,
    "fd_pwrite": get_fd_pwrite_ptr,
    "fd_readdir": get_fd_readdir_ptr,
    "fd_renumber": get_fd_renumber_ptr,
    "path_open": get_path_open_ptr,
    "path_create_directory": get_path_create_directory_ptr,
    "path_unlink_file": get_path_unlink_file_ptr,
    "path_remove_directory": get_path_remove_directory_ptr,
    "path_rename": get_path_rename_ptr,
    "path_filestat_get": get_path_filestat_get_ptr,
    "path_filestat_set_times": get_path_filestat_set_times_ptr,
    "path_link": get_path_link_ptr,
    "path_readlink": get_path_readlink_ptr,
    "path_symlink": get_path_symlink_ptr,
    "args_sizes_get": get_args_sizes_get_ptr,
    "args_get": get_args_get_ptr,
    "environ_sizes_get": get_environ_sizes_get_ptr,
    "environ_get": get_environ_get_ptr,
    "clock_time_get": get_clock_time_get_ptr,
    "clock_res_get": get_clock_res_get_ptr,
    "random_get": get_random_get_ptr,
    "proc_exit": get_proc_exit_ptr,
    "proc_raise": get_proc_raise_ptr,
    "sched_yield": get_sched_yield_ptr,
    "poll_oneoff": get_poll_oneoff_ptr,
    "sock_accept": get_sock_accept_ptr,
    "sock_recv": get_sock_recv_ptr,
    "sock_send": get_sock_send_ptr,
    "sock_shutdown": get_sock_shutdown_ptr,
  }
  m["spectest"] = {
    "print": get_spectest_print_ptr,
    "print_i32": get_spectest_print_i32_ptr,
    "print_i64": get_spectest_print_i64_ptr,
    "print_f32": get_spectest_print_f32_ptr,
    "print_f64": get_spectest_print_f64_ptr,
    "print_i32_f32": get_spectest_print_i32_f32_ptr,
    "print_f64_f64": get_spectest_print_f64_f64_ptr,
    "print_char": get_spectest_print_char_ptr,
  }
  m
}

///|
/// Get trampoline function pointer for an import.
/// Returns None if the import is not supported by JIT.
pub fn get_import_trampoline(
  module_name : String,
  field_name : String,
) -> Int64? {
  import_trampolines
  .get(module_name)
  .bind(fn(m) { m.get(field_name) })
  .map(fn(f) { f() })
}

///|
pub fn resolve_import_function_ptr(
  external_imports : Map[String, Map[String, Int64]],
  module_name : String,
  field_name : String,
) -> Int64? {
  match external_imports.get(module_name) {
    Some(module_imports) =>
      match module_imports.get(field_name) {
        Some(ptr) => Some(ptr)
        None => get_import_trampoline(module_name, field_name)
      }
    None => get_import_trampoline(module_name, field_name)
  }
}

///|
/// Check if a module is known to JIT (has trampoline support).
pub fn is_jit_supported_module(module_name : String) -> Bool {
  import_trampolines.contains(module_name)
}
