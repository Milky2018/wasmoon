///|
/// JIT runtime FFI for executable memory management and code execution
/// These functions call C functions defined in ffi_jit.c

// ============ Trap Handling ============

///|
/// Get trap code (0 = no trap, 1 = out of bounds memory access, 9 = out of memory, 10 = gc precise roots unavailable)
extern "c" fn c_jit_get_trap_code() -> Int = "wasmoon_jit_get_trap_code"

///|
/// Clear trap code
extern "c" fn c_jit_clear_trap() -> Unit = "wasmoon_jit_clear_trap"

///|
/// Get last trap signal number (e.g. SIGSEGV/SIGBUS/SIGTRAP), or 0 if none
extern "c" fn c_jit_get_trap_signal() -> Int = "wasmoon_jit_get_trap_signal"

///|
/// Get last trap PC (instruction address), or 0 if unavailable
extern "c" fn c_jit_get_trap_pc() -> Int64 = "wasmoon_jit_get_trap_pc"

///|
/// Get last trap LR (return address), or 0 if unavailable
extern "c" fn c_jit_get_trap_lr() -> Int64 = "wasmoon_jit_get_trap_lr"

///|
/// Get last trap FP (frame pointer), or 0 if unavailable
extern "c" fn c_jit_get_trap_fp() -> Int64 = "wasmoon_jit_get_trap_fp"

///|
/// Get caller return address from the frame record ([fp + 8]), or 0 if unavailable
extern "c" fn c_jit_get_trap_frame_lr() -> Int64 = "wasmoon_jit_get_trap_frame_lr"

///|
/// Get last trap fault address (SIGSEGV/SIGBUS si_addr), or 0 if N/A
extern "c" fn c_jit_get_trap_fault_addr() -> Int64 = "wasmoon_jit_get_trap_fault_addr"

///|
/// Get BRK immediate decoded for SIGTRAP, or -1 if N/A
extern "c" fn c_jit_get_trap_brk_imm() -> Int = "wasmoon_jit_get_trap_brk_imm"

///|
/// Get best-effort wasm func_idx at trap time, or -1 if unknown
extern "c" fn c_jit_get_trap_func_idx() -> Int = "wasmoon_jit_get_trap_func_idx"

///|
/// Get best-effort captured x-register value at trap time (JIT ABI numbering).
/// Supported indices: 0,1,2,3,6,7,8,9,10,11,15. Others return 0.
extern "c" fn c_jit_get_trap_xreg(idx : Int) -> Int64 = "wasmoon_jit_get_trap_xreg"

// ============ Host Target ============

///|
/// Host target architecture tag: 1=x86_64, 2=aarch64.
extern "c" fn c_jit_host_target_arch() -> Int = "wasmoon_jit_host_target_arch"

// ============ Hostcall Bridge (JIT -> Host) ============

///|
/// Get hostcall function pointer (C calling convention).
extern "c" fn c_jit_get_hostcall_ptr() -> Int64 = "wasmoon_jit_get_hostcall_ptr"

///|
/// Get the cooperative cancellation poll helper pointer.
extern "c" fn c_jit_get_cancel_poll_ptr() -> Int64 = "wasmoon_jit_get_cancel_poll_ptr"

///|
/// Current hostcall func_idx (thread-local).
extern "c" fn c_jit_get_hostcall_func_idx() -> Int = "wasmoon_jit_get_hostcall_func_idx"

///|
/// Current hostcall values_vec pointer (thread-local).
extern "c" fn c_jit_get_hostcall_values_ptr() -> Int64 = "wasmoon_jit_get_hostcall_values_ptr"

///|
/// Current hostcall num_args (thread-local).
extern "c" fn c_jit_get_hostcall_num_args() -> Int = "wasmoon_jit_get_hostcall_num_args"

///|
/// Current hostcall num_results (thread-local).
extern "c" fn c_jit_get_hostcall_num_results() -> Int = "wasmoon_jit_get_hostcall_num_results"

// ============ GC-managed JITContext ============

///|
/// GC-managed JIT context object
/// The context is automatically freed when the object is garbage collected
priv type JITContext

///|
/// Allocate GC-managed JIT context
extern "c" fn c_jit_alloc_context_managed(func_count : Int) -> JITContext = "wasmoon_jit_alloc_context_managed"

///|
/// Copy bytes to linear memory at offset (zero-copy friendly Bytes path).
#borrow(data)
extern "c" fn c_jit_memory_init_bytes(
  mem_ptr : Int64,
  offset : Int64,
  data : Bytes,
  size : Int,
) -> Int = "wasmoon_jit_memory_init_bytes"

