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
test "lower locals through native linear fast path" {
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
test "lower globals through native VMContext loads and stores" {
  let mod_ = {
    ..@types.Module::simple(
      [I32],
      [I32],
      [LocalGet(0), GlobalSet(0), GlobalGet(0)],
      "global_roundtrip",
    ),
    globals: [
      { type_: { value_type: I32, mutable: true }, init: [I32Const(0)] },
    ],
  }
  let env = EmbeddingEnvironment::new()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("load_ptr.i64"), content="true")
  inspect(text.contains("store_ptr.i32"), content="true")
  inspect(text.contains("load_ptr.i32"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower table size and get through native VMContext loads" {
  let table : @types.Table = {
    type_: {
      elem_type: FuncRef,
      limits: { min: 2, max: None },
      is_table64: false,
    },
    init: None,
  }
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32, I64],
      [TableSize(0), I32Const(0), TableGet(0)],
      "table_probe",
    ),
    tables: [table],
  }
  let env = EmbeddingEnvironment::new()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("load_ptr.i64"), content="true")
  inspect(text.contains("ireduce"), content="true")
  inspect(text.contains("trap \"table out of bounds\""), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower table set through native table fill custom shape" {
  let table : @types.Table = {
    type_: {
      elem_type: FuncRef,
      limits: { min: 2, max: None },
      is_table64: false,
    },
    init: None,
  }
  let mod_ = {
    ..@types.Module::simple(
      [I64],
      [],
      [I32Const(0), LocalGet(0), TableSet(0)],
      "table_set",
    ),
    tables: [table],
  }
  let env = EmbeddingEnvironment::new()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("wasmoon.TableFill"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower linear explicit return without legacy bridge" {
  let mod_ = @types.Module::simple(
    [I64, I64],
    [I64],
    [LocalGet(0), LocalGet(1), I64Add, Return],
    "add64",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("iadd"), content="true")
  inspect(text.contains("return"), content="true")
  inspect(func.verify(), content="()")
}

///|
test "lower linear float arithmetic and drop without legacy bridge" {
  let mod_ = @types.Module::simple(
    [F64],
    [F64],
    [F64Const(99.0), Drop, LocalGet(0), F64Const(0.5), F64Sub],
    "adjust",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("fsub"), content="true")
  inspect(func.verify(), content="()")
}

///|
test "lower linear integer bitops comparisons and select natively" {
  let mod_ = @types.Module::simple(
    [I32, I32],
    [I32],
    [
      LocalGet(0),
      I32Const(3),
      I32And,
      LocalTee(2),
      LocalGet(1),
      I32Const(1),
      I32Shl,
      LocalGet(2),
      I32Const(0),
      I32Eq,
      Select,
    ],
    "bit_select",
  )
  let body : Array[@types.Instruction] = [
    LocalGet(0),
    I32Const(3),
    I32And,
    LocalTee(2),
    LocalGet(1),
    I32Const(1),
    I32Shl,
    LocalGet(2),
    I32Const(0),
    I32Eq,
    Select,
  ]
  let mod_ = { ..mod_, codes: [{ locals: [I32], body }] }
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("band"), content="true")
  inspect(text.contains("ishl"), content="true")
  inspect(text.contains("icmp.eq"), content="true")
  inspect(text.contains("select"), content="true")
  inspect(func.verify(), content="()")
}

///|
test "lower linear float compare and unary ops natively" {
  let mod_ = @types.Module::simple(
    [F64],
    [I32],
    [LocalGet(0), F64Neg, F64Abs, F64Ceil, F64Const(1.0), F64Ge],
    "float_cmp",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fneg"), content="true")
  inspect(text.contains("fabs"), content="true")
  inspect(text.contains("fceil"), content="true")
  inspect(text.contains("fcmp.ge"), content="true")
  inspect(func.verify(), content="()")
}

///|
test "lower linear integer extensions and reduction natively" {
  let mod_ = @types.Module::simple(
    [I64],
    [I32],
    [LocalGet(0), I32WrapI64, I32Extend8S],
    "extend_i32",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("ireduce"), content="true")
  inspect(text.contains("sextend8"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower linear i64 extensions natively" {
  let mod_ = @types.Module::simple(
    [I32],
    [I64],
    [LocalGet(0), I64ExtendI32U, I64Extend32S],
    "extend_i64",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("uextend"), content="true")
  inspect(text.contains("sextend32"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower linear float promotion and demotion natively" {
  let mod_ = @types.Module::simple(
    [F64],
    [F32],
    [LocalGet(0), F32DemoteF64, F64PromoteF32, F32DemoteF64],
    "float_resize",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fdemote"), content="true")
  inspect(text.contains("fpromote"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower linear numeric conversions natively" {
  let mod_ = @types.Module::simple(
    [F64, I64],
    [F32],
    [LocalGet(0), I32TruncF64S, Drop, LocalGet(1), F32ConvertI64U],
    "numeric_convert",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fcvt_to_sint"), content="true")
  inspect(text.contains("uint_to_fcvt"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower linear saturating conversion and reinterpret natively" {
  let mod_ = @types.Module::simple(
    [F32, I64],
    [F64],
    [LocalGet(0), I32TruncSatF32U, Drop, LocalGet(1), F64ReinterpretI64],
    "sat_bitcast",
  )
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fcvt_to_uint_sat"), content="true")
  inspect(text.contains("bitcast"), content="true")
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
test "lower memory grow size and bulk helpers as native custom ops" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32, I32],
      [
        MemorySize(0),
        I32Const(1),
        MemoryGrow(0),
        I32Const(0),
        I32Const(255),
        I32Const(8),
        MemoryFill(0),
        I32Const(0),
        I32Const(4),
        I32Const(8),
        MemoryCopy(0, 0),
        I32Const(0),
        I32Const(0),
        I32Const(8),
        MemoryInit(0, 0),
        DataDrop(0),
      ],
      "memory_bulk",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let env = EmbeddingEnvironment::new()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("wasmoon.MemorySize"), content="true")
  inspect(text.contains("wasmoon.MemoryGrow"), content="true")
  inspect(text.contains("wasmoon.MemoryFill"), content="true")
  inspect(text.contains("wasmoon.MemoryCopy"), content="true")
  inspect(text.contains("wasmoon.MemoryInit"), content="true")
  inspect(text.contains("wasmoon.DataDrop"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "lower table bulk helpers as native custom ops" {
  let table : @types.Table = {
    type_: {
      elem_type: FuncRef,
      limits: { min: 2, max: None },
      is_table64: false,
    },
    init: None,
  }
  let mod_ = {
    ..@types.Module::simple(
      [I64],
      [],
      [
        LocalGet(0),
        I32Const(1),
        TableGrow(0),
        Drop,
        I32Const(0),
        LocalGet(0),
        I32Const(1),
        TableFill(0),
        I32Const(0),
        I32Const(1),
        I32Const(1),
        TableCopy(0, 0),
        I32Const(0),
        I32Const(0),
        I32Const(1),
        TableInit(0, 0),
        ElemDrop(0),
      ],
      "table_bulk",
    ),
    tables: [table],
  }
  let env = EmbeddingEnvironment::new()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("wasmoon.TableGrow"), content="true")
  inspect(text.contains("wasmoon.TableFill"), content="true")
  inspect(text.contains("wasmoon.TableCopy"), content="true")
  inspect(text.contains("wasmoon.TableInit"), content="true")
  inspect(text.contains("wasmoon.ElemDrop"), content="true")
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
