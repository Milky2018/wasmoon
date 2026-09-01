///|
fn native_test_env() -> EmbeddingEnvironment {
  EmbeddingEnvironment(
    runtime_symbol_prefix="test",
    runtime_layout=Some({
      memory0_base_offset: 8,
      memory0_size_offset: 16,
      func_table_offset: 24,
      table0_base_offset: 32,
      table0_elements_offset: 40,
      globals_offset: 48,
      tables_offset: 56,
      table_sizes_offset: 72,
      memories_offset: 88,
      pointer_stride: 8,
      global_value_stride: 16,
      table_entry_value_offset: 0,
      table_entry_stride: 16,
      func_table_entry_stride: 8,
    }),
    memory_descriptor_layout=Some({ base_offset: 0, current_length_offset: 8, }),
  )
}

///|
fn frontend_test_env() -> EmbeddingEnvironment {
  EmbeddingEnvironment(runtime_symbol_prefix="test", hidden_context_type=None)
}

///|
test "lower empty wasm function through embedding environment" {
  let mod_ = @types.Module::simple([], [], [], "run")
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  inspect(func.name, content="wasm_func_0")
  inspect(func.signature().params.length(), content="1")
  inspect(func.signature().results.length(), content="0")
  inspect(func.blocks.length(), content="1")
  @wasm_milkir.verify_function(func)
}

