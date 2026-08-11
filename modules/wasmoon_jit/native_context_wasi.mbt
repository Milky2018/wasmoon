/// WASI state and symbol access for managed native JIT contexts.

///|
fn take_wasi_exit_code(context : JITContext) -> Int {
  let raw_code = c_jit_get_wasi_exit_code_managed(context)
  c_jit_clear_wasi_exit_managed(context)
  if raw_code < 0 {
    0
  } else {
    raw_code
  }
}

///|
pub fn make_cstring(s : String) -> FixedArray[Byte] {
  let len = s.length()
  let mut size = 0
  let mut i = 0
  while i < len {
    let c = s.code_unit_at(i).to_int()
    if c < 0x80 {
      size += 1
      i += 1
    } else if c < 0x800 {
      size += 2
      i += 1
    } else if c >= 0xD800 && c <= 0xDBFF && i + 1 < len {
      let c2 = s.code_unit_at(i + 1).to_int()
      if c2 >= 0xDC00 && c2 <= 0xDFFF {
        size += 4
        i += 2
      } else {
        size += 3
        i += 1
      }
    } else {
      size += 3
      i += 1
    }
  }
  let result = FixedArray::make(size + 1, b'\x00')
  let mut pos = 0
  i = 0
  while i < len {
    let c = s.code_unit_at(i).to_int()
    if c < 0x80 {
      result[pos] = c.to_byte()
      pos += 1
      i += 1
    } else if c < 0x800 {
      result[pos] = (0xC0 | (c >> 6)).to_byte()
      result[pos + 1] = (0x80 | (c & 0x3F)).to_byte()
      pos += 2
      i += 1
    } else if c >= 0xD800 && c <= 0xDBFF && i + 1 < len {
      let c2 = s.code_unit_at(i + 1).to_int()
      if c2 >= 0xDC00 && c2 <= 0xDFFF {
        let codepoint = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00)
        result[pos] = (0xF0 | (codepoint >> 18)).to_byte()
        result[pos + 1] = (0x80 | ((codepoint >> 12) & 0x3F)).to_byte()
        result[pos + 2] = (0x80 | ((codepoint >> 6) & 0x3F)).to_byte()
        result[pos + 3] = (0x80 | (codepoint & 0x3F)).to_byte()
        pos += 4
        i += 2
      } else {
        result[pos] = b'\xEF'
        result[pos + 1] = b'\xBF'
        result[pos + 2] = b'\xBD'
        pos += 3
        i += 1
      }
    } else {
      result[pos] = (0xE0 | (c >> 12)).to_byte()
      result[pos + 1] = (0x80 | ((c >> 6) & 0x3F)).to_byte()
      result[pos + 2] = (0x80 | (c & 0x3F)).to_byte()
      pos += 3
      i += 1
    }
  }
  result[size] = b'\x00'
  result
}

///|
fn set_wasi_stdout_capture(context : JITContext, enabled : Bool) -> Unit {
  c_jit_set_wasi_stdout_capture_managed(context, if enabled { 1 } else { 0 })
}

///|
fn set_wasi_stderr_capture(context : JITContext, enabled : Bool) -> Unit {
  c_jit_set_wasi_stderr_capture_managed(context, if enabled { 1 } else { 0 })
}

///|
fn set_wasi_stdin_buffer(context : JITContext, data : Bytes) -> Unit {
  c_jit_set_wasi_stdin_buffer_managed(context, data, data.length())
}

///|
fn set_wasi_stdin_callback(
  context : JITContext,
  callback : () -> Bytes,
) -> Unit {
  let call_closure : FuncRef[(() -> Bytes) -> Bytes] = fn(f : () -> Bytes) {
    f()
  }
  c_jit_set_wasi_stdin_callback_managed(context, call_closure, callback)
}

///|
fn clear_wasi_stdin_callback(context : JITContext) -> Unit {
  c_jit_clear_wasi_stdin_callback_managed(context)
}

///|
fn clear_wasi_stdin_buffer(context : JITContext) -> Unit {
  c_jit_clear_wasi_stdin_buffer_managed(context)
}

///|
fn take_wasi_stdout(context : JITContext) -> Bytes {
  c_jit_take_wasi_stdout_managed(context)
}

///|
fn take_wasi_stderr(context : JITContext) -> Bytes {
  c_jit_take_wasi_stderr_managed(context)
}

