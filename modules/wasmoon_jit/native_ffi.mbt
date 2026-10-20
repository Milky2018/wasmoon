///|
/// JIT runtime FFI for executable memory management and code execution
/// These functions call C functions defined in ffi_jit.c

// ============ Trap Handling ============

///|
/// Get trap code (0 = no trap, 1 = out of bounds memory access, 9 = out of memory, 10 = gc precise roots unavailable)
extern "c" fn c_jit_get_trap_code() -> Int32 = "wasmoon_jit_get_trap_code"

///|
/// Clear trap code
extern "c" fn c_jit_clear_trap() -> Unit = "wasmoon_jit_clear_trap"

///|
/// Get last trap signal number (e.g. SIGSEGV/SIGBUS/SIGTRAP), or 0 if none
extern "c" fn c_jit_get_trap_signal() -> Int32 = "wasmoon_jit_get_trap_signal"

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
extern "c" fn c_jit_get_trap_brk_imm() -> Int32 = "wasmoon_jit_get_trap_brk_imm"

///|
/// Get best-effort wasm func_idx at trap time, or -1 if unknown
extern "c" fn c_jit_get_trap_func_idx() -> Int32 = "wasmoon_jit_get_trap_func_idx"

///|
/// Get best-effort captured x-register value at trap time (JIT ABI numbering).
/// Supported indices: 0,1,2,3,6,7,8,9,10,11,15. Others return 0.
extern "c" fn c_jit_get_trap_xreg(idx : Int32) -> Int64 = "wasmoon_jit_get_trap_xreg"

// ============ Host Target ============

///|
/// Host target architecture tag: 1=x86_64, 2=aarch64.
extern "c" fn c_jit_host_target_arch() -> Int32 = "wasmoon_jit_host_target_arch"

// ============ Hostcall Bridge (JIT -> Host) ============

///|
/// Get hostcall function pointer (C calling convention).
extern "c" fn c_jit_get_hostcall_ptr() -> Int64 = "wasmoon_jit_get_hostcall_ptr"

///|
/// Get the cooperative cancellation poll helper pointer.
extern "c" fn c_jit_get_cancel_poll_ptr() -> Int64 = "wasmoon_jit_get_cancel_poll_ptr"

///|
/// Current hostcall func_idx (thread-local).
extern "c" fn c_jit_get_hostcall_func_idx() -> Int32 = "wasmoon_jit_get_hostcall_func_idx"

///|
/// Current hostcall values_vec pointer (thread-local).
extern "c" fn c_jit_get_hostcall_values_ptr() -> Int64 = "wasmoon_jit_get_hostcall_values_ptr"

///|
/// Current hostcall num_args (thread-local).
extern "c" fn c_jit_get_hostcall_num_args() -> Int32 = "wasmoon_jit_get_hostcall_num_args"

///|
/// Current hostcall num_results (thread-local).
extern "c" fn c_jit_get_hostcall_num_results() -> Int32 = "wasmoon_jit_get_hostcall_num_results"

// ============ GC-managed JITContext ============

///|
using @jit_ffi {type JITContext}

///|
/// Release one descriptor owner; free its backing after the final release.

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
/// C FFI for trampoline-based calls that keeps the GC-managed `JITContext`
/// alive for the duration of the call.
/// This avoids relying on any global "current context" state.
#borrow(jit_context, values_vec)
extern "c" fn c_jit_call_trampoline_managed(
  jit_context : JITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int32,
) -> Int32 = "wasmoon_jit_call_trampoline_managed"

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
  values_len : Int32,
  stack_size : Int64,
) -> NativeFiberObject = "wasmoon_native_jit_continuation_alloc"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_continue_code(
  fiber : NativeFiberObject,
  resume_value : Int64,
) -> Int32 = "wasmoon_native_fiber_continue"

///|
extern "c" fn c_native_fiber_yield(value : Int64) -> Int64 = "wasmoon_native_fiber_yield"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_cancel_code(fiber : NativeFiberObject) -> Int32 = "wasmoon_native_fiber_cancel"

///|
#borrow(fiber)
extern "c" fn c_native_fiber_state_code(fiber : NativeFiberObject) -> Int32 = "wasmoon_native_fiber_state"

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

// ============ Struct Operations ============

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
  size : Int32,
  func_idx : Int32,
) -> Unit = "wasmoon_dwarf_add_function"

///|
/// Register the DWARF debug info with the debugger (LLDB/GDB)
/// This generates an in-memory Mach-O/ELF object and registers it
/// via the GDB JIT interface
/// verbose: if true, print debug info to stderr
#borrow(dwarf)
extern "c" fn c_dwarf_register(dwarf : DWARFBuilder, verbose : Int32) -> Bool = "wasmoon_dwarf_register"

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
  name_size : Int32,
  func_idx_out : FixedArray[Int32],
  offset_out : FixedArray[Int64],
) -> Int32 = "wasmoon_dwarf_lookup_address"

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
  max_frames : Int32,
) -> Int32 = "wasmoon_dwarf_capture_backtrace_ex"

// ============ Managed JITContext Operations ============

