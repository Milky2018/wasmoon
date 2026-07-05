/// Native JIT runtime primitives shared by Wasmoon integration code.
///
/// This module intentionally owns only Wasmoon-independent FFI wrappers and
/// managed native handles. Entry trampoline planning now lives in
/// `wasmoon_jit`; the production `JITContext` wrapper remains in
/// `Milky2018/wasmoon/jit` until its call path switches to that reusable
/// trampoline planner.

///|
pub using @jit_ffi {c_jit_write_i64, c_jit_write_u32, c_jit_read_i64}

///|
/// Low-level trap detail captured by the JIT signal handlers (best-effort).
pub struct TrapDetails {
  signal : Int
  pc : Int64
  lr : Int64
  fp : Int64
  frame_lr : Int64
  fault_addr : Int64
  brk_imm : Int
  func_idx : Int
  x0 : Int64
  x1 : Int64
  x2 : Int64
  x3 : Int64
  x6 : Int64
  x7 : Int64
  x8 : Int64
  x9 : Int64
  x10 : Int64
  x11 : Int64
  x15 : Int64
}

///|
pub fn TrapDetails::new() -> TrapDetails {
  {
    signal: 0,
    pc: 0L,
    lr: 0L,
    fp: 0L,
    frame_lr: 0L,
    fault_addr: 0L,
    brk_imm: 0,
    func_idx: -1,
    x0: 0L,
    x1: 0L,
    x2: 0L,
    x3: 0L,
    x6: 0L,
    x7: 0L,
    x8: 0L,
    x9: 0L,
    x10: 0L,
    x11: 0L,
    x15: 0L,
  }
}

///|
/// Get the last captured trap details (best-effort).
/// These fields are reset at the start of each JIT call.
pub fn get_last_trap_details() -> TrapDetails {
  {
    signal: @jit_ffi.c_jit_get_trap_signal(),
    pc: @jit_ffi.c_jit_get_trap_pc(),
    lr: @jit_ffi.c_jit_get_trap_lr(),
    fp: @jit_ffi.c_jit_get_trap_fp(),
    frame_lr: @jit_ffi.c_jit_get_trap_frame_lr(),
    fault_addr: @jit_ffi.c_jit_get_trap_fault_addr(),
    brk_imm: @jit_ffi.c_jit_get_trap_brk_imm(),
    func_idx: @jit_ffi.c_jit_get_trap_func_idx(),
    x0: @jit_ffi.c_jit_get_trap_xreg(0),
    x1: @jit_ffi.c_jit_get_trap_xreg(1),
    x2: @jit_ffi.c_jit_get_trap_xreg(2),
    x3: @jit_ffi.c_jit_get_trap_xreg(3),
    x6: @jit_ffi.c_jit_get_trap_xreg(6),
    x7: @jit_ffi.c_jit_get_trap_xreg(7),
    x8: @jit_ffi.c_jit_get_trap_xreg(8),
    x9: @jit_ffi.c_jit_get_trap_xreg(9),
    x10: @jit_ffi.c_jit_get_trap_xreg(10),
    x11: @jit_ffi.c_jit_get_trap_xreg(11),
    x15: @jit_ffi.c_jit_get_trap_xreg(15),
  }
}

///|
pub fn format_signal_name(sig : Int) -> String {
  match sig {
    5 => "SIGTRAP(5)"
    10 => "SIGBUS(10)"
    11 => "SIGSEGV(11)"
    7 => "SIGBUS(7)"
    _ => "SIG(\{sig})"
  }
}

///|
pub fn jit_trap_message(code : Int) -> String {
  match code {
    1 => "out of bounds memory access"
    2 => "call stack exhausted"
    3 => "unreachable"
    4 => "indirect call type mismatch"
    5 => "invalid conversion to integer"
    6 => "integer divide by zero"
    7 => "integer overflow"
    8 => "jit backend trap"
    9 => "out of memory"
    10 => "gc precise roots unavailable"
    _ => "unknown trap"
  }
}

///|
pub fn legacy_trap_immediate_from_message(msg : String) -> Int {
  // Keep this mapping in sync with `jit_ffi/trap.c` BRK/UD2 immediate decoding:
  // 0 unreachable, 1 out of bounds, 2 type mismatch, 3 invalid conversion,
  // 4 divide by zero, 5 overflow, 6 backend/unknown JIT trap.
  if msg == "unreachable" {
    0
  } else if msg.contains("out of bounds") {
    1
  } else if msg.contains("type mismatch") {
    2
  } else if msg.contains("invalid conversion") {
    3
  } else if msg.contains("divide by zero") {
    4
  } else if msg.contains("overflow") {
    5
  } else {
    6
  }
}