///|
fn init_wasi_context(
  context : JITContext,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
  quiet? : Bool = false,
) -> Unit {
  if quiet {
    c_jit_init_wasi_fds_quiet_managed(context, preopens.length())
  } else {
    c_jit_init_wasi_fds_managed(context, preopens.length())
  }
  set_wasi_stdout_capture(context, false)
  set_wasi_stderr_capture(context, false)
  clear_wasi_stdin_callback(context)
  clear_wasi_stdin_buffer(context)
  c_jit_set_wasi_args_managed(context, args.length())
  for i, arg in args {
    c_jit_set_wasi_arg_managed(context, i, make_cstring(arg))
  }
  c_jit_set_wasi_envs_managed(context, env.length())
  for i, e in env {
    c_jit_set_wasi_env_managed(context, i, make_cstring(e))
  }
  for i, entry in preopens {
    let (host, guest) = entry
    c_jit_add_preopen_managed(
      context,
      i,
      make_cstring(host),
      make_cstring(guest),
    )
  }
}

///|
pub fn NativeJITContext::init_wasi(
  self : NativeJITContext,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
  quiet? : Bool = false,
) -> Unit {
  init_wasi_context(self.handle, args, env, preopens, quiet~)
}

///|
pub fn NativeJITContext::set_wasi_stdout_capture(
  self : NativeJITContext,
  enabled : Bool,
) -> Unit {
  set_wasi_stdout_capture(self.handle, enabled)
}

///|
pub fn NativeJITContext::set_wasi_stderr_capture(
  self : NativeJITContext,
  enabled : Bool,
) -> Unit {
  set_wasi_stderr_capture(self.handle, enabled)
}

///|
pub fn NativeJITContext::set_wasi_stdin_buffer(
  self : NativeJITContext,
  data : Bytes,
) -> Unit {
  set_wasi_stdin_buffer(self.handle, data)
}

///|
pub fn NativeJITContext::set_wasi_stdin_callback(
  self : NativeJITContext,
  callback : () -> Bytes,
) -> Unit {
  set_wasi_stdin_callback(self.handle, callback)
}

///|
pub fn NativeJITContext::clear_wasi_stdin_callback(
  self : NativeJITContext,
) -> Unit {
  clear_wasi_stdin_callback(self.handle)
}

///|
pub fn NativeJITContext::clear_wasi_stdin_buffer(
  self : NativeJITContext,
) -> Unit {
  clear_wasi_stdin_buffer(self.handle)
}

///|
pub fn NativeJITContext::take_wasi_stdout(self : NativeJITContext) -> Bytes {
  take_wasi_stdout(self.handle)
}

///|
pub fn NativeJITContext::take_wasi_stderr(self : NativeJITContext) -> Bytes {
  take_wasi_stderr(self.handle)
}

///|
pub fn NativeJITContext::take_wasi_exit_code(self : NativeJITContext) -> Int {
  take_wasi_exit_code(self.handle)
}

///|
fn get_fd_write_ptr() -> Int64 {
  c_jit_get_fd_write_ptr()
}

///|
fn get_proc_exit_ptr() -> Int64 {
  c_jit_get_proc_exit_ptr()
}

///|
fn get_fd_read_ptr() -> Int64 {
  c_jit_get_fd_read_ptr()
}

///|
fn get_args_sizes_get_ptr() -> Int64 {
  c_jit_get_args_sizes_get_ptr()
}

///|
fn get_args_get_ptr() -> Int64 {
  c_jit_get_args_get_ptr()
}

///|
fn get_environ_sizes_get_ptr() -> Int64 {
  c_jit_get_environ_sizes_get_ptr()
}

///|
fn get_environ_get_ptr() -> Int64 {
  c_jit_get_environ_get_ptr()
}

///|
fn get_clock_time_get_ptr() -> Int64 {
  c_jit_get_clock_time_get_ptr()
}

///|
fn get_random_get_ptr() -> Int64 {
  c_jit_get_random_get_ptr()
}

///|
fn get_fd_close_ptr() -> Int64 {
  c_jit_get_fd_close_ptr()
}

///|
fn get_fd_fdstat_get_ptr() -> Int64 {
  c_jit_get_fd_fdstat_get_ptr()
}

///|
fn get_fd_prestat_get_ptr() -> Int64 {
  c_jit_get_fd_prestat_get_ptr()
}

///|
fn get_fd_prestat_dir_name_ptr() -> Int64 {
  c_jit_get_fd_prestat_dir_name_ptr()
}

///|
fn get_fd_seek_ptr() -> Int64 {
  c_jit_get_fd_seek_ptr()
}

///|
fn get_fd_tell_ptr() -> Int64 {
  c_jit_get_fd_tell_ptr()
}

///|
fn get_fd_sync_ptr() -> Int64 {
  c_jit_get_fd_sync_ptr()
}

