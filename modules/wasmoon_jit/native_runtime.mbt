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