///|
pub fn take_pending_trap_message() -> String? {
  let code = @jit_ffi.c_jit_get_trap_code()
  if code == 0 {
    None
  } else {
    @jit_ffi.c_jit_clear_trap()
    Some(jit_trap_message(code))
  }
}

///|
pub fn is_wasi_exit_trap_code(code : Int) -> Bool {
  code == 100
}

///|
pub fn take_wasi_exit_code(ctx_ptr : Int64) -> Int {
  let raw_code = @jit_ffi.c_jit_get_wasi_exit_code(ctx_ptr)
  @jit_ffi.c_jit_clear_wasi_exit(ctx_ptr)
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
pub fn set_wasi_stdout_capture(ctx_ptr : Int64, enabled : Bool) -> Unit {
  @jit_ffi.c_jit_set_wasi_stdout_capture(ctx_ptr, if enabled { 1 } else { 0 })
}

///|
pub fn set_wasi_stderr_capture(ctx_ptr : Int64, enabled : Bool) -> Unit {
  @jit_ffi.c_jit_set_wasi_stderr_capture(ctx_ptr, if enabled { 1 } else { 0 })
}

///|
pub fn set_wasi_stdin_buffer(ctx_ptr : Int64, data : Bytes) -> Unit {
  @jit_ffi.c_jit_set_wasi_stdin_buffer(ctx_ptr, data, data.length())
}

///|
pub fn set_wasi_stdin_callback(ctx_ptr : Int64, callback : () -> Bytes) -> Unit {
  let call_closure : FuncRef[(() -> Bytes) -> Bytes] = fn(f : () -> Bytes) {
    f()
  }
  @jit_ffi.c_jit_set_wasi_stdin_callback(ctx_ptr, call_closure, callback)
}

///|
pub fn clear_wasi_stdin_callback(ctx_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_clear_wasi_stdin_callback(ctx_ptr)
}

///|
pub fn clear_wasi_stdin_buffer(ctx_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_clear_wasi_stdin_buffer(ctx_ptr)
}

///|
pub fn take_wasi_stdout(ctx_ptr : Int64) -> Bytes {
  @jit_ffi.c_jit_take_wasi_stdout(ctx_ptr)
}

///|
pub fn take_wasi_stderr(ctx_ptr : Int64) -> Bytes {
  @jit_ffi.c_jit_take_wasi_stderr(ctx_ptr)
}

///|
pub fn init_wasi_context(
  ctx_ptr : Int64,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
  quiet? : Bool = false,
) -> Unit {
  if quiet {
    @jit_ffi.c_jit_init_wasi_fds_quiet(ctx_ptr, preopens.length())
  } else {
    @jit_ffi.c_jit_init_wasi_fds(ctx_ptr, preopens.length())
  }
  set_wasi_stdout_capture(ctx_ptr, false)
  set_wasi_stderr_capture(ctx_ptr, false)
  clear_wasi_stdin_callback(ctx_ptr)
  clear_wasi_stdin_buffer(ctx_ptr)
  @jit_ffi.c_jit_set_wasi_args(ctx_ptr, args.length())
  for i, arg in args {
    @jit_ffi.c_jit_set_wasi_arg(ctx_ptr, i, make_cstring(arg))
  }
  @jit_ffi.c_jit_set_wasi_envs(ctx_ptr, env.length())
  for i, e in env {
    @jit_ffi.c_jit_set_wasi_env(ctx_ptr, i, make_cstring(e))
  }
  for i, entry in preopens {
    let (host, guest) = entry
    @jit_ffi.c_jit_add_preopen(
      ctx_ptr,
      i,
      make_cstring(host),
      make_cstring(guest),
    )
  }
}

///|
pub fn context_func_table_ptr(ctx_ptr : Int64) -> Int64 {
  @jit_ffi.c_jit_ctx_get_func_table(ctx_ptr)
}

///|
pub fn context_func_count(ctx_ptr : Int64) -> Int {
  @jit_ffi.c_jit_ctx_get_func_count(ctx_ptr)
}

///|
pub fn context_table_ptr(ctx_ptr : Int64, table_idx : Int) -> Int64 {
  @jit_ffi.c_jit_ctx_get_table_ptr(ctx_ptr, table_idx)
}

///|
pub fn context_table_size(ctx_ptr : Int64, table_idx : Int) -> Int {
  @jit_ffi.c_jit_ctx_get_table_size(ctx_ptr, table_idx)
}

///|
pub fn throw_exception_tag(ctx_ptr : Int64, tag_addr : Int) -> Unit {
  @jit_ffi.c_jit_exception_throw_tag(ctx_ptr, tag_addr)
}

///|
pub fn throw_exception_values(
  ctx_ptr : Int64,
  tag_addr : Int,
  values : Array[Int64],
) -> Unit {
  let payload = FixedArray::makei(values.length(), fn(i) { values[i] })
  @jit_ffi.c_jit_exception_throw_values(
    ctx_ptr,
    tag_addr,
    payload,
    values.length(),
  )
}

///|
pub fn setup_segments(
  ctx_ptr : Int64,
  datas : Array[@types.Data],
  elem_segments : Array[Array[Int64]],
  data_dropped? : Array[Bool] = [],
  elem_dropped? : Array[Bool] = [],
) -> Unit {
  @jit_ffi.c_jit_ctx_init_data_segments(ctx_ptr, datas.length())
  for i, data in datas {
    let bytes = data.init
    let size = bytes.length()
    let dropped = if i < data_dropped.length() && data_dropped[i] {
      1
    } else {
      0
    }
    let buf = FixedArray::make(size.max(1), b'\x00')
    for j in 0..<size {
      buf[j] = bytes[j]
    }
    @jit_ffi.c_jit_ctx_add_data_segment(ctx_ptr, i, buf, size, dropped)
  }

  @jit_ffi.c_jit_ctx_init_elem_segments(ctx_ptr, elem_segments.length())
  for i, seg in elem_segments {
    let dropped = if i < elem_dropped.length() && elem_dropped[i] {
      1
    } else {
      0
    }
    let nslots = seg.length()
    let buf = FixedArray::make(nslots.max(1), 0L)
    for j in 0..<nslots {
      buf[j] = seg[j]
    }
    @jit_ffi.c_jit_ctx_add_elem_segment(ctx_ptr, i, buf, nslots / 2, dropped)
  }
}

///|
pub fn clear_segments(ctx_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_ctx_clear_segments(ctx_ptr)
}

///|
/// Get the runtime store function address for the current JIT -> hostcall.
///
/// This value is set by `wasmoon_jit_hostcall` right before invoking the
/// MoonBit hostcall callback.
pub fn get_hostcall_func_addr() -> Int {
  @jit_ffi.c_jit_get_hostcall_func_idx()
}

///|
/// Get the pointer to the hostcall scratch `values_vec` buffer.
pub fn get_hostcall_values_ptr() -> Int64 {
  @jit_ffi.c_jit_get_hostcall_values_ptr()
}

///|
/// Get the number of argument *slots* in `values_vec`.
///
/// Note: slots are 8 bytes each; V128 occupies 2 slots.
pub fn get_hostcall_num_arg_slots() -> Int {
  @jit_ffi.c_jit_get_hostcall_num_args()
}

///|
/// Get the number of result *slots* in `values_vec`.
///
/// Note: slots are 8 bytes each; V128 occupies 2 slots.
pub fn get_hostcall_num_result_slots() -> Int {
  @jit_ffi.c_jit_get_hostcall_num_results()
}

///|
/// Memory information for JIT execution.
pub struct MemoryInfo {
  ptr : Int64 // Pointer to `wasmoon_memory_t` (memory descriptor)
  size : Int64 // Initial size in bytes (informational)
  max_pages : Int? // Max pages (None = unlimited)
}

///|
/// Create a new MemoryInfo.
pub fn MemoryInfo::new(
  ptr : Int64,
  size : Int64,
  max_pages : Int?,
) -> MemoryInfo {
  { ptr, size, max_pages }
}

///|
/// Allocate linear memory for WASM (returns 0 on failure).
pub fn alloc_memory(size : Int64) -> Int64 {
  @jit_ffi.c_jit_alloc_memory(size)
}

///|
/// Allocate a `wasmoon_memory_t` descriptor with owned backing memory.
pub fn alloc_memory_desc(
  size_bytes : Int64,
  max_pages : Int?,
  is_memory64? : Bool = false,
  page_size_log2? : Int = 16,
  is_shared? : Bool = false,
) -> Int64 {
  @jit_ffi.c_jit_alloc_memory_desc(
    size_bytes,
    max_pages.unwrap_or(-1),
    if is_memory64 {
      1
    } else {
      0
    },
    page_size_log2,
    if is_shared {
      1
    } else {
      0
    },
  )
}

///|
/// Allocate a guarded (reserved) memory descriptor for memory32 memory0.
/// This is required for bounds-check elimination; out-of-bounds accesses trap via guard pages.
pub fn alloc_guarded_memory_desc(
  initial_pages : Int,
  max_pages : Int?,
) -> Int64 {
  @jit_ffi.c_jit_alloc_guarded_memory_desc(
    initial_pages.to_int64(),
    max_pages.unwrap_or(-1).to_int64(),
  )
}

///|
pub fn free_memory(mem_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_free_memory(mem_ptr)
}

///|
pub fn free_memory_desc(mem_desc_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_free_memory_desc(mem_desc_ptr)
}

///|
/// Initialize memory with data at offset.
pub fn memory_init(mem_ptr : Int64, offset : Int64, data : Bytes) -> Bool {
  let size = data.length()
  if size == 0 {
    return true
  }
  @jit_ffi.c_jit_memory_init_bytes(mem_ptr, offset, data, size) == 0
}

///|
/// Read `size` bytes from linear memory at offset.
pub fn memory_read(mem_ptr : Int64, offset : Int64, size : Int) -> Bytes {
  if mem_ptr == 0L || size <= 0 {
    return b""
  }
  let out = FixedArray::make(size, b'\x00')
  let rc = @jit_ffi.c_jit_memory_read(mem_ptr, offset, out, size)
  if rc != 0 {
    return b""
  }
  let arr : Array[Byte] = Array::make(size, b'\x00')
  for i in 0..<size {
    arr[i] = out[i]
  }
  Bytes::from_array(arr)
}

///|
/// Shared indirect table that can be used by multiple JIT modules.
struct JITTable {
  mut table_ptr : Int64 // Pointer to the shared C-side table
  mut size : Int
  max : Int?
} derive(Debug)

///|
/// Create a new shared JIT table.
/// Note: size 0 is valid (empty table that can grow later).
pub fn JITTable::new(size : Int, max : Int?) -> JITTable? {
  if size < 0 {
    return None
  }
  let alloc_size = if size == 0 { 1 } else { size }
  let table_ptr = @jit_ffi.c_jit_alloc_shared_indirect_table(alloc_size)
  if table_ptr == 0L {
    return None
  }
  Some({ table_ptr, size, max })
}

///|
/// Set an entry in the shared table.
pub fn JITTable::set(
  self : JITTable,
  table_idx : Int,
  func_ptr : Int64,
  type_hash : Int,
) -> Unit {
  if table_idx < 0 || table_idx >= self.size {
    return
  }
  @jit_ffi.c_jit_shared_table_set(
    self.table_ptr,
    table_idx,
    func_ptr,
    type_hash,
  )
}

///|
/// Read raw entry value bits from the shared table.
pub fn JITTable::get_entry_value(self : JITTable, table_idx : Int) -> Int64 {
  if table_idx < 0 || table_idx >= self.size {
    return 0L
  }
  c_jit_read_i64(self.table_ptr + (table_idx * 16).to_int64())
}

///|
/// Read raw entry type index from the shared table.
pub fn JITTable::get_entry_type(self : JITTable, table_idx : Int) -> Int {
  if table_idx < 0 || table_idx >= self.size {
    return -1
  }
  c_jit_read_i64(self.table_ptr + (table_idx * 16 + 8).to_int64()).to_int()
}

///|
/// Get the table size.
pub fn JITTable::get_size(self : JITTable) -> Int {
  self.size
}

///|
/// Get the raw shared table pointer.
pub fn JITTable::raw_ptr(self : JITTable) -> Int64 {
  self.table_ptr
}

///|
/// Refresh table pointer and size from the active JIT context view.
pub fn JITTable::refresh_layout(
  self : JITTable,
  table_ptr : Int64,
  size : Int,
) -> Unit {
  if table_ptr == 0L || size < 0 {
    return
  }
  self.table_ptr = table_ptr
  self.size = size
}

///|
/// Get the table max size.
pub fn JITTable::get_max(self : JITTable) -> Int? {
  self.max
}

///|
pub fn get_fd_write_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_write_ptr()
}

