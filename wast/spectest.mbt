// Spectest module - Standard test module for WebAssembly test suite

///|
/// Create the spectest module with standard test functions
pub fn create_spectest_module(
  store : @runtime.Store,
) -> @runtime.ModuleInstance {
  // Allocate host functions with correct types
  // print_i32: (i32) -> ()
  let print_i32_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let print_i32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i32_type,
  )
  // print_i64: (i64) -> ()
  let print_i64_type : @types.FuncType = {
    params: [@types.ValueType::I64],
    results: [],
  }
  let print_i64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i64_type,
  )
  // print_f32: (f32) -> ()
  let print_f32_type : @types.FuncType = {
    params: [@types.ValueType::F32],
    results: [],
  }
  let print_f32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f32_type,
  )
  // print_f64: (f64) -> ()
  let print_f64_type : @types.FuncType = {
    params: [@types.ValueType::F64],
    results: [],
  }
  let print_f64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f64_type,
  )
  // print_i32_f32: (i32, f32) -> ()
  let print_i32_f32_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::F32],
    results: [],
  }
  let print_i32_f32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i32_f32_type,
  )
  // print_f64_f64: (f64, f64) -> ()
  let print_f64_f64_type : @types.FuncType = {
    params: [@types.ValueType::F64, @types.ValueType::F64],
    results: [],
  }
  let print_f64_f64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f64_f64_type,
  )
  // print: () -> ()
  let print_type : @types.FuncType = { params: [], results: [] }
  let print_addr = store.alloc_host_func(fn(_args) { [] }, func_type=print_type)

  // print_char: (i32) -> () - prints character to stdout
  let print_char_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let print_char_addr = store.alloc_host_func(
    fn(args) {
      match args[0] {
        @types.Value::I32(c) => @wasi.putchar(c)
        _ => ()
      }
      []
    },
    func_type=print_char_type,
  )

  // Allocate memory: (memory 1 2) - min 1 page, max 2 pages
  let memory = @runtime.Memory::new(1, Some(2))
  let memory_addr = store.alloc_mem(memory)

  // Allocate table: (table 10 20 funcref)
  let table = @runtime.Table::new(@types.ValueType::FuncRef, 10, Some(20))
  let table_addr = store.alloc_table(table)

  // Allocate table64: (table i64 10 20 funcref)
  let table64 = @runtime.Table::new(
    @types.ValueType::FuncRef,
    10,
    Some(20),
    is_table64=true,
  )
  let table64_addr = store.alloc_table(table64)

  // Allocate globals
  // global_i32: (global i32 (i32.const 666))
  let global_i32_addr = store.alloc_global(
    @runtime.GlobalInstance::new(
      @types.GlobalType::{ value_type: @types.ValueType::I32, mutable: false },
      @types.Value::I32(666),
    ),
  )
  // global_i64: (global i64 (i64.const 666))
  let global_i64_addr = store.alloc_global(
    @runtime.GlobalInstance::new(
      @types.GlobalType::{ value_type: @types.ValueType::I64, mutable: false },
      @types.Value::I64(666L),
    ),
  )
  // global_f32: (global f32 (f32.const 666))
  let global_f32_addr = store.alloc_global(
    @runtime.GlobalInstance::new(
      @types.GlobalType::{ value_type: @types.ValueType::F32, mutable: false },
      @types.Value::F32(666.6),
    ),
  )
  // global_f64: (global f64 (f64.const 666))
  let global_f64_addr = store.alloc_global(
    @runtime.GlobalInstance::new(
      @types.GlobalType::{ value_type: @types.ValueType::F64, mutable: false },
      @types.Value::F64(666.6),
    ),
  )

  // Create exports
  let exports : Array[@types.Export] = [
    { name: "print_i32", desc: @types.ExportDesc::Func(0) },
    { name: "print_i64", desc: @types.ExportDesc::Func(1) },
    { name: "print_f32", desc: @types.ExportDesc::Func(2) },
    { name: "print_f64", desc: @types.ExportDesc::Func(3) },
    { name: "print_i32_f32", desc: @types.ExportDesc::Func(4) },
    { name: "print_f64_f64", desc: @types.ExportDesc::Func(5) },
    { name: "print", desc: @types.ExportDesc::Func(6) },
    { name: "print_char", desc: @types.ExportDesc::Func(7) },
    { name: "memory", desc: @types.ExportDesc::Memory(0) },
    { name: "table", desc: @types.ExportDesc::Table(0) },
    { name: "table64", desc: @types.ExportDesc::Table(1) },
    { name: "global_i32", desc: @types.ExportDesc::Global(0) },
    { name: "global_i64", desc: @types.ExportDesc::Global(1) },
    { name: "global_f32", desc: @types.ExportDesc::Global(2) },
    { name: "global_f64", desc: @types.ExportDesc::Global(3) },
  ]
  @runtime.ModuleInstance::{
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