///|
test "lower simple wasm body into MilkIR operations" {
  let mod_ = @types.Module::simple(
    [I32, I32],
    [I32],
    [LocalGet(0), LocalGet(1), I32Add],
    "run",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  inspect(func.signature().params.length(), content="2")
  inspect(func.signature().results.length(), content="1")
  inspect(func.blocks[0].instructions.length(), content="2")
  inspect(func.print().contains("iadd"), content="true")
  inspect(func.print().contains("ireduce"), content="true")
  inspect(func.print().contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
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
    codes: [{ locals: [I32], body, }],
  }
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("iadd"), content="true")
  inspect(text.contains("imul"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower nop and float locals through native linear fast path" {
  let body : Array[@types.Instruction] = [Nop, LocalGet(1), LocalGet(0), F64Add]
  let mod_ = {
    ..@types.Module::simple([F64], [F64], body, "float_local_default"),
    codes: [{ locals: [F64], body, }],
  }
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fconst"), content="true")
  inspect(text.contains("fadd"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower branchless blocks through native linear fast path" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [Block(Value(I32), [LocalGet(0), Block(Value(I32), [I32Const(1)]), I32Add])],
    "branchless_block",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("iadd"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower branchless loop through native linear fast path" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [Loop(Value(I32), [LocalGet(0), I32Const(1), I32Add])],
    "branchless_loop",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("iadd"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "try lower native function does not use legacy fallback" {
  let env = frontend_test_env()
  let linear = @types.Module::simple(
    [I32, I32],
    [I32],
    [LocalGet(0), LocalGet(1), I32Add],
    "linear",
  )
  let structured = @types.Module::simple(
    [],
    [],
    [Block(Empty, [Br(0)])],
    "structured_branch",
  )
  let loop_branch = @types.Module::simple(
    [],
    [],
    [Loop(Empty, [Br(0)])],
    "loop_branch",
  )
  inspect(try_lower_native_function(env, linear, 0) is Some(_), content="true")
  inspect(
    try_lower_native_function(env, structured, 0) is Some(_),
    content="true",
  )
  inspect(
    try_lower_native_function(env, loop_branch, 0) is None,
    content="true",
  )
}

///|
test "top-level frontend lowers structured if through production translator" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [I32Const(1), If(Value(I32), [I32Const(7)], [I32Const(9)])],
    "structured_if",
  )
  let func = translate_function(native_test_env(), mod_, 0)
  inspect(func.blocks.length() > 1, content="true")
  @wasm_milkir.verify_function(func)
}

///|
test "return_call terminates the translated MilkIR block" {
  let mod_ = @types.Module::simple([], [], [ReturnCall(0)], "tail_recursive")
  let func = translate_function(native_test_env(), mod_, 0)
  @wasm_milkir.verify_function(func)
}

///|
test "unreachable structured continuations remain verifier-safe" {
  let bodies : Array[Array[@types.Instruction]] = [
    [Block(Empty, [Return]), Unreachable],
    [I32Const(1), If(Empty, [Return], [Return]), Unreachable],
    [Loop(Empty, [Return]), Unreachable],
    [Return, Loop(Empty, [Loop(Empty, [])])],
  ]
  for i, body in bodies {
    let mod_ = @types.Module::simple([], [], body, "unreachable_control_\{i}")
    let func = translate_function(native_test_env(), mod_, 0)
    @wasm_milkir.verify_function(func)
  }
}

///|
test "lower direct block branch through native linear fast path" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [Block(Value(I32), [I32Const(7), Br(0)])],
    "block_exit_branch",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("iconst 7"), content="true")
  inspect(text.contains("iconst 9"), content="false")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "non-terminal block branch falls back to interpreter trampoline" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [Block(Value(I32), [I32Const(4), I32Const(8), Br(0), I32Add])],
    "block_nonterminal_branch",
  )
  let env = frontend_test_env()
  inspect(try_lower_native_function(env, mod_, 0) is None, content="true")
}

///|
test "lower terminal block br_if through native linear fast path" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [Block(Value(I32), [I32Const(7), I32Const(1), BrIf(0)])],
    "block_exit_branch_if",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("iconst 7"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower terminal current-block br_table through native linear fast path" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [Block(Value(I32), [I32Const(7), I32Const(1), BrTable([0, 0], 0)])],
    "block_exit_branch_table",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("iconst 7"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower terminal current-block ref branches through native linear fast path" {
  let env = frontend_test_env()
  let null_branch = @types.Module::simple(
    [],
    [FuncRef],
    [Block(Value(FuncRef), [RefNull(FuncRef), BrOnNull(0)])],
    "block_exit_br_on_null",
  )
  let non_null_branch = @types.Module::simple(
    [],
    [FuncRef],
    [Block(Value(FuncRef), [RefNull(FuncRef), BrOnNonNull(0)])],
    "block_exit_br_on_non_null",
  )
  inspect(
    try_lower_native_function(env, null_branch, 0) is Some(_),
    content="true",
  )
  inspect(
    try_lower_native_function(env, non_null_branch, 0) is Some(_),
    content="true",
  )
}

///|
test "lower empty if through native linear fast path" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [I32Const(1), If(Empty, [], []), I32Const(7)],
    "empty_if",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("iconst 7"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower nop-only if through native linear fast path" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [I32Const(0), If(Empty, [Nop], [Nop, Nop]), I32Const(9)],
    "nop_only_if",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("iconst 9"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
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
      { type_: { value_type: I32, mutable: true, }, init: [I32Const(0)], },
    ],
  }
  let env = native_test_env()
  let lowered = try_lower_native_function(env, mod_, 0)
  guard lowered is Some(func) else {
    fail("global roundtrip did not lower natively")
  }
  let text = func.print()
  inspect(text.contains("load.i64"), content="true")
  inspect(text.contains("store.i32"), content="true")
  inspect(text.contains("load.i32"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower table size and get through native VMContext loads" {
  let table : @types.Table = {
    type_: {
      elem_type: FuncRef,
      limits: { min: 2, max: None, },
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
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("load.i64"), content="true")
  inspect(text.contains("ireduce"), content="true")
  inspect(text.contains("trap \"table out of bounds\""), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "production table.get preserves the table element carrier" {
  let table : @types.Table = {
    type_: {
      elem_type: FuncRef,
      limits: { min: 1, max: None, },
      is_table64: false,
    },
    init: None,
  }
  let mod_ = {
    ..@types.Module::simple(
      [],
      [FuncRef],
      [I32Const(0), TableGet(0)],
      "table_get_funcref",
    ),
    tables: [table],
  }
  let func = translate_function(native_test_env(), mod_, 0)
  @wasm_milkir.verify_function(func)
  let imported = {
    ..mod_,
    imports: [{ mod_name: "host", name: "table", desc: Table(table.type_), }],
    tables: [],
  }
  let imported_func = translate_function(native_test_env(), imported, 0)
  @wasm_milkir.verify_function(imported_func)
}

///|
test "lower table set through native table fill runtime call" {
  let table : @types.Table = {
    type_: {
      elem_type: FuncRef,
      limits: { min: 2, max: None, },
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
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("test.TableFill"), content="false")
  inspect(text.contains("call test.runtime.table_fill"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower linear explicit return without legacy bridge" {
  let mod_ = @types.Module::simple(
    [I64, I64],
    [I64],
    [LocalGet(0), LocalGet(1), I64Add, Return],
    "add64",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("iadd"), content="true")
  inspect(text.contains("return"), content="true")
  @wasm_milkir.verify_function(func)
}

///|
test "lower return with dead tail without legacy bridge" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [I32Const(7), Return, I32Const(1), I32Const(2), I32Add],
    "dead_tail",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("return"), content="true")
  inspect(text.contains("iadd"), content="false")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower linear float arithmetic and drop without legacy bridge" {
  let mod_ = @types.Module::simple(
    [F64],
    [F64],
    [F64Const(99.0), Drop, LocalGet(0), F64Const(0.5), F64Sub],
    "adjust",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("fsub"), content="true")
  @wasm_milkir.verify_function(func)
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
  let mod_ = { ..mod_, codes: [{ locals: [I32], body, }], }
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("band"), content="true")
  inspect(text.contains("ishl"), content="true")
  inspect(text.contains("icmp.eq"), content="true")
  inspect(text.contains("select"), content="true")
  @wasm_milkir.verify_function(func)
}

///|
test "lower linear float compare and unary ops natively" {
  let mod_ = @types.Module::simple(
    [F64],
    [I32],
    [LocalGet(0), F64Neg, F64Abs, F64Ceil, F64Const(1.0), F64Ge],
    "float_cmp",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fneg"), content="true")
  inspect(text.contains("fabs"), content="true")
  inspect(text.contains("fceil"), content="true")
  inspect(text.contains("fcmp.ge"), content="true")
  @wasm_milkir.verify_function(func)
}

///|
test "lower linear integer extensions and reduction natively" {
  let mod_ = @types.Module::simple(
    [I64],
    [I32],
    [LocalGet(0), I32WrapI64, I32Extend8S],
    "extend_i32",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("ireduce"), content="true")
  inspect(text.contains("sextend8"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower linear i64 extensions natively" {
  let mod_ = @types.Module::simple(
    [I32],
    [I64],
    [LocalGet(0), I64ExtendI32U, I64Extend32S],
    "extend_i64",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("uextend"), content="true")
  inspect(text.contains("sextend32"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower linear float promotion and demotion natively" {
  let mod_ = @types.Module::simple(
    [F64],
    [F32],
    [LocalGet(0), F32DemoteF64, F64PromoteF32, F32DemoteF64],
    "float_resize",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fdemote"), content="true")
  inspect(text.contains("fpromote"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower linear numeric conversions natively" {
  let mod_ = @types.Module::simple(
    [F64, I64],
    [F32],
    [LocalGet(0), I32TruncF64S, Drop, LocalGet(1), F32ConvertI64U],
    "numeric_convert",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fcvt_to_sint"), content="true")
  inspect(text.contains("uint_to_fcvt"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower linear saturating conversion and reinterpret natively" {
  let mod_ = @types.Module::simple(
    [F32, I64],
    [F64],
    [LocalGet(0), I32TruncSatF32U, Drop, LocalGet(1), F64ReinterpretI64],
    "sat_bitcast",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("fcvt_to_uint_sat"), content="true")
  inspect(text.contains("bitcast"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower pure if into native MilkIR select" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), If(Value(I32), [I32Const(111)], [I32Const(222)])],
    "select_const",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("select"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower pure if expression bodies into native MilkIR select" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [
      LocalGet(0),
      If(Value(I32), [LocalGet(0), I32Const(10), I32Add], [
        LocalGet(0),
        I32Const(1),
        I32Shl,
      ]),
    ],
    "select_expr_body",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(func.blocks.length(), content="1")
  inspect(text.contains("iadd"), content="true")
  inspect(text.contains("ishl"), content="true")
  inspect(text.contains("select"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower pure if copysign and wide multiply expression bodies" {
  let float_mod = @types.Module::simple(
    [I32, F32, F32],
    [F32],
    [
      LocalGet(0),
      If(Value(F32), [LocalGet(1), LocalGet(2), F32Copysign], [
        LocalGet(2),
        LocalGet(1),
        F32Copysign,
      ]),
    ],
    "select_copysign_body",
  )
  let wide_mod = @types.Module::simple(
    [I32, I64, I64],
    [I64],
    [
      LocalGet(0),
      If(Value(I64), [LocalGet(1), LocalGet(2), I64MulWideU], [
        LocalGet(1),
        LocalGet(2),
        I64MulWideS,
      ]),
    ],
    "select_wide_mul_body",
  )
  let env = frontend_test_env()
  let float_func = lower_function(env, float_mod, 0)
  let wide_func = lower_function(env, wide_mod, 0)
  inspect(float_func.print().contains("bor"), content="true")
  inspect(float_func.print().contains("select"), content="true")
  inspect(float_func.print().contains("TODO(wasm_frontend)"), content="false")
  inspect(wide_func.print().contains("umulh"), content="true")
  inspect(wide_func.print().contains("smulh"), content="true")
  inspect(wide_func.print().contains("select"), content="true")
  inspect(wide_func.print().contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(float_func)
  @wasm_milkir.verify_function(wide_func)
}

///|
test "lower trap without wasm_frontend skeleton fallback" {
  let mod_ = @types.Module::simple([], [], [Unreachable], "trap")
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("unreachable"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
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
  let add_type : @types.FuncType = { params: [I32, I32], results: [I32], }
  let main_type : @types.FuncType = { params: [], results: [I32], }
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
    exports: [{ name: "main", desc: Func(1), }],
    start: None,
    elems: [],
    codes: [add_func, main_func],
    datas: [],
    tags: [],
    func_names: Map([]),
  }
  let env = native_test_env()
  let func = lower_function(env, mod_, 1)
  let text = func.print()
  inspect(text.contains("call_ptr(3) -> 1"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower memory operations through native MilkIR memory ops" {
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
      {
        limits: { min: 1, max: None, },
        is_memory64: false,
        page_size_log2: 16,
      },
    ],
  }
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("test.LoadMemBase"), content="false")
  inspect(text.contains("load.i64"), content="true")
  inspect(text.contains("load.i32"), content="true")
  inspect(text.contains("store.i32"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower copysign through native MilkIR bit operations" {
  let mod_ = @types.Module::simple(
    [F32, F32, F64, F64],
    [F32, F64],
    [
      LocalGet(0),
      LocalGet(1),
      F32Copysign,
      LocalGet(2),
      LocalGet(3),
      F64Copysign,
    ],
    "copysign",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("bitcast"), content="true")
  inspect(text.contains("band"), content="true")
  inspect(text.contains("bor"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower wide i64 multiply through native MilkIR high-half ops" {
  let mod_ = @types.Module::simple(
    [I64, I64],
    [I64, I64],
    [
      LocalGet(0),
      LocalGet(1),
      I64MulWideU,
      LocalGet(0),
      LocalGet(1),
      I64MulWideS,
    ],
    "wide_mul",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("umulh"), content="true")
  inspect(text.contains("smulh"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower narrow memory operations through native MilkIR memory ops" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [
        I32Const(0),
        I32Const(0x1234),
        I32Store16(0, 1, 2),
        I32Const(1),
        I32Load8S(0, 0, 2),
      ],
      "narrow_memory",
    ),
    memories: [
      {
        limits: { min: 1, max: None, },
        is_memory64: false,
        page_size_log2: 16,
      },
    ],
  }
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("test.LoadMemBase"), content="false")
  inspect(text.contains("load.i64"), content="true")
  inspect(text.contains("store16"), content="true")
  inspect(text.contains("load8_s.i32"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower memory grow size and bulk helpers as native helper calls" {
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
      {
        limits: { min: 1, max: None, },
        is_memory64: false,
        page_size_log2: 16,
      },
    ],
  }
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("test.MemorySize"), content="false")
  inspect(text.contains("test.MemoryGrow"), content="false")
  inspect(text.contains("load.i64"), content="true")
  inspect(text.contains("ushr"), content="true")
  inspect(text.contains("call test.runtime.memory_grow"), content="true")
  inspect(text.contains("test.MemoryFill"), content="false")
  inspect(text.contains("test.MemoryCopy"), content="false")
  inspect(text.contains("call test.runtime.memory_fill"), content="true")
  inspect(text.contains("call test.runtime.memory_copy"), content="true")
  inspect(text.contains("test.MemoryInit"), content="false")
  inspect(text.contains("test.DataDrop"), content="false")
  inspect(text.contains("call test.runtime.memory_init"), content="true")
  inspect(text.contains("call test.runtime.data_drop"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower non-zero memory.size through native descriptor loads" {
  let mod_ = {
    ..@types.Module::simple([], [I32], [MemorySize(1)], "memory1_size"),
    memories: [
      {
        limits: { min: 1, max: None, },
        is_memory64: false,
        page_size_log2: 16,
      },
      {
        limits: { min: 2, max: None, },
        is_memory64: false,
        page_size_log2: 16,
      },
    ],
  }
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("test.MemorySize"), content="false")
  inspect(text.contains("load.i64"), content="true")
  inspect(text.contains("ushr"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower non-zero memory load store with explicit bounds check" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [
        I32Const(0),
        I32Const(7),
        I32Store(1, 2, 0),
        I32Const(0),
        I32Load(1, 2, 0),
      ],
      "memory1_roundtrip",
    ),
    memories: [
      {
        limits: { min: 1, max: None, },
        is_memory64: false,
        page_size_log2: 16,
      },
      {
        limits: { min: 1, max: None, },
        is_memory64: false,
        page_size_log2: 16,
      },
    ],
  }
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("test.LoadMemBase"), content="false")
  inspect(text.contains("trap \"memory out of bounds\""), content="true")
  inspect(text.contains("load.i32"), content="true")
  inspect(text.contains("store.i32"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower memory64 load with overflow-safe bounds check" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [I64Const(0L), I32Load(0, 2, 0)],
      "memory64_load",
    ),
    memories: [
      { limits: { min: 1, max: None, }, is_memory64: true, page_size_log2: 16, },
    ],
  }
  let env = native_test_env()
  let lowered = try_lower_native_function(env, mod_, 0)
  guard lowered is Some(func) else {
    fail("memory64 load did not lower natively")
  }
  let text = func.print()
  inspect(text.contains("test.LoadMemBase"), content="false")
  inspect(text.contains("trap \"memory out of bounds\""), content="true")
  inspect(text.contains("icmp.uge"), content="true")
  inspect(text.contains("icmp.ule"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower memory64 narrow load store with overflow-safe bounds check" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [
        I64Const(0L),
        I32Const(7),
        I32Store8(0, 0, 0),
        I64Const(0L),
        I32Load8U(0, 0, 0),
      ],
      "memory64_narrow_roundtrip",
    ),
    memories: [
      { limits: { min: 1, max: None, }, is_memory64: true, page_size_log2: 16, },
    ],
  }
  let env = native_test_env()
  let lowered = try_lower_native_function(env, mod_, 0)
  guard lowered is Some(func) else {
    fail("memory64 narrow load/store did not lower natively")
  }
  let text = func.print()
  inspect(text.contains("test.LoadMemBase"), content="false")
  inspect(text.contains("trap \"memory out of bounds\""), content="true")
  inspect(text.contains("load8_u.i32"), content="true")
  inspect(text.contains("store8"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower v128 load store through native memory path" {
  let body : Array[@types.Instruction] = [
    I32Const(0),
    LocalGet(0),
    V128Store(0, 4, 0),
    I32Const(0),
    V128Load(0, 4, 0),
  ]
  let mod_ = {
    ..@types.Module::simple([V128], [V128], body, "v128_roundtrip"),
    memories: [
      {
        limits: { min: 1, max: None, },
        is_memory64: false,
        page_size_log2: 16,
      },
    ],
  }
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("load.v128"), content="true")
  inspect(text.contains("store.v128"), content="true")
  inspect(text.contains("test.LoadMemBase"), content="false")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower table bulk helpers as native helper calls" {
  let table : @types.Table = {
    type_: {
      elem_type: FuncRef,
      limits: { min: 2, max: None, },
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
  let env = native_test_env()
  inspect(try_lower_native_function(env, mod_, 0) is Some(_), content="true")
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("test.TableGrow"), content="false")
  inspect(text.contains("test.TableFill"), content="false")
  inspect(text.contains("test.TableCopy"), content="false")
  inspect(text.contains("test.TableInit"), content="false")
  inspect(text.contains("test.ElemDrop"), content="false")
  inspect(text.contains("call test.runtime.table_grow"), content="true")
  inspect(text.contains("call test.runtime.table_fill"), content="true")
  inspect(text.contains("call test.runtime.table_copy"), content="true")
  inspect(text.contains("call test.runtime.table_init"), content="true")
  inspect(text.contains("call test.runtime.elem_drop"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower reference null and is_null natively" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [RefNull(FuncRef), RefIsNull],
    "ref_null_test",
  )
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("iconst"), content="true")
  inspect(text.contains("icmp.eq"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower reference func non-null and eq natively" {
  let mod_ = @types.Module::simple(
    [],
    [I32],
    [RefFunc(0), RefAsNonNull, RefFunc(0), RefEqInstr],
    "ref_func_eq",
  )
  let env = native_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("test.GetFuncRef"), content="false")
  inspect(text.contains("load.ref"), content="true")
  inspect(text.contains("bor"), content="true")
  inspect(text.contains("trap \"null reference\""), content="true")
  inspect(text.contains("icmp.eq"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower i31 refs through native linear fast path" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), RefI31, I31GetS],
    "i31_roundtrip",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("band"), content="true")
  inspect(text.contains("uextend"), content="true")
  inspect(text.contains("trap \"null i31 reference\""), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "lower ref conversion copies through native linear fast path" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), RefI31, ExternConvertAny, AnyConvertExtern, I31GetU],
    "ref_convert_copy",
  )
  let env = frontend_test_env()
  let func = lower_function(env, mod_, 0)
  let text = func.print()
  inspect(text.contains("copy"), content="true")
  inspect(text.contains("TODO(wasm_frontend)"), content="false")
  @wasm_milkir.verify_function(func)
}

///|
test "pure if rejects trapping i31 get in branch expression" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), If(Value(I32), [I32Const(7)], [RefNull(RefNullI31), I31GetS])],
    "if_i31_trap_arm",
  )
  let env = frontend_test_env()
  inspect(try_lower_native_function(env, mod_, 0) is None, content="true")
}

///|
test "unsupported structured branch reports label-stack capability" {
  let mod_ = @types.Module::simple(
    [],
    [],
    [Loop(Empty, [Br(0)])],
    "loop_branch",
  )
  let env = frontend_test_env()
  try lower_function(env, mod_, 0) catch {
    err => {
      let msg = Repr(err).to_string()
      inspect(
        msg.contains("structured branches require label-stack lowering"),
        content="true",
      )
    }
  } noraise {
    _ => fail("expected unsupported native lowering")
  }
}

///|
test "unsupported memory64 bulk helper reports runtime ABI capability" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [],
      [I64Const(0L), I32Const(0), I64Const(4L), MemoryFill(0)],
      "memory64_fill",
    ),
    memories: [
      { limits: { min: 1, max: None, }, is_memory64: true, page_size_log2: 16, },
    ],
  }
  let env = native_test_env()
  try lower_function(env, mod_, 0) catch {
    err => {
      let msg = Repr(err).to_string()
      inspect(
        msg.contains(
          "memory64 memory.fill requires a reusable runtime helper ABI",
        ),
        content="true",
      )
    }
  } noraise {
    _ => fail("expected unsupported native lowering")
  }
}

///|
test "lower rejects missing wasm function" {
  let mod_ = @types.Module::empty()
  let env = native_test_env()
  try lower_function(env, mod_, 0) catch {
    err => inspect(err, content="FunctionIndexOutOfRange(index=0)")
  } noraise {
    _ => fail("expected missing wasm function")
  }
}
