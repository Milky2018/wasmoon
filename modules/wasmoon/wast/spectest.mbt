// Spectest module - Standard test module for WebAssembly test suite

///|
/// Create the spectest module with standard test functions
pub fn create_spectest_module(
  store : @runtime.Store,
) -> @runtime.ModuleInstance {
  // Allocate host functions with correct types
  // print_i32: (i32) -> ()
  let print_i32_type : @types.FuncType = { params: [I32], results: [] }
  let print_i32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i32_type,
  )
  // print_i64: (i64) -> ()
  let print_i64_type : @types.FuncType = { params: [I64], results: [] }
  let print_i64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i64_type,
  )
  // print_f32: (f32) -> ()
  let print_f32_type : @types.FuncType = { params: [F32], results: [] }
  let print_f32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f32_type,
  )
  // print_f64: (f64) -> ()
  let print_f64_type : @types.FuncType = { params: [F64], results: [] }
  let print_f64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f64_type,
  )
  // print_i32_f32: (i32, f32) -> ()
  let print_i32_f32_type : @types.FuncType = { params: [I32, F32], results: [] }
  let print_i32_f32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i32_f32_type,
  )
  // print_f64_f64: (f64, f64) -> ()
  let print_f64_f64_type : @types.FuncType = { params: [F64, F64], results: [] }
  let print_f64_f64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f64_f64_type,
  )
  // print: () -> ()
  let print_type : @types.FuncType = { params: [], results: [] }
  let print_addr = store.alloc_host_func(fn(_args) { [] }, func_type=print_type)

  // print_char: (i32) -> () - prints character to stdout
  let print_char_type : @types.FuncType = { params: [I32], results: [] }
  let print_char_addr = store.alloc_host_func(
    fn(args) {
      if args[0] is I32(c) {
        @wasi.putchar(c)
      }
      []
    },
    func_type=print_char_type,
  )

  // Allocate memory: (memory 1 2) - min 1 page, max 2 pages
  let memory = @runtime.Memory::Memory(1, Some(2))
  let memory_addr = store.alloc_mem(memory)

  // Allocate table: (table 10 20 funcref)
  let table = @runtime.Table::Table(FuncRef, 10, Some(20))
  let table_addr = store.alloc_table(table)

  // Allocate table64: (table i64 10 20 funcref)
  let table64 = @runtime.Table::Table(FuncRef, 10, Some(20), is_table64=true)
  let table64_addr = store.alloc_table(table64)

  // Allocate globals
  // global_i32: (global i32 (i32.const 666))
  let global_i32_addr = store.alloc_global(
    GlobalInstance({ value_type: I32, mutable: false }, I32(666)),
  )
  // global_i64: (global i64 (i64.const 666))
  let global_i64_addr = store.alloc_global(
    GlobalInstance({ value_type: I64, mutable: false }, I64(666L)),
  )
  // global_f32: (global f32 (f32.const 666))
  let global_f32_addr = store.alloc_global(
    GlobalInstance({ value_type: F32, mutable: false }, F32(666.6)),
  )
  // global_f64: (global f64 (f64.const 666))
  let global_f64_addr = store.alloc_global(
    GlobalInstance({ value_type: F64, mutable: false }, F64(666.6)),
  )

  // Create exports
  let exports : Array[@types.Export] = [
    { name: "print_i32", desc: Func(0) },
    { name: "print_i64", desc: Func(1) },
    { name: "print_f32", desc: Func(2) },
    { name: "print_f64", desc: Func(3) },
    { name: "print_i32_f32", desc: Func(4) },
    { name: "print_f64_f64", desc: Func(5) },
    { name: "print", desc: Func(6) },
    { name: "print_char", desc: Func(7) },
    { name: "memory", desc: Memory(0) },
    { name: "table", desc: Table(0) },
    { name: "table64", desc: Table(1) },
    { name: "global_i32", desc: Global(0) },
    { name: "global_i64", desc: Global(1) },
    { name: "global_f32", desc: Global(2) },
    { name: "global_f64", desc: Global(3) },
  ]
  {
    types: [],
    type_rec_groups: [],
    canonical_type_indices: [],
    store_idx: -1,
    func_addrs: [
      print_i32_addr, print_i64_addr, print_f32_addr, print_f64_addr, print_i32_f32_addr,
      print_f64_f64_addr, print_addr, print_char_addr,
    ],
    func_type_indices: [],
    table_addrs: [table_addr, table64_addr],
    mem_addrs: [memory_addr],
    global_addrs: [
      global_i32_addr, global_i64_addr, global_f32_addr, global_f64_addr,
    ],
    tag_addrs: [],
    exports,
    elem_segments: [],
    data_segments: [],
    dropped_elems: [],
    dropped_datas: [],
  }
}