///|
/// Copy data from linear memory at offset into `out`
#borrow(out)
extern "c" fn c_jit_memory_read(
  mem_ptr : Int64,
  offset : Int64,
  out : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_memory_read"

///|
/// Allocate linear memory for generic buffers (globals, etc.)
extern "c" fn c_jit_alloc_memory(size : Int64) -> Int64 = "wasmoon_jit_alloc_memory"

///|
/// Allocate a `wasmoon_memory_t` descriptor with an owned backing allocation.
/// max_pages is interpreted by the runtime; -1 means "unknown/unlimited".
extern "c" fn c_jit_alloc_memory_desc(
  size_bytes : Int64,
  max_pages : Int64,
  is_memory64 : Int,
  page_size_log2 : Int,
  is_shared : Int,
) -> MemoryDescriptor = "wasmoon_jit_alloc_memory_desc"

///|
/// Release one descriptor owner; free its backing after the final release.

///|
/// Get current length in bytes from a `wasmoon_memory_t` descriptor.
#borrow(mem_desc_ptr)
extern "c" fn c_mem_desc_get_len(mem_desc_ptr : MemoryDescriptor) -> Int64 = "wasmoon_mem_desc_get_len"

///|
/// Grow a `wasmoon_memory_t` descriptor by `delta_pages`.
/// Returns old size in pages on success, or -1 on failure.
#borrow(mem_desc_ptr)
extern "c" fn c_mem_desc_grow(
  mem_desc_ptr : MemoryDescriptor,
  delta_pages : Int64,
  max_pages : Int,
) -> Int64 = "wasmoon_mem_desc_grow"

///|
/// Copy bytes from memory descriptor at offset into `out`.
#borrow(out, mem_desc_ptr)
extern "c" fn c_mem_desc_read(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  out : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_mem_desc_read"

///|
/// Copy bytes from `data` into memory descriptor at offset.
#borrow(data, mem_desc_ptr)
extern "c" fn c_mem_desc_write(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_mem_desc_write"

///|
/// Copy bytes from `data` into memory descriptor at offset (Bytes fast path).
#borrow(data, mem_desc_ptr)
extern "c" fn c_mem_desc_write_bytes(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  data : Bytes,
  size : Int,
) -> Int = "wasmoon_mem_desc_write_bytes"

///|
/// memmove within the same memory descriptor.
#borrow(mem_desc_ptr)
extern "c" fn c_mem_desc_memmove(
  mem_desc_ptr : MemoryDescriptor,
  dst : Int64,
  src : Int64,
  size : Int,
) -> Int = "wasmoon_mem_desc_memmove"

///|
/// memset within the same memory descriptor.
#borrow(mem_desc_ptr)
extern "c" fn c_mem_desc_memset(
  mem_desc_ptr : MemoryDescriptor,
  dst : Int64,
  val : Int,
  size : Int,
) -> Int = "wasmoon_mem_desc_memset"

///|
/// Allocate guarded memory into a standalone descriptor.
/// Returns: `wasmoon_memory_t*` on success, 0 on failure.
extern "c" fn c_jit_alloc_guarded_memory_desc(
  initial_pages : Int64,
  max_pages : Int64,
  is_shared : Int,
) -> MemoryDescriptor = "wasmoon_jit_alloc_guarded_memory_desc"

///|
/// Free linear memory
extern "c" fn c_jit_free_memory(mem_ptr : Int64) -> Unit = "wasmoon_jit_free_memory"

///|
/// Get table_grow function pointer for JIT
/// Signature: table_grow(ctx: *jit_context_t, table_idx: i32, delta: i64, init_value: i64) -> i64
extern "c" fn c_jit_get_table_grow_ptr() -> Int64 = "wasmoon_jit_get_table_grow_ptr"

// ============ Multi-Memory Operations (with memidx) ============

///|
/// Get memory_grow function pointer for JIT (multi-memory)
/// Signature: memory_grow(ctx: *jit_context_t, memidx: i32, delta: i64, max_pages: i32) -> i64
extern "c" fn c_jit_get_memory_grow_ptr() -> Int64 = "wasmoon_jit_get_memory_grow_ptr"

///|
/// Get memory_size function pointer for JIT (multi-memory)
/// Signature: memory_size(ctx: *jit_context_t, memidx: i32) -> i64
extern "c" fn c_jit_get_memory_size_ptr() -> Int64 = "wasmoon_jit_get_memory_size_ptr"

///|
/// Get memory_fill function pointer for JIT (multi-memory)
/// Signature: memory_fill(ctx: *jit_context_t, memidx: i32, dst: i64, val: i32, size: i64) -> void
extern "c" fn c_jit_get_memory_fill_ptr() -> Int64 = "wasmoon_jit_get_memory_fill_ptr"

///|
/// Get memory_copy function pointer for JIT (multi-memory)
/// Signature: memory_copy(ctx: *jit_context_t, dst_memidx: i32, src_memidx: i32, dst: i64, src: i64, size: i64) -> void
extern "c" fn c_jit_get_memory_copy_ptr() -> Int64 = "wasmoon_jit_get_memory_copy_ptr"

// ============ Integer div/rem helpers (x86_64 bootstrap) ============

///|
/// Get memory_init function pointer for JIT
/// Signature: memory_init(ctx: *jit_context_t, memidx: i32, data_idx: i32, dst: i32, src: i32, size: i32) -> void
extern "c" fn c_jit_get_memory_init_ptr() -> Int64 = "wasmoon_jit_get_memory_init_ptr"

///|
/// Get data_drop function pointer for JIT
/// Signature: data_drop(ctx: *jit_context_t, data_idx: i32) -> void
extern "c" fn c_jit_get_data_drop_ptr() -> Int64 = "wasmoon_jit_get_data_drop_ptr"

///|
/// Get table_fill function pointer for JIT
/// Signature: table_fill(ctx: *jit_context_t, table_idx: i32, dst: i32, val: i64, size: i32) -> void
extern "c" fn c_jit_get_table_fill_ptr() -> Int64 = "wasmoon_jit_get_table_fill_ptr"

///|
/// Get table_copy function pointer for JIT
/// Signature: table_copy(ctx: *jit_context_t, dst_table_idx: i32, src_table_idx: i32, dst: i32, src: i32, size: i32) -> void
extern "c" fn c_jit_get_table_copy_ptr() -> Int64 = "wasmoon_jit_get_table_copy_ptr"

///|
/// Get table_init function pointer for JIT
/// Signature: table_init(ctx: *jit_context_t, table_idx: i32, elem_idx: i32, dst: i32, src: i32, size: i32) -> void
extern "c" fn c_jit_get_table_init_ptr() -> Int64 = "wasmoon_jit_get_table_init_ptr"

///|
/// Get elem_drop function pointer for JIT
/// Signature: elem_drop(ctx: *jit_context_t, elem_idx: i32) -> void
extern "c" fn c_jit_get_elem_drop_ptr() -> Int64 = "wasmoon_jit_get_elem_drop_ptr"

// ============ Shared Indirect Table ============

///|
/// Allocate a shared indirect table that can be used by multiple JIT modules
extern "c" fn c_jit_alloc_shared_indirect_table(
  count : Int,
) -> NativeTableHandle = "wasmoon_jit_alloc_shared_indirect_table"

///|
/// Set an entry in a shared indirect table
#borrow(table_ptr)
extern "c" fn c_jit_shared_table_set(
  table_ptr : NativeTableHandle,
  table_idx : Int,
  func_ptr : Int64,
  type_hash : Int,
) -> Unit = "wasmoon_jit_shared_table_set"

///|
/// C FFI for trampoline-based calls that keeps the GC-managed `JITContext`
/// alive for the duration of the call.
/// This avoids relying on any global "current context" state.
#borrow(jit_context, values_vec)
extern "c" fn c_jit_call_trampoline_managed(
  jit_context : JITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
) -> Int = "wasmoon_jit_call_trampoline_managed"

// ============ Store-Owned Native Fibers ============

///|
priv type NativeFiberObject

///|
#owned(closure)
extern "c" fn c_native_fiber_alloc(
  call_closure : FuncRef[(() -> Int64) -> Int64],
  closure : () -> Int64,
  stack_size : Int64,
) -> NativeFiberObject = "wasmoon_native_fiber_alloc"

///|
#owned(jit_context, values)
extern "c" fn c_native_jit_continuation_alloc(
  jit_context : JITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values : FixedArray[Int64],
  values_len : Int,
  stack_size : Int64,
) -> NativeFiberObject = "wasmoon_native_jit_continuation_alloc"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_continue_code(
  fiber : NativeFiberObject,
  resume_value : Int64,
) -> Int = "wasmoon_native_fiber_continue"

///|
extern "c" fn c_native_fiber_yield(value : Int64) -> Int64 = "wasmoon_native_fiber_yield"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_cancel_code(fiber : NativeFiberObject) -> Int = "wasmoon_native_fiber_cancel"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_state_code(fiber : NativeFiberObject) -> Int = "wasmoon_native_fiber_state"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_yielded_value(fiber : NativeFiberObject) -> Int64 = "wasmoon_native_fiber_yielded_value"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_return_value(fiber : NativeFiberObject) -> Int64 = "wasmoon_native_fiber_return_value"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_stack_size(fiber : NativeFiberObject) -> Int64 = "wasmoon_native_fiber_stack_size"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_guard_size(fiber : NativeFiberObject) -> Int64 = "wasmoon_native_fiber_guard_size"

///|
extern "c" fn c_native_hostcall_suspend_event() -> Int64 = "wasmoon_native_hostcall_suspend_event"

// ============ WASI Trampoline Pointers ============

///|
/// Get spectest print trampoline pointer
extern "c" fn c_jit_get_spectest_print_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_ptr"

///|
/// Get spectest print_i32 trampoline pointer
extern "c" fn c_jit_get_spectest_print_i32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i32_ptr"

///|
/// Get spectest print_i64 trampoline pointer
extern "c" fn c_jit_get_spectest_print_i64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i64_ptr"

///|
/// Get spectest print_f32 trampoline pointer
extern "c" fn c_jit_get_spectest_print_f32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f32_ptr"

///|
/// Get spectest print_f64 trampoline pointer
extern "c" fn c_jit_get_spectest_print_f64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f64_ptr"

///|
/// Get spectest print_i32_f32 trampoline pointer
extern "c" fn c_jit_get_spectest_print_i32_f32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i32_f32_ptr"

///|
/// Get spectest print_f64_f64 trampoline pointer
extern "c" fn c_jit_get_spectest_print_f64_f64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f64_f64_ptr"

///|
/// Get spectest print_char trampoline pointer
extern "c" fn c_jit_get_spectest_print_char_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_char_ptr"

// ============ Bulk Memory Operations ============

///|
/// Write an int64 value to a memory address
extern "c" fn c_jit_write_i64(addr : Int64, value : Int64) -> Unit = "wasmoon_jit_write_i64"

///|
/// Read an int64 value from a memory address
extern "c" fn c_jit_read_i64(addr : Int64) -> Int64 = "wasmoon_jit_read_i64"

// ============ GC Runtime Helpers ============

///|
/// Get ref.test libcall function pointer
extern "c" fn c_jit_get_gc_ref_test_ptr() -> Int64 = "wasmoon_jit_get_gc_ref_test_ptr"

///|
/// Get ref.cast libcall function pointer
extern "c" fn c_jit_get_gc_ref_cast_ptr() -> Int64 = "wasmoon_jit_get_gc_ref_cast_ptr"

///|
/// Get struct.new libcall function pointer
extern "c" fn c_jit_get_gc_struct_new_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_new_ptr"

///|
/// Get struct.get libcall function pointer
extern "c" fn c_jit_get_gc_struct_get_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_get_ptr"

///|
/// Get struct.set libcall function pointer
extern "c" fn c_jit_get_gc_struct_set_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_set_ptr"

///|
/// Get the v128 aggregate libcall function pointers.
///
/// These carry the vector through a caller-owned 16-byte buffer rather than a
/// runtime word, so each takes or returns its value by address.
extern "c" fn c_jit_get_gc_struct_get_v128_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_get_v128_ptr"

///|
extern "c" fn c_jit_get_gc_struct_set_v128_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_set_v128_ptr"

///|
extern "c" fn c_jit_get_gc_array_get_v128_ptr() -> Int64 = "wasmoon_jit_get_gc_array_get_v128_ptr"

///|
extern "c" fn c_jit_get_gc_array_set_v128_ptr() -> Int64 = "wasmoon_jit_get_gc_array_set_v128_ptr"

///|
extern "c" fn c_jit_get_gc_array_fill_v128_ptr() -> Int64 = "wasmoon_jit_get_gc_array_fill_v128_ptr"

///|
extern "c" fn c_jit_get_gc_alloc_struct_wide_slow_ptr() -> Int64 = "wasmoon_jit_get_gc_alloc_struct_wide_slow_ptr"

///|
extern "c" fn c_jit_get_gc_alloc_array_wide_slow_ptr() -> Int64 = "wasmoon_jit_get_gc_alloc_array_wide_slow_ptr"

///|
extern "c" fn c_jit_get_gc_alloc_array_from_slots_slow_ptr() -> Int64 = "wasmoon_jit_get_gc_alloc_array_from_slots_slow_ptr"

///|
/// Get array.new libcall function pointer
extern "c" fn c_jit_get_gc_array_new_ptr() -> Int64 = "wasmoon_jit_get_gc_array_new_ptr"

///|
/// Get array.get libcall function pointer
extern "c" fn c_jit_get_gc_array_get_ptr() -> Int64 = "wasmoon_jit_get_gc_array_get_ptr"

///|
/// Get array.set libcall function pointer
extern "c" fn c_jit_get_gc_array_set_ptr() -> Int64 = "wasmoon_jit_get_gc_array_set_ptr"

///|
/// Get array.len libcall function pointer
extern "c" fn c_jit_get_gc_array_len_ptr() -> Int64 = "wasmoon_jit_get_gc_array_len_ptr"

///|
/// Get array.fill libcall function pointer
/// Signature: void gc_array_fill(int64_t ref, int32_t offset, int64_t value, int32_t count)
extern "c" fn c_jit_get_gc_array_fill_ptr() -> Int64 = "wasmoon_jit_get_gc_array_fill_ptr"

///|
/// Get array.copy libcall function pointer
/// Signature: void gc_array_copy(int64_t dst_ref, int32_t dst_offset, int64_t src_ref, int32_t src_offset, int32_t count)
extern "c" fn c_jit_get_gc_array_copy_ptr() -> Int64 = "wasmoon_jit_get_gc_array_copy_ptr"

///|
/// Get array.new_data libcall function pointer
/// Signature: int64_t gc_array_new_data(ctx, type_idx, data_idx, data_offset, length) -> arrayref
extern "c" fn c_jit_get_gc_array_new_data_ptr() -> Int64 = "wasmoon_jit_get_gc_array_new_data_ptr"

///|
/// Get array.new_elem libcall function pointer
/// Signature: int64_t gc_array_new_elem(ctx, type_idx, elem_idx, elem_offset, length) -> arrayref
extern "c" fn c_jit_get_gc_array_new_elem_ptr() -> Int64 = "wasmoon_jit_get_gc_array_new_elem_ptr"

///|
/// Get array.init_data libcall function pointer
/// Signature: void gc_array_init_data(ctx, type_idx, data_idx, arrayref, arr_offset, data_offset, length)
extern "c" fn c_jit_get_gc_array_init_data_ptr() -> Int64 = "wasmoon_jit_get_gc_array_init_data_ptr"

///|
/// Get array.init_elem libcall function pointer
/// Signature: void gc_array_init_elem(ctx, type_idx, elem_idx, arrayref, arr_offset, elem_offset, length)
extern "c" fn c_jit_get_gc_array_init_elem_ptr() -> Int64 = "wasmoon_jit_get_gc_array_init_elem_ptr"

///|
/// Get type check subtype libcall function pointer for call_indirect with subtyping
/// Signature: void gc_type_check_subtype(int32_t actual_type, int32_t expected_type)
/// Traps if actual_type is not a subtype of expected_type
extern "c" fn c_jit_get_gc_type_check_subtype_ptr() -> Int64 = "wasmoon_jit_get_gc_type_check_subtype_ptr"

///|
/// Get gc_register_struct_inline function pointer for inline allocation
/// Signature: int64_t gc_register_struct_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size)
extern "c" fn c_jit_get_gc_register_struct_inline_ptr() -> Int64 = "wasmoon_jit_get_gc_register_struct_inline_ptr"

///|
/// Get gc_register_array_inline function pointer for inline allocation
/// Signature: int64_t gc_register_array_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size)
extern "c" fn c_jit_get_gc_register_array_inline_ptr() -> Int64 = "wasmoon_jit_get_gc_register_array_inline_ptr"

///|
/// Get gc_alloc_struct_slow function pointer for slow path
/// Signature: int64_t gc_alloc_struct_slow(jit_context_t *ctx, int32_t type_idx, int64_t *fields, int32_t num_fields, int32_t safepoint_id)
extern "c" fn c_jit_get_gc_alloc_struct_slow_ptr() -> Int64 = "wasmoon_jit_get_gc_alloc_struct_slow_ptr"

///|
/// Get gc_alloc_array_slow function pointer for slow path
/// Signature: int64_t gc_alloc_array_slow(jit_context_t *ctx, int32_t type_idx, int32_t len, int64_t init_value, int32_t safepoint_id)
extern "c" fn c_jit_get_gc_alloc_array_slow_ptr() -> Int64 = "wasmoon_jit_get_gc_alloc_array_slow_ptr"

///|
/// Get gc_alloc_array_from_values_slow function pointer for fixed-array slow path
/// Signature: int64_t gc_alloc_array_from_values_slow(jit_context_t *ctx, int32_t type_idx, int64_t *values, int32_t len, int32_t safepoint_id)
extern "c" fn c_jit_get_gc_alloc_array_from_values_slow_ptr() -> Int64 = "wasmoon_jit_get_gc_alloc_array_from_values_slow_ptr"

///|
/// Get the copied caller-root scope push helper.
/// Signature: void push(jit_context_t *ctx, int64_t *roots, int32_t root_count)
/// Traps if the runtime cannot copy the roots.
extern "c" fn c_jit_get_gc_push_root_scope_ptr() -> Int64 = "wasmoon_jit_get_gc_push_root_scope_ptr"

///|
/// Get the copied caller-root scope pop helper.
/// Signature: void pop(jit_context_t *ctx)
/// Traps if no matching scope exists.
extern "c" fn c_jit_get_gc_pop_root_scope_ptr() -> Int64 = "wasmoon_jit_get_gc_pop_root_scope_ptr"

///|
/// Clear the GC heap while keeping the managed context alive for the C call.
#borrow(jit_context)
extern "c" fn c_jit_gc_clear_heap_managed(jit_context : JITContext) -> Unit = "wasmoon_jit_gc_clear_heap_managed"

// ============ C GC Heap ============

///|
/// Create a new GC heap with the given initial capacity
/// Returns a C-owned heap handle
extern "c" fn c_gc_heap_new(capacity : Int64) -> GCHeapHandle = "wasmoon_gc_heap_new"

// ============ Struct Operations ============

///|
/// Allocate a new struct
/// Returns gc_ref (1-based index), or 0 on failure
///
/// `fields` is a flat run of [lo, hi] word pairs, two entries per field. The
/// narrow `wasmoon_gc_heap_alloc_struct` next to it in C is for JIT-emitted
/// code, which only ever produces runtime words; MoonBit always goes wide so
/// that a v128 field never has to be squeezed into one word.
#borrow(fields, heap)
extern "c" fn c_gc_heap_alloc_struct_wide(
  heap : GCHeapHandle,
  type_idx : Int,
  fields : FixedArray[Int64],
  num_fields : Int,
) -> Int = "wasmoon_gc_heap_alloc_struct_wide"

///|
/// Read a struct field into `out` as [lo, hi]
#borrow(out, heap)
extern "c" fn c_gc_heap_struct_get_wide(
  heap : GCHeapHandle,
  gc_ref : Int,
  field_idx : Int,
  out : FixedArray[Int64],
) -> Unit = "wasmoon_gc_heap_struct_get_wide"

///|
/// Set a struct field value
#borrow(heap)
extern "c" fn c_gc_heap_struct_set_wide(
  heap : GCHeapHandle,
  gc_ref : Int,
  field_idx : Int,
  lo : Int64,
  hi : Int64,
) -> Unit = "wasmoon_gc_heap_struct_set_wide"

// ============ Array Operations ============

///|
/// Allocate a new array
/// Returns gc_ref (1-based index), or 0 on failure
#borrow(heap)
extern "c" fn c_gc_heap_alloc_array_wide(
  heap : GCHeapHandle,
  type_idx : Int,
  len : Int,
  lo : Int64,
  hi : Int64,
) -> Int = "wasmoon_gc_heap_alloc_array_wide"

///|
/// Allocate a new array from existing values
/// Returns gc_ref (1-based index), or 0 on failure
///
/// `values` is a flat run of [lo, hi] word pairs, two entries per element.
#borrow(values, heap)
extern "c" fn c_gc_heap_alloc_array_from_slots(
  heap : GCHeapHandle,
  type_idx : Int,
  values : FixedArray[Int64],
  len : Int,
) -> Int = "wasmoon_gc_heap_alloc_array_from_slots"

///|
/// Get array length
#borrow(heap)
extern "c" fn c_gc_heap_array_len(heap : GCHeapHandle, gc_ref : Int) -> Int = "wasmoon_gc_heap_array_len"

///|
/// Read an array element into `out` as [lo, hi]
#borrow(out, heap)
extern "c" fn c_gc_heap_array_get_wide(
  heap : GCHeapHandle,
  gc_ref : Int,
  idx : Int,
  out : FixedArray[Int64],
) -> Unit = "wasmoon_gc_heap_array_get_wide"

///|
/// Set an array element
#borrow(heap)
extern "c" fn c_gc_heap_array_set_wide(
  heap : GCHeapHandle,
  gc_ref : Int,
  idx : Int,
  lo : Int64,
  hi : Int64,
) -> Unit = "wasmoon_gc_heap_array_set_wide"

///|
/// Fill array elements with a value
#borrow(heap)
extern "c" fn c_gc_heap_array_fill_wide(
  heap : GCHeapHandle,
  gc_ref : Int,
  offset : Int,
  lo : Int64,
  hi : Int64,
  count : Int,
) -> Unit = "wasmoon_gc_heap_array_fill_wide"

///|
/// Copy array elements
#borrow(heap)
extern "c" fn c_gc_heap_array_copy(
  heap : GCHeapHandle,
  dst_ref : Int,
  dst_offset : Int,
  src_ref : Int,
  src_offset : Int,
  count : Int,
) -> Unit = "wasmoon_gc_heap_array_copy"

// ============ Type Information ============

///|
/// Get the type index of an object
#borrow(heap)
extern "c" fn c_gc_heap_get_type_idx(heap : GCHeapHandle, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_type_idx"

///|
/// Get the kind of an object (1=struct, 2=array)
#borrow(heap)
extern "c" fn c_gc_heap_get_kind(heap : GCHeapHandle, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_kind"

///|
/// Check if a gc_ref is valid (non-null and within bounds)
#borrow(heap)
extern "c" fn c_gc_heap_is_valid(heap : GCHeapHandle, gc_ref : Int) -> Int = "wasmoon_gc_heap_is_valid"

// ============ GC Operations ============

///|
/// Perform a full GC cycle (mark + sweep)
/// Returns number of objects collected
#borrow(roots, heap)
extern "c" fn c_gc_heap_collect(
  heap : GCHeapHandle,
  roots : FixedArray[Int64],
  num_roots : Int,
) -> Int = "wasmoon_jit_collect_heap"

///|
/// Discard unreachable objects allocated after the supplied object-table boundary.
#borrow(roots, heap)
extern "c" fn c_gc_heap_rollback_allocations(
  heap : GCHeapHandle,
  object_count : Int,
  roots : FixedArray[Int64],
  num_roots : Int,
) -> Int = "wasmoon_gc_heap_rollback_allocations"

///|
/// Verify C heap invariants (returns 1 when valid, 0 on failure)
#borrow(heap)
extern "c" fn c_gc_heap_verify(heap : GCHeapHandle, verbose : Int) -> Int = "wasmoon_gc_heap_verify"

///|
/// Configure allocation fault injection:
/// - fail_at > 0: fail exactly on Nth allocation attempt
/// - fail_every > 0: fail on every Kth allocation attempt
extern "c" fn c_gc_heap_debug_set_fail_alloc(
  fail_at : Int,
  fail_every : Int,
) -> Unit = "wasmoon_gc_heap_debug_set_fail_alloc"

// ============ JIT Utilities ============

///|
/// Get heap base pointer (for JIT inline access)
#borrow(heap)
extern "c" fn c_gc_heap_get_base(heap : GCHeapHandle) -> Int64 = "wasmoon_gc_heap_get_base"

///|
/// Get object offset in heap (for JIT inline access)
#borrow(heap)
extern "c" fn c_gc_heap_get_offset(heap : GCHeapHandle, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_offset"

///|
/// Get current heap size (bytes used)
#borrow(heap)
extern "c" fn c_gc_heap_get_size(heap : GCHeapHandle) -> Int64 = "wasmoon_gc_heap_get_size"

///|
/// Get heap capacity (total allocated bytes)
#borrow(heap)
extern "c" fn c_gc_heap_get_capacity(heap : GCHeapHandle) -> Int64 = "wasmoon_gc_heap_get_capacity"

///|
/// Get number of objects in heap
#borrow(heap)
extern "c" fn c_gc_heap_get_object_count(heap : GCHeapHandle) -> Int = "wasmoon_gc_heap_get_object_count"

///|
/// Get total number of write-barrier calls recorded
#borrow(heap)
extern "c" fn c_gc_heap_get_barrier_writes(heap : GCHeapHandle) -> Int = "wasmoon_gc_heap_get_barrier_writes"

///|
/// Get total number of allocations since heap creation
#borrow(heap)
extern "c" fn c_gc_heap_get_total_allocations(heap : GCHeapHandle) -> Int = "wasmoon_gc_heap_get_total_allocations"

///|
/// Get total number of GC cycles performed
#borrow(heap)
extern "c" fn c_gc_heap_get_total_collections(heap : GCHeapHandle) -> Int = "wasmoon_gc_heap_get_total_collections"

// ============ Exception Handling ============

///|
/// Get exception try_begin function pointer for JIT
/// Signature: try_begin(ctx: *jit_context_t, handler_id: i32) -> *sigjmp_buf
extern "c" fn c_jit_get_exception_try_begin_ptr() -> Int64 = "wasmoon_jit_get_exception_try_begin_ptr"

///|
/// Get exception try_end function pointer for JIT
/// Signature: try_end(ctx: *jit_context_t, handler_id: i32)
extern "c" fn c_jit_get_exception_try_end_ptr() -> Int64 = "wasmoon_jit_get_exception_try_end_ptr"

///|
/// Get exception throw function pointer for JIT
/// Signature: throw(ctx: *jit_context_t, tag_addr: i32, values_ptr: i64, count: i32) -> noreturn
extern "c" fn c_jit_get_exception_throw_ptr() -> Int64 = "wasmoon_jit_get_exception_throw_ptr"

///|
/// Get exception throw_tag function pointer for JIT
/// Signature: throw_tag(ctx: *jit_context_t, tag_addr: i32) -> noreturn
extern "c" fn c_jit_get_exception_throw_tag_ptr() -> Int64 = "wasmoon_jit_get_exception_throw_tag_ptr"

///|
/// Get exception throw_ref function pointer for JIT
/// Signature: throw_ref(ctx: *jit_context_t, exnref: i64) -> noreturn
extern "c" fn c_jit_get_exception_throw_ref_ptr() -> Int64 = "wasmoon_jit_get_exception_throw_ref_ptr"

///|
/// Get exception delegate function pointer for JIT
/// Signature: delegate(ctx: *jit_context_t, depth: i32) -> noreturn
extern "c" fn c_jit_get_exception_delegate_ptr() -> Int64 = "wasmoon_jit_get_exception_delegate_ptr"

///|
/// Get exception get_tag function pointer for JIT
/// Signature: get_tag(ctx: *jit_context_t) -> i32
extern "c" fn c_jit_get_exception_get_tag_ptr() -> Int64 = "wasmoon_jit_get_exception_get_tag_ptr"

///|
/// Get exception get_value function pointer for JIT
/// Signature: get_value(ctx: *jit_context_t, idx: i32) -> i64
extern "c" fn c_jit_get_exception_get_value_ptr() -> Int64 = "wasmoon_jit_get_exception_get_value_ptr"

///|
/// Get exception get_value_count function pointer for JIT
/// Signature: get_value_count(ctx: *jit_context_t) -> i32
extern "c" fn c_jit_get_exception_get_value_count_ptr() -> Int64 = "wasmoon_jit_get_exception_get_value_count_ptr"

///|
/// Get sigsetjmp function pointer for JIT to call directly
/// Signature: sigsetjmp(jmp_buf, savemask: i32) -> i32
/// Returns 0 on first call, handler_id on longjmp return
extern "c" fn c_jit_get_sigsetjmp_ptr() -> Int64 = "wasmoon_jit_get_sigsetjmp_ptr"

///|
/// Get exception spill_locals function pointer for JIT
/// Signature: spill_locals(ctx: *jit_context_t, locals: *i64, count: i32) -> void
/// Saves locals before throw so catch handlers see throw-time values
extern "c" fn c_jit_get_exception_spill_locals_ptr() -> Int64 = "wasmoon_jit_get_exception_spill_locals_ptr"

///|
/// Get exception get_spilled_local function pointer for JIT
/// Signature: get_spilled_local(ctx: *jit_context_t, idx: i32) -> i64
/// Gets a spilled local value for catch handlers
extern "c" fn c_jit_get_exception_get_spilled_local_ptr() -> Int64 = "wasmoon_jit_get_exception_get_spilled_local_ptr"

// ============ DWARF Debug Info ============

///|
/// Create a new DWARF debug info builder
/// Returns an opaque handle to pass to other DWARF functions
extern "c" fn c_dwarf_create() -> DWARFBuilder = "wasmoon_dwarf_create"

///|
/// Add a function to the DWARF debug info
/// Parameters:
///   dwarf: Handle from c_dwarf_create()
///   name: Function name (null-terminated bytes)
///   addr: Function start address
///   size: Function size in bytes
///   func_idx: WebAssembly function index
#borrow(dwarf, name)
extern "c" fn c_dwarf_add_function(
  dwarf : DWARFBuilder,
  name : Bytes,
  addr : Int64,
  size : Int,
  func_idx : Int,
) -> Unit = "wasmoon_dwarf_add_function"

///|
/// Register the DWARF debug info with the debugger (LLDB/GDB)
/// This generates an in-memory Mach-O/ELF object and registers it
/// via the GDB JIT interface
/// verbose: if true, print debug info to stderr
#borrow(dwarf)
extern "c" fn c_dwarf_register(dwarf : DWARFBuilder, verbose : Int) -> Unit = "wasmoon_dwarf_register"

///|
/// Unregister DWARF debug info from the debugger
#borrow(dwarf)
extern "c" fn c_dwarf_unregister(dwarf : DWARFBuilder) -> Unit = "wasmoon_dwarf_unregister"

///|
/// Destroy the DWARF builder and free resources
/// Also unregisters debug info if registered
#borrow(dwarf)
extern "c" fn c_dwarf_destroy(dwarf : DWARFBuilder) -> Unit = "wasmoon_dwarf_destroy"

///|
/// Set the active DWARF builder for address lookups
/// This is used for backtrace symbolication
#borrow(dwarf)
extern "c" fn c_dwarf_set_active(dwarf : DWARFBuilder) -> Unit = "wasmoon_dwarf_set_active"

///|
/// Lookup an address in the DWARF debug info
/// Returns 1 if found, 0 if not found
/// If found, writes results to the provided arrays
#borrow(dwarf, name_out, func_idx_out, offset_out)
extern "c" fn c_dwarf_lookup_address(
  dwarf : DWARFBuilder,
  addr : Int64,
  name_out : FixedArray[Byte],
  name_size : Int,
  func_idx_out : FixedArray[Int],
  offset_out : FixedArray[Int64],
) -> Int = "wasmoon_dwarf_lookup_address"

///|
/// Capture a backtrace with LR fallback (for when FP is 0)
/// Returns the number of frames captured
/// frames_out contains alternating (pc, fp) pairs
#borrow(frames_out)
extern "c" fn c_dwarf_capture_backtrace_ex(
  initial_pc : Int64,
  initial_fp : Int64,
  initial_lr : Int64,
  frames_out : FixedArray[Int64],
  max_frames : Int,
) -> Int = "wasmoon_dwarf_capture_backtrace_ex"

// ============ Managed JITContext Operations ============

///|
#borrow(jit_context)
extern "c" fn c_jit_context_is_valid(jit_context : JITContext) -> Int = "wasmoon_jit_context_is_valid"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_set_func_managed(
  jit_context : JITContext,
  idx : Int,
  func_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_func_managed"

///|
#borrow(jit_context, mem0_ptr)
extern "c" fn c_jit_ctx_set_memory_managed(
  jit_context : JITContext,
  mem0_ptr : MemoryDescriptor,
) -> Unit = "wasmoon_jit_ctx_set_memory_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_set_globals_managed(
  jit_context : JITContext,
  globals_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_globals_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_func_table_managed(
  jit_context : JITContext,
) -> Int64 = "wasmoon_jit_ctx_get_func_table_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_func_count_managed(jit_context : JITContext) -> Int = "wasmoon_jit_ctx_get_func_count_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_table_ptr_managed(
  jit_context : JITContext,
  table_idx : Int,
) -> NativeTableHandle = "wasmoon_jit_ctx_get_table_ptr_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_table_size_managed(
  jit_context : JITContext,
  table_idx : Int,
) -> Int = "wasmoon_jit_ctx_get_table_size_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_alloc_indirect_table_managed(
  jit_context : JITContext,
  count : Int,
) -> Int = "wasmoon_jit_ctx_alloc_indirect_table_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_set_indirect_managed(
  jit_context : JITContext,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit = "wasmoon_jit_ctx_set_indirect_managed"

///|
#borrow(jit_context, memory_ptrs)
extern "c" fn c_jit_ctx_set_memory_pointers_managed(
  jit_context : JITContext,
  memory_ptrs : FixedArray[MemoryDescriptor],
  memory_count : Int,
) -> Unit = "wasmoon_jit_ctx_set_memory_pointers_managed"

///|
#borrow(jit_context, table_ptrs, table_sizes, table_max_sizes)
extern "c" fn c_jit_ctx_set_table_pointers_managed(
  jit_context : JITContext,
  table_ptrs : FixedArray[NativeTableHandle],
  table_sizes : FixedArray[Int],
  table_max_sizes : FixedArray[Int64],
  table_count : Int,
) -> Unit = "wasmoon_jit_ctx_set_table_pointers_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_alloc_guarded_memory_managed(
  jit_context : JITContext,
  initial_pages : Int64,
  max_pages : Int64,
) -> MemoryDescriptor = "wasmoon_jit_ctx_alloc_guarded_memory_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_memory_ptr_managed(
  jit_context : JITContext,
  memidx : Int,
) -> Int64 = "wasmoon_jit_ctx_get_memory_ptr_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_memory_size_managed(
  jit_context : JITContext,
  memidx : Int,
) -> Int64 = "wasmoon_jit_ctx_get_memory_size_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_exception_throw_tag_managed(
  jit_context : JITContext,
  tag_addr : Int,
) -> Unit = "wasmoon_jit_exception_throw_tag_managed"

///|
#borrow(jit_context, values)
extern "c" fn c_jit_exception_throw_values_managed(
  jit_context : JITContext,
  tag_addr : Int,
  values : FixedArray[Int64],
  count : Int,
) -> Unit = "wasmoon_jit_exception_throw_values_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_init_data_segments_managed(
  jit_context : JITContext,
  count : Int,
) -> Unit = "wasmoon_jit_ctx_init_data_segments_managed"