///|
pub fn get_proc_exit_ptr() -> Int64 {
  @jit_ffi.c_jit_get_proc_exit_ptr()
}

///|
pub fn get_fd_read_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_read_ptr()
}

///|
pub fn get_args_sizes_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_args_sizes_get_ptr()
}

///|
pub fn get_args_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_args_get_ptr()
}

///|
pub fn get_environ_sizes_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_environ_sizes_get_ptr()
}

///|
pub fn get_environ_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_environ_get_ptr()
}

///|
pub fn get_clock_time_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_clock_time_get_ptr()
}

///|
pub fn get_random_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_random_get_ptr()
}

///|
pub fn get_fd_close_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_close_ptr()
}

///|
pub fn get_fd_fdstat_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_fdstat_get_ptr()
}

///|
pub fn get_fd_prestat_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_prestat_get_ptr()
}

///|
pub fn get_fd_prestat_dir_name_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_prestat_dir_name_ptr()
}

///|
pub fn get_fd_seek_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_seek_ptr()
}

///|
pub fn get_fd_tell_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_tell_ptr()
}

///|
pub fn get_fd_sync_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_sync_ptr()
}

///|
pub fn get_fd_datasync_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_datasync_ptr()
}

///|
pub fn get_fd_filestat_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_filestat_get_ptr()
}

