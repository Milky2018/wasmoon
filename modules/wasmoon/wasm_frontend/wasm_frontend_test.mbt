///|
test "lower empty wasm function through embedding environment" {
  let mod_ = @types.Module::simple([], [], [], "run")
  let env = EmbeddingEnvironment::new()
  let func = lower_function(env, mod_, 0)
  inspect(func.name, content="wasm_func_0")
  inspect(func.signature.params.length(), content="1")
  inspect(func.signature.results.length(), content="0")
  inspect(func.blocks.length(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "lower simple wasm body into MilkIR operations" {
  let mod_ = @types.Module::simple(
    [I32, I32],
    [I32],
    [LocalGet(0), LocalGet(1), I32Add],
    "run",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  inspect(func.signature.params.length(), content="2")
  inspect(func.signature.results.length(), content="1")
  inspect(func.blocks[0].instructions.length(), content="1")
  inspect(func.print().contains("iadd"), content="true")
  inspect(func.print().contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower locals through production translator bridge" {
  let body : Array[@types.Instruction] = [
    LocalGet(0),
    LocalGet(1),
    I32Add,
    LocalSet(2),
    LocalGet(2),
    I32Const(2),
    I32Mul,
  ]
  let mod_ = {
    ..@types.Module::simple([I32, I32], [I32], body, "double_sum"),
    codes: [{ locals: [I32], body }],
  }
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("iadd"), content="true")
  inspect(text.contains("imul"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower control flow into MilkIR blocks and terminators" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), If(Value(I32), [I32Const(111)], [I32Const(222)])],
    "select_const",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length() > 1, content="true")
  inspect(text.contains("br"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower trap without wasm_frontend skeleton fallback" {
  let mod_ = @types.Module::simple([], [], [Unreachable], "trap")
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("unreachable"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower direct calls as generic MilkIR calls" {
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let main_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(3), I32Const(4), Call(0)],
  }
  let add_type : @types.FuncType = { params: [I32, I32], results: [I32] }
  let main_type : @types.FuncType = { params: [], results: [I32] }
  let mod_ : @types.Module = {
    types: [
      @types.SubType::from_func(add_type),
      @types.SubType::from_func(main_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "main", desc: Func(1) }],
    start: None,
    elems: [],
    codes: [add_func, main_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 1)
  let text = func.print()
  inspect(text.contains("call wasm.func.0"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower memory operations through Wasmoon-owned adapter opcodes" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [
        I32Const(0),
        I32Const(42),
        I32Store(0, 2, 0),
        I32Const(0),
        I32Load(0, 2, 0),
      ],
      "memory_roundtrip",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let env = EmbeddingEnvironment::new()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("wasmoon.LoadMemBase"), content="true")
  inspect(text.contains("load_ptr.i32"), content="true")
  inspect(text.contains("store_ptr.i32"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower rejects missing wasm function" {
  let mod_ = @types.Module::empty()
  let env = EmbeddingEnvironment::new()
  try lower_function(env, mod_, 0) catch {
    err => inspect(err, content="FunctionIndexOutOfRange(index=0)")
  } noraise {
    _ => fail("expected missing wasm function")
  }
}