///|
#borrow(jit_context, data)
extern "c" fn c_jit_ctx_add_data_segment_managed(
  jit_context : JITContext,
  idx : Int,
  data : FixedArray[Byte],
  size : Int,
  dropped : Int,
) -> Unit = "wasmoon_jit_ctx_add_data_segment_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_init_elem_segments_managed(
  jit_context : JITContext,
  count : Int,
) -> Unit = "wasmoon_jit_ctx_init_elem_segments_managed"

///|
#borrow(jit_context, data)
extern "c" fn c_jit_ctx_add_elem_segment_managed(
  jit_context : JITContext,
  idx : Int,
  data : FixedArray[Int64],
  size : Int,
  dropped : Int,
) -> Unit = "wasmoon_jit_ctx_add_elem_segment_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_clear_segments_managed(
  jit_context : JITContext,
) -> Unit = "wasmoon_jit_ctx_clear_segments_managed"

///|
#borrow(jit_context)
#owned(closure)
extern "c" fn c_jit_set_hostcall_callback_managed(
  jit_context : JITContext,
  call_closure : FuncRef[(() -> Int) -> Int],
  closure : () -> Int,
) -> Unit = "wasmoon_jit_set_hostcall_callback_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_clear_hostcall_callback_managed(
  jit_context : JITContext,
) -> Unit = "wasmoon_jit_clear_hostcall_callback_managed"