///|
fn get_fd_datasync_ptr() -> Int64 {
  c_jit_get_fd_datasync_ptr()
}

///|
fn get_fd_filestat_get_ptr() -> Int64 {
  c_jit_get_fd_filestat_get_ptr()
}

///|
fn get_fd_filestat_set_size_ptr() -> Int64 {
  c_jit_get_fd_filestat_set_size_ptr()
}

///|
fn get_path_open_ptr() -> Int64 {
  c_jit_get_path_open_ptr()
}

///|
fn get_path_create_directory_ptr() -> Int64 {
  c_jit_get_path_create_directory_ptr()
}

///|
fn get_path_unlink_file_ptr() -> Int64 {
  c_jit_get_path_unlink_file_ptr()
}

///|
fn get_path_remove_directory_ptr() -> Int64 {
  c_jit_get_path_remove_directory_ptr()
}

///|
fn get_path_rename_ptr() -> Int64 {
  c_jit_get_path_rename_ptr()
}

///|
fn get_clock_res_get_ptr() -> Int64 {
  c_jit_get_clock_res_get_ptr()
}

///|
fn get_sched_yield_ptr() -> Int64 {
  c_jit_get_sched_yield_ptr()
}

///|
fn get_proc_raise_ptr() -> Int64 {
  c_jit_get_proc_raise_ptr()
}

///|
fn get_fd_advise_ptr() -> Int64 {
  c_jit_get_fd_advise_ptr()
}

///|
fn get_fd_allocate_ptr() -> Int64 {
  c_jit_get_fd_allocate_ptr()
}

///|
fn get_fd_pread_ptr() -> Int64 {
  c_jit_get_fd_pread_ptr()
}

///|
fn get_fd_pwrite_ptr() -> Int64 {
  c_jit_get_fd_pwrite_ptr()
}

///|
fn get_fd_readdir_ptr() -> Int64 {
  c_jit_get_fd_readdir_ptr()
}

///|
fn get_fd_renumber_ptr() -> Int64 {
  c_jit_get_fd_renumber_ptr()
}

///|
fn get_fd_fdstat_set_flags_ptr() -> Int64 {
  c_jit_get_fd_fdstat_set_flags_ptr()
}

///|
fn get_fd_fdstat_set_rights_ptr() -> Int64 {
  c_jit_get_fd_fdstat_set_rights_ptr()
}

///|
fn get_fd_filestat_set_times_ptr() -> Int64 {
  c_jit_get_fd_filestat_set_times_ptr()
}

///|
fn get_path_filestat_get_ptr() -> Int64 {
  c_jit_get_path_filestat_get_ptr()
}

///|
fn get_path_filestat_set_times_ptr() -> Int64 {
  c_jit_get_path_filestat_set_times_ptr()
}

///|
fn get_path_link_ptr() -> Int64 {
  c_jit_get_path_link_ptr()
}

///|
fn get_path_readlink_ptr() -> Int64 {
  c_jit_get_path_readlink_ptr()
}

///|
fn get_path_symlink_ptr() -> Int64 {
  c_jit_get_path_symlink_ptr()
}

///|
fn get_sock_accept_ptr() -> Int64 {
  c_jit_get_sock_accept_ptr()
}

///|
fn get_sock_recv_ptr() -> Int64 {
  c_jit_get_sock_recv_ptr()
}

///|
fn get_sock_send_ptr() -> Int64 {
  c_jit_get_sock_send_ptr()
}

///|
fn get_sock_shutdown_ptr() -> Int64 {
  c_jit_get_sock_shutdown_ptr()
}

///|
fn get_spectest_print_ptr() -> Int64 {
  c_jit_get_spectest_print_ptr()
}

///|
fn get_spectest_print_i32_ptr() -> Int64 {
  c_jit_get_spectest_print_i32_ptr()
}

///|
fn get_spectest_print_i64_ptr() -> Int64 {
  c_jit_get_spectest_print_i64_ptr()
}

///|
fn get_spectest_print_f32_ptr() -> Int64 {
  c_jit_get_spectest_print_f32_ptr()
}

///|
fn get_spectest_print_f64_ptr() -> Int64 {
  c_jit_get_spectest_print_f64_ptr()
}

///|
fn get_spectest_print_i32_f32_ptr() -> Int64 {
  c_jit_get_spectest_print_i32_f32_ptr()
}

///|
fn get_spectest_print_f64_f64_ptr() -> Int64 {
  c_jit_get_spectest_print_f64_f64_ptr()
}

///|
fn get_spectest_print_char_ptr() -> Int64 {
  c_jit_get_spectest_print_char_ptr()
}