///|
pub fn get_fd_filestat_set_size_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_filestat_set_size_ptr()
}

///|
pub fn get_path_open_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_open_ptr()
}

///|
pub fn get_path_create_directory_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_create_directory_ptr()
}

///|
pub fn get_path_unlink_file_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_unlink_file_ptr()
}

///|
pub fn get_path_remove_directory_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_remove_directory_ptr()
}

///|
pub fn get_path_rename_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_rename_ptr()
}

///|
pub fn get_clock_res_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_clock_res_get_ptr()
}

///|
pub fn get_sched_yield_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sched_yield_ptr()
}

///|
pub fn get_proc_raise_ptr() -> Int64 {
  @jit_ffi.c_jit_get_proc_raise_ptr()
}

///|
pub fn get_poll_oneoff_ptr() -> Int64 {
  @jit_ffi.c_jit_get_poll_oneoff_ptr()
}

///|
pub fn get_fd_advise_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_advise_ptr()
}

///|
pub fn get_fd_allocate_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_allocate_ptr()
}

///|
pub fn get_fd_pread_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_pread_ptr()
}

///|
pub fn get_fd_pwrite_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_pwrite_ptr()
}

///|
pub fn get_fd_readdir_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_readdir_ptr()
}

///|
pub fn get_fd_renumber_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_renumber_ptr()
}