///|
#borrow(jit_context)
#owned(closure)
extern "c" fn c_jit_set_cancellation_callback_managed(
  jit_context : JITContext,
  call_closure : FuncRef[(() -> Bool) -> Int],
  closure : () -> Bool,
) -> Unit = "wasmoon_jit_set_cancellation_callback_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_clear_cancellation_callback_managed(
  jit_context : JITContext,
) -> Unit = "wasmoon_jit_clear_cancellation_callback_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_environment_is_clear_managed(
  jit_context : JITContext,
) -> Int = "wasmoon_jit_gc_environment_is_clear_managed"

///|
#borrow(jit_context, types_data)
extern "c" fn c_jit_gc_set_type_cache_managed(
  jit_context : JITContext,
  types_data : FixedArray[Int],
  num_types : Int,
) -> Unit = "wasmoon_jit_gc_set_type_cache_managed"

///|
#borrow(jit_context, canonical)
extern "c" fn c_jit_gc_set_canonical_indices_managed(
  jit_context : JITContext,
  canonical : FixedArray[Int],
  num_types : Int,
) -> Unit = "wasmoon_jit_gc_set_canonical_indices_managed"

///|
#borrow(jit_context, func_type_indices)
extern "c" fn c_jit_gc_set_func_type_indices_managed(
  jit_context : JITContext,
  func_type_indices : FixedArray[Int],
  num_funcs : Int,
) -> Unit = "wasmoon_jit_gc_set_func_type_indices_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_set_func_table_managed(
  jit_context : JITContext,
  func_table_ptr : Int64,
  num_funcs : Int,
) -> Unit = "wasmoon_jit_gc_set_func_table_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_clear_cache_managed(jit_context : JITContext) -> Unit = "wasmoon_jit_gc_clear_cache_managed"

