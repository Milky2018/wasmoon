///|
/// JIT runtime FFI for executable memory management and code execution
/// These functions call C functions defined in ffi_jit.c

// ============ Trap Handling ============

///|
/// Get trap code (0 = no trap, 1 = out of bounds memory access)
pub extern "c" fn c_jit_get_trap_code() -> Int = "wasmoon_jit_get_trap_code"

///|
/// Clear trap code
pub extern "c" fn c_jit_clear_trap() -> Unit = "wasmoon_jit_clear_trap"

// ============ GC-managed JITContext ============

///|
/// GC-managed JIT context object
/// The context is automatically freed when the object is garbage collected
pub type JITContext

///|
/// Allocate GC-managed JIT context
pub extern "c" fn c_jit_alloc_context_managed(func_count : Int) -> JITContext = "wasmoon_jit_alloc_context_managed"

///|
/// Get the context pointer from a GC-managed JITContext object
#borrow(jit_context)
pub extern "c" fn c_jit_context_ptr(jit_context : JITContext) -> Int64 = "wasmoon_jit_context_ptr"

///|
/// Set a function pointer in the context's function table
pub extern "c" fn c_jit_ctx_set_func(
  ctx_ptr : Int64,
  idx : Int,
  func_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_func"

///|
/// Copy data to linear memory at offset
#borrow(data)
pub extern "c" fn c_jit_memory_init(
  mem_ptr : Int64,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_memory_init"

///|
/// Set memory in the context
pub extern "c" fn c_jit_ctx_set_memory(
  ctx_ptr : Int64,
  mem_ptr : Int64,
  mem_size : Int64,
) -> Unit = "wasmoon_jit_ctx_set_memory"

///|
/// Allocate linear memory for WASM
pub extern "c" fn c_jit_alloc_memory(size : Int64) -> Int64 = "wasmoon_jit_alloc_memory"

///|
/// Free linear memory
pub extern "c" fn c_jit_free_memory(mem_ptr : Int64) -> Unit = "wasmoon_jit_free_memory"

///|
/// Get memory_grow v3 function pointer for JIT (ctx-passing)
pub extern "c" fn c_jit_get_memory_grow_ptr_v3() -> Int64 = "wasmoon_jit_get_memory_grow_ptr_v3"

///|
/// Get memory_size v3 function pointer for JIT (ctx-passing, returns pages)
pub extern "c" fn c_jit_get_memory_size_ptr_v3() -> Int64 = "wasmoon_jit_get_memory_size_ptr_v3"

///|
/// Get memory_fill v3 function pointer for JIT (ctx-passing)
pub extern "c" fn c_jit_get_memory_fill_ptr_v3() -> Int64 = "wasmoon_jit_get_memory_fill_ptr_v3"

///|
/// Get memory_copy v3 function pointer for JIT (ctx-passing)
pub extern "c" fn c_jit_get_memory_copy_ptr_v3() -> Int64 = "wasmoon_jit_get_memory_copy_ptr_v3"

///|
/// Get table_grow v3 function pointer for JIT (ctx-passing)
/// Signature: table_grow(ctx: *jit_context_t, table_idx: i32, delta: i64, init_value: i64) -> i32
pub extern "c" fn c_jit_get_table_grow_ptr_v3() -> Int64 = "wasmoon_jit_get_table_grow_ptr_v3"

// ============ Multi-Memory v4 Operations (with memidx) ============

///|
/// Get memory_grow v4 function pointer for JIT (multi-memory)
/// Signature: memory_grow(ctx: *jit_context_t, memidx: i32, delta: i32, max_pages: i32) -> i32
pub extern "c" fn c_jit_get_memory_grow_ptr_v4() -> Int64 = "wasmoon_jit_get_memory_grow_ptr_v4"

///|
/// Get memory_size v4 function pointer for JIT (multi-memory)
/// Signature: memory_size(ctx: *jit_context_t, memidx: i32) -> i32
pub extern "c" fn c_jit_get_memory_size_ptr_v4() -> Int64 = "wasmoon_jit_get_memory_size_ptr_v4"

///|
/// Get memory_fill v4 function pointer for JIT (multi-memory)
/// Signature: memory_fill(ctx: *jit_context_t, memidx: i32, dst: i32, val: i32, size: i32) -> void
pub extern "c" fn c_jit_get_memory_fill_ptr_v4() -> Int64 = "wasmoon_jit_get_memory_fill_ptr_v4"

///|
/// Get memory_copy v4 function pointer for JIT (multi-memory)
/// Signature: memory_copy(ctx: *jit_context_t, dst_memidx: i32, src_memidx: i32, dst: i32, src: i32, size: i32) -> void
pub extern "c" fn c_jit_get_memory_copy_ptr_v4() -> Int64 = "wasmoon_jit_get_memory_copy_ptr_v4"

///|
/// Configure JIT context with multiple memories (for multi-memory support)
/// memory_ptrs: FixedArray of Int64 (memory base pointers)
/// memory_sizes: FixedArray of Int64 (memory sizes in bytes)
/// memory_max_sizes: FixedArray of Int (max sizes in pages, -1 = unlimited)
/// memory_count: Number of memories
#borrow(memory_ptrs, memory_sizes, memory_max_sizes)
pub extern "c" fn c_jit_ctx_set_memory_pointers(
  ctx_ptr : Int64,
  memory_ptrs : FixedArray[Int64],
  memory_sizes : FixedArray[Int64],
  memory_max_sizes : FixedArray[Int],
  memory_count : Int,
) -> Unit = "wasmoon_jit_ctx_set_memory_pointers"

///|
/// Set globals array in the context
pub extern "c" fn c_jit_ctx_set_globals(
  ctx_ptr : Int64,
  globals_ptr : Int64,
) -> Unit = "wasmoon_jit_ctx_set_globals"

///|
/// Get function table base address from context
pub extern "c" fn c_jit_ctx_get_func_table(ctx_ptr : Int64) -> Int64 = "wasmoon_jit_ctx_get_func_table"

///|
/// Get function count from context
pub extern "c" fn c_jit_ctx_get_func_count(ctx_ptr : Int64) -> Int = "wasmoon_jit_ctx_get_func_count"

///|
/// Allocate indirect table for context
pub extern "c" fn c_jit_ctx_alloc_indirect_table(
  ctx_ptr : Int64,
  count : Int,
) -> Int = "wasmoon_jit_ctx_alloc_indirect_table"

///|
/// Set an entry in indirect table (table_idx -> func_table[func_idx])
/// type_idx: the type index of the function (for type checking)
pub extern "c" fn c_jit_ctx_set_indirect(
  ctx_ptr : Int64,
  table_idx : Int,
  func_idx : Int,
  type_idx : Int,
) -> Unit = "wasmoon_jit_ctx_set_indirect"

// ============ Shared Indirect Table ============

///|
/// Allocate a shared indirect table that can be used by multiple JIT modules
pub extern "c" fn c_jit_alloc_shared_indirect_table(count : Int) -> Int64 = "wasmoon_jit_alloc_shared_indirect_table"

///|
/// Free a shared indirect table
pub extern "c" fn c_jit_free_shared_indirect_table(table_ptr : Int64) -> Unit = "wasmoon_jit_free_shared_indirect_table"

///|
/// Set an entry in a shared indirect table
pub extern "c" fn c_jit_shared_table_set(
  table_ptr : Int64,
  table_idx : Int,
  func_ptr : Int64,
  type_hash : Int,
) -> Unit = "wasmoon_jit_shared_table_set"

///|
/// Configure a JIT context to use a shared indirect table
pub extern "c" fn c_jit_ctx_use_shared_table(
  ctx_ptr : Int64,
  shared_table_ptr : Int64,
  count : Int,
) -> Unit = "wasmoon_jit_ctx_use_shared_table"

///|
/// Configure JIT context with multiple indirect tables (for multi-table support)
/// table_ptrs: FixedArray of Int64 (table pointers from Store.jit_tables)
/// table_sizes: FixedArray of Int (table sizes for bounds checking)
/// table_max_sizes: FixedArray of Int (max sizes, -1 = unlimited)
/// table_count: Number of tables
#borrow(table_ptrs, table_sizes, table_max_sizes)
pub extern "c" fn c_jit_ctx_set_table_pointers(
  ctx_ptr : Int64,
  table_ptrs : FixedArray[Int64],
  table_sizes : FixedArray[Int],
  table_max_sizes : FixedArray[Int],
  table_count : Int,
) -> Unit = "wasmoon_jit_ctx_set_table_pointers"

///|
/// C FFI for trampoline-based calls (new, simple interface)
/// Uses JIT-generated trampoline that handles all ABI complexity
/// trampoline_ptr: Pointer to JIT-generated entry trampoline
/// ctx_ptr: VMContext pointer
/// func_ptr: Target WASM function pointer
/// values_vec: Array of Int64 for args (in) and results (out)
/// values_len: Total number of slots in values_vec
#borrow(values_vec)
pub extern "c" fn c_jit_call_trampoline(
  trampoline_ptr : Int64,
  ctx_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
) -> Int = "wasmoon_jit_call_trampoline"

///|
/// C FFI for trampoline-based calls that keeps the GC-managed `JITContext`
/// alive for the duration of the call.
/// This avoids relying on any global "current context" state.
#borrow(jit_context, values_vec)
pub extern "c" fn c_jit_call_trampoline_managed(
  jit_context : JITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values_vec : FixedArray[Int64],
  values_len : Int,
) -> Int = "wasmoon_jit_call_trampoline_managed"

// ============ WASI Trampoline Pointers ============

///|
/// Get fd_write trampoline pointer
pub extern "c" fn c_jit_get_fd_write_ptr() -> Int64 = "wasmoon_jit_get_fd_write_ptr"

///|
/// Get proc_exit trampoline pointer
pub extern "c" fn c_jit_get_proc_exit_ptr() -> Int64 = "wasmoon_jit_get_proc_exit_ptr"

///|
/// Get fd_read trampoline pointer
pub extern "c" fn c_jit_get_fd_read_ptr() -> Int64 = "wasmoon_jit_get_fd_read_ptr"

///|
/// Get args_sizes_get trampoline pointer
pub extern "c" fn c_jit_get_args_sizes_get_ptr() -> Int64 = "wasmoon_jit_get_args_sizes_get_ptr"

///|
/// Get args_get trampoline pointer
pub extern "c" fn c_jit_get_args_get_ptr() -> Int64 = "wasmoon_jit_get_args_get_ptr"

///|
/// Get environ_sizes_get trampoline pointer
pub extern "c" fn c_jit_get_environ_sizes_get_ptr() -> Int64 = "wasmoon_jit_get_environ_sizes_get_ptr"

///|
/// Get environ_get trampoline pointer
pub extern "c" fn c_jit_get_environ_get_ptr() -> Int64 = "wasmoon_jit_get_environ_get_ptr"

///|
/// Get clock_time_get trampoline pointer
pub extern "c" fn c_jit_get_clock_time_get_ptr() -> Int64 = "wasmoon_jit_get_clock_time_get_ptr"

///|
/// Get random_get trampoline pointer
pub extern "c" fn c_jit_get_random_get_ptr() -> Int64 = "wasmoon_jit_get_random_get_ptr"

///|
/// Get fd_close trampoline pointer
pub extern "c" fn c_jit_get_fd_close_ptr() -> Int64 = "wasmoon_jit_get_fd_close_ptr"

///|
/// Get fd_fdstat_get trampoline pointer
pub extern "c" fn c_jit_get_fd_fdstat_get_ptr() -> Int64 = "wasmoon_jit_get_fd_fdstat_get_ptr"

///|
/// Get fd_prestat_get trampoline pointer
pub extern "c" fn c_jit_get_fd_prestat_get_ptr() -> Int64 = "wasmoon_jit_get_fd_prestat_get_ptr"

// ============ Spectest Trampolines ============

///|
/// Get spectest print trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_ptr"

///|
/// Get spectest print_i32 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_i32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i32_ptr"

///|
/// Get spectest print_i64 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_i64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i64_ptr"

///|
/// Get spectest print_f32 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_f32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f32_ptr"

///|
/// Get spectest print_f64 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_f64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f64_ptr"

///|
/// Get spectest print_i32_f32 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_i32_f32_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_i32_f32_ptr"

///|
/// Get spectest print_f64_f64 trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_f64_f64_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_f64_f64_ptr"

///|
/// Get spectest print_char trampoline pointer
pub extern "c" fn c_jit_get_spectest_print_char_ptr() -> Int64 = "wasmoon_jit_get_spectest_print_char_ptr"

// ============ Bulk Memory Operations ============

///|
/// memory.fill: Fill memory region with a byte value
/// Parameters: dst (offset), val (byte value), size (count)
/// Traps if out of bounds
pub extern "c" fn c_jit_memory_fill(dst : Int, val : Int, size : Int) -> Unit = "wasmoon_jit_memory_fill"

///|
/// memory.copy: Copy memory region
/// Parameters: dst (dest offset), src (source offset), size (count)
/// Handles overlapping regions correctly
/// Traps if out of bounds
pub extern "c" fn c_jit_memory_copy(dst : Int, src : Int, size : Int) -> Unit = "wasmoon_jit_memory_copy"

// ============ Executable Memory Management ============

///|
/// Allocate executable memory
/// Returns pointer as Int64 (0 on failure)
pub extern "c" fn c_jit_alloc_exec(size : Int) -> Int64 = "wasmoon_jit_alloc_exec"

///|
/// Copy code to executable memory
/// Returns 0 on success, -1 on failure
#borrow(src)
pub extern "c" fn c_jit_copy_code(
  dest : Int64,
  src : FixedArray[Byte],
  size : Int,
) -> Int = "wasmoon_jit_copy_code"

// ============ GC-managed ExecCode ============

///|
/// GC-managed executable code object
/// The memory is automatically freed when the object is garbage collected
pub type ExecCode

///|
/// Allocate GC-managed executable code
/// Returns the allocated ExecCode object
#borrow(code)
pub extern "c" fn c_jit_alloc_exec_managed(
  code : FixedArray[Byte],
  size : Int,
) -> ExecCode = "wasmoon_jit_alloc_exec_managed"

///|
/// Get the function pointer from a GC-managed ExecCode object
#owned(exec_code)
pub extern "c" fn c_jit_exec_code_ptr(exec_code : ExecCode) -> Int64 = "wasmoon_jit_exec_code_ptr"

// ============ Multi-value Return Support ============

///|
/// C FFI for multi-value return calls
/// result_types uses: 0=I32, 1=I64, 2=F32, 3=F64
#borrow(args, results, result_types)
pub extern "c" fn c_jit_call_multi_return(
  func_ptr : Int64,
  func_table_ptr : Int64,
  args : FixedArray[Int64],
  num_args : Int,
  results : FixedArray[Int64],
  result_types : FixedArray[Int],
  num_results : Int,
) -> Int = "wasmoon_jit_call_multi_return"

///|
/// Write an int64 value to a memory address
pub extern "c" fn c_jit_write_i64(addr : Int64, value : Int64) -> Unit = "wasmoon_jit_write_i64"

///|
/// Read an int64 value from a memory address
pub extern "c" fn c_jit_read_i64(addr : Int64) -> Int64 = "wasmoon_jit_read_i64"

// ============ GC Runtime Helpers ============

///|
/// Get ref.test libcall function pointer
pub extern "c" fn c_jit_get_gc_ref_test_ptr() -> Int64 = "wasmoon_jit_get_gc_ref_test_ptr"

///|
/// Get ref.cast libcall function pointer
pub extern "c" fn c_jit_get_gc_ref_cast_ptr() -> Int64 = "wasmoon_jit_get_gc_ref_cast_ptr"

///|
/// Get struct.new libcall function pointer
pub extern "c" fn c_jit_get_gc_struct_new_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_new_ptr"

///|
/// Get struct.get libcall function pointer
pub extern "c" fn c_jit_get_gc_struct_get_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_get_ptr"

///|
/// Get struct.set libcall function pointer
pub extern "c" fn c_jit_get_gc_struct_set_ptr() -> Int64 = "wasmoon_jit_get_gc_struct_set_ptr"

///|
/// Get array.new libcall function pointer
pub extern "c" fn c_jit_get_gc_array_new_ptr() -> Int64 = "wasmoon_jit_get_gc_array_new_ptr"

///|
/// Get array.get libcall function pointer
pub extern "c" fn c_jit_get_gc_array_get_ptr() -> Int64 = "wasmoon_jit_get_gc_array_get_ptr"

///|
/// Get array.set libcall function pointer
pub extern "c" fn c_jit_get_gc_array_set_ptr() -> Int64 = "wasmoon_jit_get_gc_array_set_ptr"

///|
/// Get array.len libcall function pointer
pub extern "c" fn c_jit_get_gc_array_len_ptr() -> Int64 = "wasmoon_jit_get_gc_array_len_ptr"

///|
/// Get array.fill libcall function pointer
/// Signature: void gc_array_fill(int64_t ref, int32_t offset, int64_t value, int32_t count)
pub extern "c" fn c_jit_get_gc_array_fill_ptr() -> Int64 = "wasmoon_jit_get_gc_array_fill_ptr"

///|
/// Get array.copy libcall function pointer
/// Signature: void gc_array_copy(int64_t dst_ref, int32_t dst_offset, int64_t src_ref, int32_t src_offset, int32_t count)
pub extern "c" fn c_jit_get_gc_array_copy_ptr() -> Int64 = "wasmoon_jit_get_gc_array_copy_ptr"

///|
/// Get type check subtype libcall function pointer for call_indirect with subtyping
/// Signature: void gc_type_check_subtype(int32_t actual_type, int32_t expected_type)
/// Traps if actual_type is not a subtype of expected_type
pub extern "c" fn c_jit_get_gc_type_check_subtype_ptr() -> Int64 = "wasmoon_jit_get_gc_type_check_subtype_ptr"

///|
/// Set type cache for GC operations
/// types_data: array of [super_idx, kind] pairs per type
#borrow(types_data)
pub extern "c" fn c_jit_gc_set_type_cache(
  types_data : FixedArray[Int],
  num_types : Int,
) -> Unit = "wasmoon_jit_gc_set_type_cache"

///|
/// Set canonical type indices for subtyping
#borrow(canonical)
pub extern "c" fn c_jit_gc_set_canonical_indices(
  canonical : FixedArray[Int],
  num_types : Int,
) -> Unit = "wasmoon_jit_gc_set_canonical_indices"

///|
/// Set function type indices for funcref subtyping
#borrow(func_type_indices)
pub extern "c" fn c_jit_gc_set_func_type_indices(
  func_type_indices : FixedArray[Int],
  num_funcs : Int,
) -> Unit = "wasmoon_jit_gc_set_func_type_indices"

///|
/// Set function table pointer for funcref lookup
pub extern "c" fn c_jit_gc_set_func_table(
  func_table_ptr : Int64,
  num_funcs : Int,
) -> Unit = "wasmoon_jit_gc_set_func_table"

///|
/// Clear GC cache after JIT execution
pub extern "c" fn c_jit_gc_clear_cache() -> Unit = "wasmoon_jit_gc_clear_cache"

///|
/// Set GC heap pointer for JIT execution
pub extern "c" fn c_jit_gc_set_heap(heap_ptr : Int64) -> Unit = "wasmoon_jit_gc_set_heap"

///|
/// Clear GC heap pointer after JIT execution
pub extern "c" fn c_jit_gc_clear_heap() -> Unit = "wasmoon_jit_gc_clear_heap"

///|
/// Get current GC heap pointer (for debugging)
pub extern "c" fn c_jit_gc_get_heap() -> Int64 = "wasmoon_jit_gc_get_heap"

// ============ C GC Heap ============

///|
/// Create a new GC heap with the given initial capacity
/// Returns heap pointer as Int64
pub extern "c" fn c_gc_heap_new(capacity : Int64) -> Int64 = "wasmoon_gc_heap_new"

///|
/// Free a GC heap and all its memory
pub extern "c" fn c_gc_heap_free(heap : Int64) -> Unit = "wasmoon_gc_heap_free"

// ============ Struct Operations ============

///|
/// Allocate a new struct
/// Returns gc_ref (1-based index), or 0 on failure
#borrow(fields)
pub extern "c" fn c_gc_heap_alloc_struct(
  heap : Int64,
  type_idx : Int,
  fields : FixedArray[Int64],
  num_fields : Int,
) -> Int = "wasmoon_gc_heap_alloc_struct"

///|
/// Get a struct field value
pub extern "c" fn c_gc_heap_struct_get(
  heap : Int64,
  gc_ref : Int,
  field_idx : Int,
) -> Int64 = "wasmoon_gc_heap_struct_get"

///|
/// Set a struct field value
pub extern "c" fn c_gc_heap_struct_set(
  heap : Int64,
  gc_ref : Int,
  field_idx : Int,
  value : Int64,
) -> Unit = "wasmoon_gc_heap_struct_set"

// ============ Array Operations ============

///|
/// Allocate a new array
/// Returns gc_ref (1-based index), or 0 on failure
pub extern "c" fn c_gc_heap_alloc_array(
  heap : Int64,
  type_idx : Int,
  len : Int,
  init_value : Int64,
) -> Int = "wasmoon_gc_heap_alloc_array"

///|
/// Allocate a new array from existing values
/// Returns gc_ref (1-based index), or 0 on failure
#borrow(values)
pub extern "c" fn c_gc_heap_alloc_array_from_values(
  heap : Int64,
  type_idx : Int,
  values : FixedArray[Int64],
  len : Int,
) -> Int = "wasmoon_gc_heap_alloc_array_from_values"

///|
/// Get array length
pub extern "c" fn c_gc_heap_array_len(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_array_len"

///|
/// Get an array element
pub extern "c" fn c_gc_heap_array_get(
  heap : Int64,
  gc_ref : Int,
  idx : Int,
) -> Int64 = "wasmoon_gc_heap_array_get"

///|
/// Set an array element
pub extern "c" fn c_gc_heap_array_set(
  heap : Int64,
  gc_ref : Int,
  idx : Int,
  value : Int64,
) -> Unit = "wasmoon_gc_heap_array_set"

///|
/// Fill array elements with a value
pub extern "c" fn c_gc_heap_array_fill(
  heap : Int64,
  gc_ref : Int,
  offset : Int,
  value : Int64,
  count : Int,
) -> Unit = "wasmoon_gc_heap_array_fill"

///|
/// Copy array elements
pub extern "c" fn c_gc_heap_array_copy(
  heap : Int64,
  dst_ref : Int,
  dst_offset : Int,
  src_ref : Int,
  src_offset : Int,
  count : Int,
) -> Unit = "wasmoon_gc_heap_array_copy"

// ============ Type Information ============

///|
/// Get the type index of an object
pub extern "c" fn c_gc_heap_get_type_idx(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_type_idx"

///|
/// Get the kind of an object (1=struct, 2=array)
pub extern "c" fn c_gc_heap_get_kind(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_kind"

///|
/// Check if a gc_ref is valid (non-null and within bounds)
pub extern "c" fn c_gc_heap_is_valid(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_is_valid"

// ============ GC Operations ============

///|
/// Mark an object as reachable (for GC)
pub extern "c" fn c_gc_heap_mark(heap : Int64, gc_ref : Int) -> Unit = "wasmoon_gc_heap_mark"

///|
/// Mark all objects reachable from roots
#borrow(roots)
pub extern "c" fn c_gc_heap_mark_roots(
  heap : Int64,
  roots : FixedArray[Int64],
  num_roots : Int,
) -> Unit = "wasmoon_gc_heap_mark_roots"

///|
/// Sweep unmarked objects
/// Returns number of objects collected
pub extern "c" fn c_gc_heap_sweep(heap : Int64) -> Int = "wasmoon_gc_heap_sweep"

///|
/// Perform a full GC cycle (mark + sweep)
/// Returns number of objects collected
#borrow(roots)
pub extern "c" fn c_gc_heap_collect(
  heap : Int64,
  roots : FixedArray[Int64],
  num_roots : Int,
) -> Int = "wasmoon_gc_heap_collect"

// ============ JIT Utilities ============

///|
/// Get heap base pointer (for JIT inline access)
pub extern "c" fn c_gc_heap_get_base(heap : Int64) -> Int64 = "wasmoon_gc_heap_get_base"

///|
/// Get object offset in heap (for JIT inline access)
pub extern "c" fn c_gc_heap_get_offset(heap : Int64, gc_ref : Int) -> Int = "wasmoon_gc_heap_get_offset"

///|
/// Get current heap size (bytes used)
pub extern "c" fn c_gc_heap_get_size(heap : Int64) -> Int64 = "wasmoon_gc_heap_get_size"

///|
/// Get heap capacity (total allocated bytes)
pub extern "c" fn c_gc_heap_get_capacity(heap : Int64) -> Int64 = "wasmoon_gc_heap_get_capacity"

///|
/// Get number of objects in heap
pub extern "c" fn c_gc_heap_get_object_count(heap : Int64) -> Int = "wasmoon_gc_heap_get_object_count"

///|
/// Get total number of allocations since heap creation
pub extern "c" fn c_gc_heap_get_total_allocations(heap : Int64) -> Int = "wasmoon_gc_heap_get_total_allocations"

///|
/// Get total number of GC cycles performed
pub extern "c" fn c_gc_heap_get_total_collections(heap : Int64) -> Int = "wasmoon_gc_heap_get_total_collections"

// ============ Exception Handling ============

///|
/// Get exception try_begin function pointer for JIT
/// Signature: try_begin(ctx: *jit_context_t, handler_id: i32) -> *sigjmp_buf
pub extern "c" fn c_jit_get_exception_try_begin_ptr() -> Int64 = "wasmoon_jit_get_exception_try_begin_ptr"

///|
/// Get exception try_end function pointer for JIT
/// Signature: try_end(ctx: *jit_context_t, handler_id: i32)
pub extern "c" fn c_jit_get_exception_try_end_ptr() -> Int64 = "wasmoon_jit_get_exception_try_end_ptr"

///|
/// Get exception throw function pointer for JIT
/// Signature: throw(ctx: *jit_context_t, tag_addr: i32, values_ptr: i64, count: i32) -> noreturn
pub extern "c" fn c_jit_get_exception_throw_ptr() -> Int64 = "wasmoon_jit_get_exception_throw_ptr"

///|
/// Get exception throw_ref function pointer for JIT
/// Signature: throw_ref(ctx: *jit_context_t, exnref: i64) -> noreturn
pub extern "c" fn c_jit_get_exception_throw_ref_ptr() -> Int64 = "wasmoon_jit_get_exception_throw_ref_ptr"

///|
/// Get exception delegate function pointer for JIT
/// Signature: delegate(ctx: *jit_context_t, depth: i32) -> noreturn
pub extern "c" fn c_jit_get_exception_delegate_ptr() -> Int64 = "wasmoon_jit_get_exception_delegate_ptr"

///|
/// Get exception get_tag function pointer for JIT
/// Signature: get_tag(ctx: *jit_context_t) -> i32
pub extern "c" fn c_jit_get_exception_get_tag_ptr() -> Int64 = "wasmoon_jit_get_exception_get_tag_ptr"

///|
/// Get exception get_value function pointer for JIT
/// Signature: get_value(ctx: *jit_context_t, idx: i32) -> i64
pub extern "c" fn c_jit_get_exception_get_value_ptr() -> Int64 = "wasmoon_jit_get_exception_get_value_ptr"

///|
/// Get exception get_value_count function pointer for JIT
/// Signature: get_value_count(ctx: *jit_context_t) -> i32
pub extern "c" fn c_jit_get_exception_get_value_count_ptr() -> Int64 = "wasmoon_jit_get_exception_get_value_count_ptr"

///|
/// Get sigsetjmp function pointer for JIT to call directly
/// Signature: sigsetjmp(jmp_buf, savemask: i32) -> i32
/// Returns 0 on first call, handler_id on longjmp return
pub extern "c" fn c_jit_get_sigsetjmp_ptr() -> Int64 = "wasmoon_jit_get_sigsetjmp_ptr"

///|
/// Get exception spill_locals function pointer for JIT
/// Signature: spill_locals(ctx: *jit_context_t, locals: *i64, count: i32) -> void
/// Saves locals before throw so catch handlers see throw-time values
pub extern "c" fn c_jit_get_exception_spill_locals_ptr() -> Int64 = "wasmoon_jit_get_exception_spill_locals_ptr"

///|
/// Get exception get_spilled_local function pointer for JIT
/// Signature: get_spilled_local(ctx: *jit_context_t, idx: i32) -> i64
/// Gets a spilled local value for catch handlers
pub extern "c" fn c_jit_get_exception_get_spilled_local_ptr() -> Int64 = "wasmoon_jit_get_exception_get_spilled_local_ptr"