///|
pub fn get_fd_fdstat_set_flags_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_fdstat_set_flags_ptr()
}

///|
pub fn get_fd_fdstat_set_rights_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_fdstat_set_rights_ptr()
}

///|
pub fn get_fd_filestat_set_times_ptr() -> Int64 {
  @jit_ffi.c_jit_get_fd_filestat_set_times_ptr()
}

///|
pub fn get_path_filestat_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_filestat_get_ptr()
}

///|
pub fn get_path_filestat_set_times_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_filestat_set_times_ptr()
}

///|
pub fn get_path_link_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_link_ptr()
}

///|
pub fn get_path_readlink_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_readlink_ptr()
}

///|
pub fn get_path_symlink_ptr() -> Int64 {
  @jit_ffi.c_jit_get_path_symlink_ptr()
}

///|
pub fn get_sock_accept_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sock_accept_ptr()
}

///|
pub fn get_sock_recv_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sock_recv_ptr()
}

///|
pub fn get_sock_send_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sock_send_ptr()
}

///|
pub fn get_sock_shutdown_ptr() -> Int64 {
  @jit_ffi.c_jit_get_sock_shutdown_ptr()
}

///|
pub fn get_spectest_print_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_ptr()
}

///|
pub fn get_spectest_print_i32_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_i32_ptr()
}

///|
pub fn get_spectest_print_i64_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_i64_ptr()
}

///|
pub fn get_spectest_print_f32_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_f32_ptr()
}

///|
pub fn get_spectest_print_f64_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_f64_ptr()
}

///|
pub fn get_spectest_print_i32_f32_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_i32_f32_ptr()
}

///|
pub fn get_spectest_print_f64_f64_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_f64_f64_ptr()
}

///|
pub fn get_spectest_print_char_ptr() -> Int64 {
  @jit_ffi.c_jit_get_spectest_print_char_ptr()
}

///|
fn push_u32_le(bytes : Array[Int], value : Int) -> Unit {
  bytes.push(value & 0xff)
  bytes.push((value >> 8) & 0xff)
  bytes.push((value >> 16) & 0xff)
  bytes.push((value >> 24) & 0xff)
}

///|
fn pack_u64_le(bytes : Array[Int], start : Int) -> Int64 {
  let mut value : Int64 = 0L
  for i in 0..<8 {
    let b = bytes[start + i].to_int64() & 0xffL
    value = value | (b << (i * 8))
  }
  value
}

///|
pub fn build_aarch64_load_imm64_fixed_bytes(
  reg : Int,
  imm : Int64,
) -> Array[Int] {
  let bytes : Array[Int] = []
  let v0 = (imm & 0xffffL).to_int()
  let v1 = ((imm >> 16) & 0xffffL).to_int()
  let v2 = ((imm >> 32) & 0xffffL).to_int()
  let v3 = ((imm >> 48) & 0xffffL).to_int()
  push_u32_le(bytes, 0xd2800000 | ((v0 & 0xffff) << 5) | (reg & 0x1f))
  push_u32_le(
    bytes,
    0xf2800000 | (1 << 21) | ((v1 & 0xffff) << 5) | (reg & 0x1f),
  )
  push_u32_le(
    bytes,
    0xf2800000 | (2 << 21) | ((v2 & 0xffff) << 5) | (reg & 0x1f),
  )
  push_u32_le(
    bytes,
    0xf2800000 | (3 << 21) | ((v3 & 0xffff) << 5) | (reg & 0x1f),
  )
  bytes
}