///|
#borrow(jit_context, heap_ptr)
extern "c" fn c_jit_gc_set_heap_managed(
  jit_context : JITContext,
  heap_ptr : GCHeapHandle,
) -> Unit = "wasmoon_jit_gc_set_heap_managed"

///|
#borrow(jit_context, heap_ptr)
extern "c" fn c_jit_ctx_set_gc_heap_managed(
  jit_context : JITContext,
  heap_ptr : GCHeapHandle,
) -> Unit = "wasmoon_jit_ctx_set_gc_heap_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_begin_frame_managed(
  jit_context : JITContext,
  frame_id : Int64,
) -> Unit = "wasmoon_jit_gc_begin_frame_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_end_frame_managed(jit_context : JITContext) -> Unit = "wasmoon_jit_gc_end_frame_managed"

///|
#borrow(jit_context, roots)
extern "c" fn c_jit_gc_collect_for_alloc_managed(
  jit_context : JITContext,
  roots : FixedArray[Int64],
  root_count : Int,
) -> Int = "wasmoon_jit_gc_collect_for_alloc_managed"

///|
#borrow(jit_context, roots)
extern "c" fn c_jit_gc_set_root_scratch_managed(
  jit_context : JITContext,
  roots : FixedArray[Int64],
  root_count : Int,
) -> Int = "wasmoon_jit_gc_set_root_scratch_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_set_safepoint_table_managed(
  jit_context : JITContext,
  table_ptr : Int64,
) -> Unit = "wasmoon_jit_gc_set_safepoint_table_managed"