///|
#borrow(jit_context)
extern "c" fn c_jit_context_is_valid(jit_context : JITContext) -> Int32 = "wasmoon_jit_context_is_valid"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_set_func_managed(
  jit_context : JITContext,
  idx : Int32,
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
extern "c" fn c_jit_ctx_get_func_count_managed(
  jit_context : JITContext,
) -> Int32 = "wasmoon_jit_ctx_get_func_count_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_table_ptr_managed(
  jit_context : JITContext,
  table_idx : Int32,
) -> NativeTableHandle = "wasmoon_jit_ctx_get_table_ptr_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_table_size_managed(
  jit_context : JITContext,
  table_idx : Int32,
) -> Int32 = "wasmoon_jit_ctx_get_table_size_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_alloc_indirect_table_managed(
  jit_context : JITContext,
  count : Int32,
) -> Int32 = "wasmoon_jit_ctx_alloc_indirect_table_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_set_indirect_managed(
  jit_context : JITContext,
  table_idx : Int32,
  func_idx : Int32,
  type_idx : Int32,
) -> Unit = "wasmoon_jit_ctx_set_indirect_managed"

///|
#borrow(jit_context, memory_ptrs)
extern "c" fn c_jit_ctx_set_memory_pointers_managed(
  jit_context : JITContext,
  memory_ptrs : FixedArray[MemoryDescriptor],
  memory_count : Int32,
) -> Int32 = "wasmoon_jit_ctx_set_memory_pointers_managed"

///|
#borrow(jit_context, table_ptrs, table_sizes, table_max_sizes)
extern "c" fn c_jit_ctx_set_table_pointers_managed(
  jit_context : JITContext,
  table_ptrs : FixedArray[NativeTableHandle],
  table_sizes : FixedArray[Int32],
  table_max_sizes : FixedArray[Int64],
  table_count : Int32,
) -> Int32 = "wasmoon_jit_ctx_set_table_pointers_managed"

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
  memidx : Int32,
) -> Int64 = "wasmoon_jit_ctx_get_memory_ptr_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_memory_size_managed(
  jit_context : JITContext,
  memidx : Int32,
) -> Int64 = "wasmoon_jit_ctx_get_memory_size_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_exception_throw_tag_managed(
  jit_context : JITContext,
  tag_addr : Int32,
) -> Int32 = "wasmoon_jit_exception_throw_tag_managed"

///|
#borrow(jit_context, values)
extern "c" fn c_jit_exception_throw_values_managed(
  jit_context : JITContext,
  tag_addr : Int32,
  values : FixedArray[Int64],
  count : Int32,
) -> Int32 = "wasmoon_jit_exception_throw_values_managed"

///|
#borrow(jit_context, values)
extern "c" fn c_jit_exception_throw_store_values_managed(
  jit_context : JITContext,
  tag_addr : Int32,
  values : FixedArray[Int64],
  count : Int32,
) -> Int32 = "wasmoon_jit_exception_throw_store_values_managed"

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
  call_closure : FuncRef[(() -> Int32) -> Int32],
  closure : () -> Int32,
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
  call_closure : FuncRef[(() -> Bool) -> Int32],
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
) -> Int32 = "wasmoon_jit_gc_environment_is_clear_managed"

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
) -> Bool = "wasmoon_jit_gc_begin_frame_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_end_frame_managed(jit_context : JITContext) -> Unit = "wasmoon_jit_gc_end_frame_managed"

///|
#borrow(jit_context, roots)
extern "c" fn c_jit_gc_collect_for_alloc_managed(
  jit_context : JITContext,
  roots : FixedArray[Int64],
  root_count : Int32,
) -> Int32 = "wasmoon_jit_gc_collect_for_alloc_managed"

///|
#borrow(jit_context, roots)
extern "c" fn c_jit_gc_set_root_scratch_managed(
  jit_context : JITContext,
  roots : FixedArray[Int64],
  root_count : Int32,
) -> Int32 = "wasmoon_jit_gc_set_root_scratch_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_set_safepoint_table_managed(
  jit_context : JITContext,
  table_ptr : Int64,
) -> Unit = "wasmoon_jit_gc_set_safepoint_table_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_gc_use_func_safepoints_managed(
  jit_context : JITContext,
  func_idx : Int32,
) -> Unit = "wasmoon_jit_gc_use_func_safepoints_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_get_wasi_exit_code_managed(
  jit_context : JITContext,
) -> Int32 = "wasmoon_jit_get_wasi_exit_code_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_clear_wasi_exit_managed(jit_context : JITContext) -> Unit = "wasmoon_jit_clear_wasi_exit_managed"

///|
extern "c" fn c_jit_get_exception_get_ref_ptr() -> Int64 = "wasmoon_jit_get_exception_get_ref_ptr"

///|
#borrow(jit_context)
extern "c" fn c_jit_set_wasi_exit_code_managed(
  jit_context : JITContext,
  code : Int32,
) -> Unit = "wasmoon_jit_set_wasi_exit_code_managed"

///|
#borrow(jit_context)
extern "c" fn c_jit_ctx_get_memory_descriptor_managed(
  jit_context : JITContext,
  memidx : Int32,
) -> MemoryDescriptor = "wasmoon_jit_ctx_get_memory_descriptor_managed"