///|
pub fn build_aarch64_direct_call_stub(target_ptr : Int64) -> Array[Int] {
  let bytes = build_aarch64_load_imm64_fixed_bytes(16, target_ptr)
  push_u32_le(bytes, 0xd61f0000 | ((16 & 0x1f) << 5))
  bytes
}

///|
pub fn build_x64_direct_call_stub(target_ptr : Int64) -> Array[Int] {
  let bytes : Array[Int] = []
  bytes.push(0x49)
  bytes.push(0xbb)
  let mut value = target_ptr
  for _ in 0..<8 {
    bytes.push((value & 0xffL).to_int())
    value = value >> 8
  }
  bytes.push(0x41)
  bytes.push(0xff)
  bytes.push(0xe3)
  bytes
}

///|
pub fn direct_call_idx_memory_fill_mem0() -> Int {
  -1001
}

///|
pub fn direct_call_idx_memory_copy_mem0() -> Int {
  -1002
}

///|
pub struct DirectCallStubSet {
  exec_codes : Array[ExecCode]
  targets : Map[Int, Int64]
}

///|
pub suberror DirectCallStubInstallError {
  UnsupportedDirectCallStubTarget(pseudo_idx~ : Int, code_size~ : Int)
  DirectCallStubAllocationFailed(pseudo_idx~ : Int, code_size~ : Int)
} derive(Debug, Eq)

///|
fn direct_call_stub_code_for_target(
  target : @cwasm.TargetArch,
  target_ptr : Int64,
) -> Array[Int] {
  match target {
    AArch64 => build_aarch64_direct_call_stub(target_ptr)
    X86_64 => build_x64_direct_call_stub(target_ptr)
    Unknown => []
  }
}

///|
fn DirectCallStubSet::install_one(
  self : DirectCallStubSet,
  target : @cwasm.TargetArch,
  pseudo_idx : Int,
  target_ptr : Int64,
) -> Unit raise DirectCallStubInstallError {
  let stub_code = direct_call_stub_code_for_target(target, target_ptr)
  if stub_code.length() == 0 {
    raise UnsupportedDirectCallStubTarget(
      pseudo_idx~,
      code_size=stub_code.length(),
    )
  }
  match ExecCode::new(stub_code) {
    Some(ec) => {
      self.exec_codes.push(ec)
      self.targets.set(pseudo_idx, ec.ptr())
    }
    None =>
      raise DirectCallStubAllocationFailed(
        pseudo_idx~,
        code_size=stub_code.length(),
      )
  }
}

///|
pub fn install_direct_call_stubs_for_target(
  target : @cwasm.TargetArch,
) -> DirectCallStubSet raise DirectCallStubInstallError {
  let stubs : DirectCallStubSet = { exec_codes: [], targets: {} }
  stubs.install_one(
    target,
    direct_call_idx_memory_fill_mem0(),
    @jit_ffi.c_jit_get_memory_fill_mem0_ptr(),
  )
  stubs.install_one(
    target,
    direct_call_idx_memory_copy_mem0(),
    @jit_ffi.c_jit_get_memory_copy_mem0_ptr(),
  )
  stubs
}

///|
pub fn patch_aarch64_load_imm64_fixed(
  exec_ptr : Int64,
  offset : Int,
  reg : Int,
  imm : Int64,
) -> Unit {
  let bytes = build_aarch64_load_imm64_fixed_bytes(reg, imm)
  if bytes.length() != 16 {
    abort("unexpected load_imm64_fixed size")
  }
  let base = exec_ptr + offset.to_int64()
  c_jit_write_i64(base, pack_u64_le(bytes, 0))
  c_jit_write_i64(base + 8L, pack_u64_le(bytes, 8))
}

///|
pub fn resolve_func_addr_fixup_target(
  func_idx : Int,
  func_table_ptr : Int64,
) -> Int64? {
  if func_idx >= 0 {
    if func_table_ptr == 0L {
      return None
    }
    Some(c_jit_read_i64(func_table_ptr + func_idx.to_int64() * 8L))
  } else {
    resolve_runtime_func_fixup_idx(func_idx)
  }
}