///|
#borrow(jit_context, stackmap_blob, code_offsets)
extern "c" fn c_jit_gc_set_func_safepoints_managed(
  jit_context : JITContext,
  func_idx : Int,
  stackmap_blob : Bytes,
  stackmap_blob_size : Int,
  code_offsets : FixedArray[Int],
  safepoint_count : Int,
) -> Int = "wasmoon_jit_gc_set_func_safepoints_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_use_func_safepoints_managed(
  jit_context : JITContext,
  func_idx : Int,
) -> Unit = "wasmoon_jit_gc_use_func_safepoints_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_get_wasi_exit_code_managed(jit_context : JITContext) -> Int = "wasmoon_jit_get_wasi_exit_code_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_clear_wasi_exit_managed(jit_context : JITContext) -> Unit = "wasmoon_jit_clear_wasi_exit_managed"

///|
extern "c" fn c_jit_get_exception_get_ref_ptr() -> Int64 = "wasmoon_jit_get_exception_get_ref_ptr"

///|
#borrow(jit_context)
extern "c" fn c_jit_set_wasi_exit_code_managed(
  jit_context : JITContext,
  code : Int,
) -> Unit = "wasmoon_jit_set_wasi_exit_code_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_memory_descriptor_managed(
  jit_context : JITContext,
  memidx : Int,
) -> MemoryDescriptor = "wasmoon_jit_ctx_get_memory_descriptor_managed"