///|
pub fn resolve_call_fixup_target(
  func_idx : Int,
  func_table_ptr : Int64,
  direct_call_targets : Map[Int, Int64],
) -> Int64? {
  if func_idx >= 0 {
    if func_table_ptr == 0L {
      return None
    }
    Some(c_jit_read_i64(func_table_ptr + func_idx.to_int64() * 8L))
  } else {
    direct_call_targets.get(func_idx)
  }
}

///|
pub fn required_context_function_count(
  precompiled : @cwasm.PrecompiledModule,
  func_signature_count : Int,
) -> Int {
  let mut count = precompiled.imports.length()
  for entry in precompiled.functions {
    let candidate = entry.func_idx + 1
    if candidate > count {
      count = candidate
    }
  }
  if func_signature_count > count {
    func_signature_count
  } else {
    count
  }
}

///|
pub fn patch_aarch64_func_addr_fixup(
  exec_ptr : Int64,
  fixup : @cwasm.FuncAddrFixup,
  target_ptr : Int64,
) -> Unit {
  patch_aarch64_func_addr_fixup_parts(
    exec_ptr,
    fixup.offset,
    fixup.reg,
    target_ptr,
  )
}

///|
pub fn patch_aarch64_func_addr_fixup_parts(
  exec_ptr : Int64,
  offset : Int,
  reg : Int,
  target_ptr : Int64,
) -> Unit {
  patch_aarch64_load_imm64_fixed(exec_ptr, offset, reg, target_ptr)
}

///|
pub fn patch_aarch64_func_addr_fixup_raw(
  exec_ptr : Int64,
  offset : Int,
  reg : Int,
  func_idx : Int,
  func_table_ptr : Int64,
) -> Unit {
  let target_ptr = match
    resolve_func_addr_fixup_target(func_idx, func_table_ptr) {
    Some(ptr) => ptr
    None => abort("unknown func addr fixup idx \{func_idx}")
  }
  patch_aarch64_func_addr_fixup_parts(exec_ptr, offset, reg, target_ptr)
}

///|
pub fn patch_func_addr_fixup_raw_for_target(
  target : @cwasm.TargetArch,
  exec_ptr : Int64,
  offset : Int,
  reg : Int,
  func_idx : Int,
  func_table_ptr : Int64,
) -> Unit {
  match target {
    AArch64 =>
      patch_aarch64_func_addr_fixup_raw(
        exec_ptr, offset, reg, func_idx, func_table_ptr,
      )
    X86_64 => abort("x64 cwasm function-address fixups are not modelled yet")
    Unknown =>
      abort("cannot patch function-address fixup for unknown cwasm target")
  }
}

///|
pub fn patch_aarch64_func_addr_fixups(
  exec_ptr : Int64,
  fixups : Array[@cwasm.FuncAddrFixup],
  func_table_ptr : Int64,
) -> Unit {
  for fixup in fixups {
    let target_ptr = match
      resolve_func_addr_fixup_target(fixup.func_idx, func_table_ptr) {
      Some(ptr) => ptr
      None => abort("unknown func addr fixup idx \{fixup.func_idx}")
    }
    patch_aarch64_func_addr_fixup(exec_ptr, fixup, target_ptr)
  }
}

///|
pub fn patch_func_addr_fixups_for_target(
  target : @cwasm.TargetArch,
  exec_ptr : Int64,
  fixups : Array[@cwasm.FuncAddrFixup],
  func_table_ptr : Int64,
) -> Unit {
  match target {
    AArch64 => patch_aarch64_func_addr_fixups(exec_ptr, fixups, func_table_ptr)
    X86_64 =>
      if fixups.length() > 0 {
        abort("x64 cwasm function-address fixups are not modelled yet")
      }
    Unknown =>
      if fixups.length() > 0 {
        abort("cannot patch function-address fixups for unknown cwasm target")
      }
  }
}

///|
pub fn encode_aarch64_bl_imm26(pc : Int64, target_ptr : Int64) -> Int? {
  let diff = target_ptr - pc
  if diff % 4L != 0L {
    return None
  }
  let imm26 = diff / 4L
  if imm26 < -0x2000000L || imm26 > 0x1FFFFFFL {
    return None
  }
  Some((0x94000000L | (imm26 & 0x3FFFFFFL)).to_int())
}

///|
pub fn encode_x64_call_rel32_disp(pc : Int64, target_ptr : Int64) -> Int? {
  let disp = target_ptr - (pc + 5L)
  if disp < -0x80000000L || disp > 0x7fffffffL {
    return None
  }
  Some((disp & 0xffffffffL).to_int())
}

///|
pub fn patch_aarch64_call_veneer_target(
  exec_ptr : Int64,
  fixup : @cwasm.CallFixup,
  target_ptr : Int64,
) -> Unit {
  // Veneer layout (16 bytes):
  //   +0:  ldr x16, #8
  //   +4:  br x16
  //   +8:  target_ptr literal (u64)
  c_jit_write_i64(exec_ptr + fixup.veneer_offset.to_int64() + 8L, target_ptr)
}

///|
pub fn patch_aarch64_direct_call(
  exec_ptr : Int64,
  fixup : @cwasm.CallFixup,
  target_ptr : Int64,
) -> Unit {
  let pc = exec_ptr + fixup.offset.to_int64()
  if encode_aarch64_bl_imm26(pc, target_ptr) is Some(encoded) {
    c_jit_write_u32(pc, encoded)
    return
  }
  if fixup.veneer_offset >= 0 {
    let veneer_pc = exec_ptr + fixup.veneer_offset.to_int64()
    if encode_aarch64_bl_imm26(pc, veneer_pc) is Some(encoded) {
      patch_aarch64_call_veneer_target(exec_ptr, fixup, target_ptr)
      c_jit_write_u32(pc, encoded)
      return
    }
  }
  abort(
    "direct call target out of range (func_idx=\{fixup.func_idx}, veneer_offset=\{fixup.veneer_offset})",
  )
}

///|
pub fn patch_x64_direct_call(
  exec_ptr : Int64,
  fixup : @cwasm.CallFixup,
  target_ptr : Int64,
) -> Unit {
  let pc = exec_ptr + fixup.offset.to_int64()
  match encode_x64_call_rel32_disp(pc, target_ptr) {
    Some(encoded) => c_jit_write_u32(pc + 1L, encoded)
    None =>
      abort(
        "direct call target out of rel32 range (func_idx=\{fixup.func_idx})",
      )
  }
}

///|
pub fn patch_aarch64_call_fixups(
  exec_ptr : Int64,
  fixups : Array[@cwasm.CallFixup],
  func_table_ptr : Int64,
  direct_call_targets : Map[Int, Int64],
) -> Unit {
  for fixup in fixups {
    let target_ptr = match
      resolve_call_fixup_target(
        fixup.func_idx,
        func_table_ptr,
        direct_call_targets,
      ) {
      Some(ptr) => ptr
      None => abort("missing direct-call target for idx \{fixup.func_idx}")
    }
    patch_aarch64_direct_call(exec_ptr, fixup, target_ptr)
  }
}

///|
pub fn patch_x64_call_fixups(
  exec_ptr : Int64,
  fixups : Array[@cwasm.CallFixup],
  func_table_ptr : Int64,
  direct_call_targets : Map[Int, Int64],
) -> Unit {
  for fixup in fixups {
    let target_ptr = match
      resolve_call_fixup_target(
        fixup.func_idx,
        func_table_ptr,
        direct_call_targets,
      ) {
      Some(ptr) => ptr
      None => abort("missing direct-call target for idx \{fixup.func_idx}")
    }
    patch_x64_direct_call(exec_ptr, fixup, target_ptr)
  }
}

///|
pub fn patch_call_fixups_for_target(
  target : @cwasm.TargetArch,
  exec_ptr : Int64,
  fixups : Array[@cwasm.CallFixup],
  func_table_ptr : Int64,
  direct_call_targets : Map[Int, Int64],
) -> Unit {
  match target {
    AArch64 =>
      patch_aarch64_call_fixups(
        exec_ptr, fixups, func_table_ptr, direct_call_targets,
      )
    X86_64 =>
      patch_x64_call_fixups(
        exec_ptr, fixups, func_table_ptr, direct_call_targets,
      )
    Unknown =>
      if fixups.length() > 0 {
        abort("cannot patch call fixups for unknown cwasm target")
      }
  }
}

///|
/// GC-managed executable code block wrapper.
struct ExecCode(@jit_ffi.ExecCode)

///|
/// Allocate and copy code to executable memory (GC-managed).
pub fn ExecCode::new(code : Array[Int]) -> ExecCode? {
  let size = code.length()
  if size == 0 {
    return None
  }
  let bytes = FixedArray::make(size, b'\x00')
  for i, b in code {
    bytes[i] = b.to_byte()
  }
  let ec = @jit_ffi.c_jit_alloc_exec_managed(bytes, size)
  if @jit_ffi.c_jit_exec_code_ptr(ec) != 0L {
    Some(ExecCode(ec))
  } else {
    None
  }
}

///|
/// Get the function pointer from this executable code.
pub fn ExecCode::ptr(self : ExecCode) -> Int64 {
  @jit_ffi.c_jit_exec_code_ptr(self.0)
}
