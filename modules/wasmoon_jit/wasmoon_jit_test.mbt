///|
test "plan Wasmoon JIT integration through a target-owned code object" {
  let milk = @milkir.Function::with_signature("entry", Signature([], []))
  let entry = milk.new_block0()
  entry.set_terminator(Return([]))
  let x64_plan = plan_milkir_integration_for_target(milk, X64)
  inspect(x64_plan.entry_symbol, content="entry")
  debug_inspect(x64_plan.target, content="X64")
  debug_inspect(
    x64_plan.object,
    content=(
      #|{
      #|  code: [195],
      #|  frame_size: 0,
      #|  func_addr_fixups: [],
      #|  call_fixups: [],
      #|  gc_safepoints: [],
      #|}
    ),
  )
  let aarch64_plan = plan_milkir_integration_for_target(milk, AArch64)
  debug_inspect(aarch64_plan.target, content="AArch64")
  debug_inspect(
    aarch64_plan.object,
    content=(
      #|{
      #|  code: [192, 3, 95, 214],
      #|  frame_size: 0,
      #|  func_addr_fixups: [],
      #|  call_fixups: [],
      #|  gc_safepoints: [],
      #|}
    ),
  )
}

///|
test "native diagnostics stream MilkIR directly into both targets" {
  let signature = @milkir.Signature::Signature([Ptr, I64, I64], [I64])
  let function = @milkir.Function::with_signature("diagnostic_add64", signature)
  let lhs = function.param(1).unwrap()
  let rhs = function.param(2).unwrap()
  let sum = function.new_value(I64)
  let entry = function.new_block([])
  entry.append_inst(
    function.new_inst(Scalar(IntBinary(Add)), [lhs, rhs], [sum]),
  )
  entry.set_terminator(Return([sum]))
  let x64 = compile_wasm_body_diagnostics_for_target(
    function,
    @wasm_milkir.WasmValidationContext::empty(),
    X64,
  )
  let aarch64 = compile_wasm_body_diagnostics_for_target(
    function,
    @wasm_milkir.WasmValidationContext::empty(),
    AArch64,
  )
  inspect(x64.target_vcode.contains("IntBinary(W64, Add)"), content="true")
  inspect(x64.machine_code, content="48 89 f0 48 01 d0 c3")
  inspect(aarch64.target_vcode.contains("IntBinary(W64, Add)"), content="true")
  inspect(aarch64.machine_code, content="20 00 02 8b c0 03 5f d6")
}

///|
test "JIT diagnostics return invalid Wasm dialect errors" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("invalid_wasm_dialect")
  builder.add_param(Ptr) |> ignore
  @wasm_milkir.get_exception_tag(builder) |> ignore
  builder.emit_void_ext_inst(ExtOp("wasm", "typo", []), [])
  builder.return_([])
  try
    compile_wasm_body_diagnostics_for_target(
      builder.get_function(),
      @wasm_milkir.WasmValidationContext::empty(),
      X64,
    )
  catch {
    err =>
      inspect(
        err,
        content=(
          #|NativeLoweringFailed(cause=InvalidMilkIR(message="UnverifiableInstruction(message=\"unknown Wasm MilkIR extension opcode 'typo'\")"))
        ),
      )
  } noraise {
    _ => fail("expected JIT integration to return a pipeline error")
  }
}

///|
test "plan MilkIR through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("add64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntBinary(Add)), [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="add64")
  debug_inspect(
    plan.object,
    content=(
      #|{
      #|  code: [72, 137, 248, 72, 1, 240, 195],
      #|  frame_size: 0,
      #|  func_addr_fixups: [],
      #|  call_fixups: [],
      #|  gc_safepoints: [],
      #|}
    ),
  )
}

///|
test "plan Wasm body MilkIR through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([Ptr, I64, I64], [I64])
  let milk = @milkir.Function::with_signature("wasm_body_add64", signature)
  let vmctx = milk.param(0).unwrap()
  let lhs = milk.param(1).unwrap()
  let rhs = milk.param(2).unwrap()
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntBinary(Add)), [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = plan_wasm_body_milkir_integration_for_target(
    milk,
    @wasm_milkir.WasmValidationContext::empty(),
    X64,
  )
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="wasm_body_add64")
  debug_inspect(
    plan.object,
    content=(
      #|{
      #|  code: [72, 137, 240, 72, 1, 208, 195],
      #|  frame_size: 0,
      #|  func_addr_fixups: [],
      #|  call_fixups: [],
      #|  gc_safepoints: [],
      #|}
    ),
  )
  inspect(vmctx.id < lhs.id && lhs.id < rhs.id, content="true")
}

///|
test "plan MilkIR branch block params through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([], [I64])
  let milk = @milkir.Function::with_signature("branch_block_params", signature)
  let cond = milk.new_value(I32)
  let true_value = milk.new_value(I64)
  let false_value = milk.new_value(I64)
  let true_param = milk.new_value(I64)
  let false_param = milk.new_value(I64)
  let entry = milk.new_block([])
  let then_block = milk.new_block([true_param])
  let else_block = milk.new_block([false_param])
  entry.append_inst(milk.new_inst(Scalar(IntConst(1L)), [], [cond]))
  entry.append_inst(milk.new_inst(Scalar(IntConst(42L)), [], [true_value]))
  entry.append_inst(milk.new_inst(Scalar(IntConst(7L)), [], [false_value]))
  entry.set_terminator(
    Branch(cond, then_block.id, [true_value], else_block.id, [false_value]),
  )
  then_block.set_terminator(Return([true_param]))
  else_block.set_terminator(Return([false_param]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  debug_inspect(
    plan.object,
    content=(
      #|{
      #|  code: [
      #|    72,
      #|    184,
      #|    1,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    72,
      #|    185,
      #|    42,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    72,
      #|    186,
      #|    7,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    0,
      #|    133,
      #|    192,
      #|    15,
      #|    133,
      #|    4,
      #|    0,
      #|    0,
      #|    0,
      #|    72,
      #|    137,
      #|    208,
      #|    195,
      #|    72,
      #|    137,
      #|    200,
      #|    195,
      #|  ],
      #|  frame_size: 0,
      #|  func_addr_fixups: [],
      #|  call_fixups: [],
      #|  gc_safepoints: [],
      #|}
    ),
  )
}

///|
test "plan MilkIR CallPtr through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([Ptr, Ptr, I64], [I64])
  let milk = @milkir.Function::with_signature("callptr64", signature)
  let callee = milk.param(0).unwrap()
  let vmctx = milk.param(1).unwrap()
  let arg = milk.param(2).unwrap()
  let result = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Call(Pointer(2, 1)), [callee, vmctx, arg], [result]),
  )
  entry.set_terminator(Return([result]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="callptr64")
  let bytes = plan.object.get_bytes()
  debug_inspect(
    bytes,
    content=(
      #|[
      #|  85,
      #|  72,
      #|  137,
      #|  229,
      #|  72,
      #|  137,
      #|  248,
      #|  72,
      #|  137,
      #|  247,
      #|  72,
      #|  137,
      #|  214,
      #|  255,
      #|  208,
      #|  93,
      #|  195,
      #|]
    ),
  )
}

///|
test "plan scalar entry trampoline through reusable JIT pipeline" {
  let params : Array[@types.ValueType] = [I64, I64]
  let results : Array[@types.ValueType] = [I64]
  let plan = plan_entry_trampoline_for_target(params, results, X64) catch {
    err => fail(Repr(err).to_string())
  }
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="entry_trampoline")
  inspect(plan.object.get_bytes().length() > 0, content="true")
  let aarch64_plan = plan_entry_trampoline_for_target(params, results, AArch64) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(aarch64_plan.object.get_bytes().length() > 0, content="true")
  inspect(
    aarch64_plan.object.get_bytes()[aarch64_plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    aarch64_plan.object.get_bytes()[aarch64_plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "entry trampoline reports V128 MilkIR planner gap" {
  let params : Array[@types.ValueType] = [V128]
  let results : Array[@types.ValueType] = []
  try plan_entry_trampoline_for_target(params, results, X64) catch {
    UnsupportedEntrySignature(message=msg) =>
      inspect(msg.contains("V128 MilkIR entry trampoline"), content="true")
    error => fail("unexpected entry trampoline error: \{Repr(error)}")
  } noraise {
    _ => fail("expected V128 trampoline planning to report unsupported")
  }
}

///|
test "entry trampoline production gate is conservative" {
  inspect(can_use_reusable_entry_trampoline([I64, I64], [I64]), content="true")
  inspect(
    can_use_reusable_entry_trampoline([I64, I64, I64], [I64]),
    content="false",
  )
  inspect(can_use_reusable_entry_trampoline([F64], [F64]), content="false")
  inspect(can_use_reusable_entry_trampoline([V128], []), content="false")
  inspect(can_use_reusable_entry_trampoline([I64], [I64, I64]), content="false")
}

///|
test "entry trampoline signature planning lives in wasmoon_jit" {
  debug_inspect(
    entry_trampoline_type_codes([I32, I64, F32, F64, V128, ExternRef]),
    content="[0, 1, 2, 3, 4, 1]",
  )
  inspect(count_entry_trampoline_slots([I64, V128, ExternRef]), content="4")
  inspect(
    entry_trampoline_signature_hash([I64, I64], [I64]) ==
    entry_trampoline_signature_hash([I64, I64], [I64]),
    content="true",
  )
  inspect(
    entry_trampoline_signature_hash([I64, I64], [I64]) ==
    entry_trampoline_signature_hash([I64], [I64, I64]),
    content="false",
  )
}

///|
test "plan hostcall import trampoline values_vec layout" {
  let params : Array[@types.ValueType] = [
    I32,
    I64,
    F32,
    F64,
    V128,
    ExternRef,
    I64,
  ]
  let results : Array[@types.ValueType] = [I64, V128, F32]
  let layout = plan_hostcall_import_trampoline_layout(params, results, 2, 2)
  inspect(layout.arg_slots, content="8")
  inspect(layout.result_slots, content="4")
  inspect(layout.values_vec_bytes, content="96")
  inspect(layout.int_overflow_count, content="2")
  debug_inspect(layout.float_overflow_types, content="[V128]")
  inspect(hostcall_value_slot_count(V128), content="2")
  inspect(hostcall_value_byte_count(V128), content="16")
  inspect(hostcall_value_slot_count(ExternRef), content="1")
}

///|
test "machine-code entry trampolines support V128 registers" {
  let params : Array[@types.ValueType] = [V128]
  let results : Array[@types.ValueType] = [V128]
  let x64_code = build_entry_trampoline_for_target(params, results, X64) catch {
    err => fail(Repr(err).to_string())
  }
  let mut x64_has_load = false
  let mut x64_has_store = false
  for i in 0..<(x64_code.length() - 3) {
    if x64_code[i] == 0xf3 && x64_code[i + 2] == 0x0f && x64_code[i + 3] == 0x6f {
      x64_has_load = true
    }
    if x64_code[i] == 0xf3 && x64_code[i + 2] == 0x0f && x64_code[i + 3] == 0x7f {
      x64_has_store = true
    }
  }
  inspect(x64_has_load, content="true")
  inspect(x64_has_store, content="true")
  let a64_code = build_entry_trampoline_for_target(params, results, AArch64) catch {
    err => fail(Repr(err).to_string())
  }
  let mut a64_has_load = false
  let mut a64_has_store = false
  for i in 0..<(a64_code.length() - 3) {
    if a64_code[i + 3] == 0x3d {
      if (a64_code[i + 2] & 0xc0) == 0xc0 {
        a64_has_load = true
      } else if (a64_code[i + 2] & 0x80) == 0x80 {
        a64_has_store = true
      }
    }
  }
  inspect(a64_has_load, content="true")
  inspect(a64_has_store, content="true")
}

///|
test "hostcall trampolines support V128 registers" {
  let params : Array[@types.ValueType] = [V128]
  let results : Array[@types.ValueType] = [V128]
  let x64_host = build_hostcall_import_trampoline_for_target(
    params,
    results,
    0,
    X64,
  ) catch {
    err => fail(Repr(err).to_string())
  }
  let mut x64_has_store = false
  let mut x64_has_load = false
  for i in 0..<(x64_host.code.length() - 3) {
    if x64_host.code[i] == 0xf3 &&
      x64_host.code[i + 2] == 0x0f &&
      x64_host.code[i + 3] == 0x7f {
      x64_has_store = true
    }
    if x64_host.code[i] == 0xf3 &&
      x64_host.code[i + 2] == 0x0f &&
      x64_host.code[i + 3] == 0x6f {
      x64_has_load = true
    }
  }
  inspect(x64_has_store, content="true")
  inspect(x64_has_load, content="true")
  let a64_host = build_hostcall_import_trampoline_for_target(
    params,
    results,
    0,
    AArch64,
  ) catch {
    err => fail(Repr(err).to_string())
  }
  let mut a64_has_store = false
  let mut a64_has_load = false
  for i in 0..<(a64_host.code.length() - 3) {
    if a64_host.code[i + 3] == 0x3d {
      if (a64_host.code[i + 2] & 0xc0) == 0xc0 {
        a64_has_load = true
      } else if (a64_host.code[i + 2] & 0x80) == 0x80 {
        a64_has_store = true
      }
    }
  }
  inspect(a64_has_store, content="true")
  inspect(a64_has_load, content="true")
}

///|
fn code_contains_x64_rsp_int_load(code : Array[Int]) -> Bool {
  if code.length() < 4 {
    return false
  }
  for i in 0..<(code.length() - 3) {
    if code[i] == 0x4c &&
      code[i + 1] == 0x8b &&
      code[i + 2] == 0x94 &&
      code[i + 3] == 0x24 {
      return true
    }
  }
  false
}

///|
fn code_contains_byte(code : Array[Int], byte : Int) -> Bool {
  for b in code {
    if b == byte {
      return true
    }
  }
  false
}

///|
fn code_contains_pair(code : Array[Int], b0 : Int, b1 : Int) -> Bool {
  if code.length() < 2 {
    return false
  }
  for i in 0..<(code.length() - 1) {
    if code[i] == b0 && code[i + 1] == b1 {
      return true
    }
  }
  false
}

///|
fn code_contains_x64_rsp_int_store(code : Array[Int]) -> Bool {
  if code.length() < 4 {
    return false
  }
  for i in 0..<(code.length() - 3) {
    if code[i] == 0x4c &&
      code[i + 1] == 0x89 &&
      code[i + 2] == 0x94 &&
      code[i + 3] == 0x24 {
      return true
    }
  }
  false
}

///|
fn code_contains_x64_r12_int_store(code : Array[Int]) -> Bool {
  if code.length() < 4 {
    return false
  }
  for i in 0..<(code.length() - 3) {
    if code[i] == 0x4d &&
      code[i + 1] == 0x89 &&
      code[i + 2] == 0x94 &&
      code[i + 3] == 0x24 {
      return true
    }
  }
  false
}

///|
fn code_contains_x64_r14_int_load(code : Array[Int]) -> Bool {
  if code.length() < 3 {
    return false
  }
  for i in 0..<(code.length() - 2) {
    if code[i] == 0x4d && code[i + 1] == 0x8b && code[i + 2] == 0x96 {
      return true
    }
  }
  false
}

///|
fn code_contains_x64_r14_int_store(code : Array[Int]) -> Bool {
  if code.length() < 3 {
    return false
  }
  for i in 0..<(code.length() - 2) {
    if code[i] == 0x4d && code[i + 1] == 0x89 && code[i + 2] == 0x96 {
      return true
    }
  }
  false
}

///|
fn code_contains_a64_x16_load_from_base(code : Array[Int], base : Int) -> Bool {
  if code.length() < 4 {
    return false
  }
  let expected = 0xf9400000 | ((base & 31) << 5) | 16
  let mask = 0xffc003ff
  for i in 0..<(code.length() - 3) {
    let word = code[i] |
      (code[i + 1] << 8) |
      (code[i + 2] << 16) |
      (code[i + 3] << 24)
    if (word & mask) == expected {
      return true
    }
  }
  false
}

///|
fn code_contains_a64_x16_store_to_base(code : Array[Int], base : Int) -> Bool {
  if code.length() < 4 {
    return false
  }
  let expected = 0xf9000000 | ((base & 31) << 5) | 16
  let mask = 0xffc003ff
  for i in 0..<(code.length() - 3) {
    let word = code[i] |
      (code[i + 1] << 8) |
      (code[i + 2] << 16) |
      (code[i + 3] << 24)
    if (word & mask) == expected {
      return true
    }
  }
  false
}

///|
test "hostcall trampolines support stack-passed arguments" {
  let x64_params : Array[@types.ValueType] = [I64, I64, I64, I64, I64, I64]
  let a64_params : Array[@types.ValueType] = [
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let results : Array[@types.ValueType] = []
  let x64_host = build_hostcall_import_trampoline_for_target(
    x64_params,
    results,
    0,
    X64,
  ) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(code_contains_x64_rsp_int_load(x64_host.code), content="true")
  inspect(code_contains_x64_rsp_int_store(x64_host.code), content="true")
  let a64_host = build_hostcall_import_trampoline_for_target(
    a64_params,
    results,
    0,
    AArch64,
  ) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(
    code_contains_a64_x16_load_from_base(a64_host.code, 31),
    content="true",
  )
  inspect(
    code_contains_a64_x16_store_to_base(a64_host.code, 31),
    content="true",
  )
}

///|
test "entry trampolines support stack-passed arguments" {
  let x64_params : Array[@types.ValueType] = [I64, I64, I64, I64, I64, I64]
  let a64_params : Array[@types.ValueType] = [
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let results : Array[@types.ValueType] = []
  let x64_code = build_entry_trampoline_for_target(x64_params, results, X64) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(code_contains_x64_r14_int_load(x64_code), content="true")
  inspect(code_contains_x64_rsp_int_store(x64_code), content="true")
  let a64_code = build_entry_trampoline_for_target(a64_params, results, AArch64) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(code_contains_a64_x16_load_from_base(a64_code, 19), content="true")
  inspect(code_contains_a64_x16_store_to_base(a64_code, 31), content="true")
}

///|
test "hostcall trampolines support overflow result areas" {
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = [
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let x64_host = build_hostcall_import_trampoline_for_target(
    params,
    results,
    0,
    X64,
  ) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(code_contains_x64_rsp_int_load(x64_host.code), content="true")
  inspect(code_contains_x64_r12_int_store(x64_host.code), content="true")
  let a64_host = build_hostcall_import_trampoline_for_target(
    params,
    results,
    0,
    AArch64,
  ) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(
    code_contains_a64_x16_load_from_base(a64_host.code, 31),
    content="true",
  )
  inspect(
    code_contains_a64_x16_store_to_base(a64_host.code, 23),
    content="true",
  )
}

///|
test "entry trampolines support overflow result areas" {
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = [
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let x64_code = build_entry_trampoline_for_target(params, results, X64) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(code_contains_x64_rsp_int_load(x64_code), content="true")
  inspect(code_contains_x64_r14_int_store(x64_code), content="true")
  let a64_code = build_entry_trampoline_for_target(params, results, AArch64) catch {
    err => fail(Repr(err).to_string())
  }
  inspect(code_contains_a64_x16_load_from_base(a64_code, 31), content="true")
  inspect(code_contains_a64_x16_store_to_base(a64_code, 19), content="true")
}

///|
test "plan MilkIR floating point through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([F64, F64], [F64])
  let milk = @milkir.Function::with_signature("fadd64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let sum = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(FloatBinary(Add)), [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="fadd64")
  debug_inspect(
    plan.object,
    content=(
      #|{
      #|  code: [242, 15, 88, 193, 195],
      #|  frame_size: 0,
      #|  func_addr_fixups: [],
      #|  call_fixups: [],
      #|  gc_safepoints: [],
      #|}
    ),
  )
}

///|
test "plan MilkIR floating abs and neg through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([F64], [F64])
  let milk = @milkir.Function::with_signature("fabs_fneg64", signature)
  let input = milk.param(0).unwrap()
  let neg = milk.new_value(F64)
  let abs = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(FloatUnary(Neg)), [input], [neg]))
  entry.append_inst(milk.new_inst(Scalar(FloatUnary(Abs)), [neg], [abs]))
  entry.set_terminator(Return([abs]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_abs_mask = false
  let mut has_neg_mask = false
  for byte in plan.object.get_bytes() {
    if byte == 0x54 {
      has_abs_mask = true
    }
    if byte == 0x57 {
      has_neg_mask = true
    }
  }
  inspect(has_abs_mask, content="true")
  inspect(has_neg_mask, content="true")
  inspect(code_contains_byte(plan.object.get_bytes(), 0xc3), content="true")
}

///|
test "plan MilkIR f64 const through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([], [F64])
  let milk = @milkir.Function::with_signature("fconst64_x64", signature)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(
      Scalar(FloatConst64((1.5 : Double).reinterpret_as_uint64())),
      [],
      [output],
    ),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let bytes = plan.object.get_bytes()
  inspect(bytes.length() > 0, content="true")
  inspect(code_contains_byte(bytes, 0xc3), content="true")
}

///|
test "plan MilkIR f32 const through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([], [F32])
  let milk = @milkir.Function::with_signature("fconst32_aarch64", signature)
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  let bits = (1.25 : Float).reinterpret_as_uint()
  entry.append_inst(milk.new_inst(Scalar(FloatConst32(bits)), [], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_fmov_w_to_s = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if plan.object.get_bytes()[i + 2] == 0x27 &&
      plan.object.get_bytes()[i + 3] == 0x1e {
      has_fmov_w_to_s = true
    }
  }
  inspect(has_fmov_w_to_s, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR float promote through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([F32], [F64])
  let milk = @milkir.Function::with_signature("fpromote_x64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(Convert(FloatPromote)), [input], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_cvtss2sd = false
  for i in 0..<(plan.object.get_bytes().length() - 2) {
    if plan.object.get_bytes()[i] == 0xf3 &&
      plan.object.get_bytes()[i + 1] == 0x0f &&
      plan.object.get_bytes()[i + 2] == 0x5a {
      has_cvtss2sd = true
    }
  }
  inspect(has_cvtss2sd, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR float demote through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([F64], [F32])
  let milk = @milkir.Function::with_signature("fdemote_aarch64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(Convert(FloatDemote)), [input], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_fcvt_s_d = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if (plan.object.get_bytes()[i + 1] & 0x40) == 0x40 &&
      plan.object.get_bytes()[i + 2] == 0x62 &&
      plan.object.get_bytes()[i + 3] == 0x1e {
      has_fcvt_s_d = true
    }
  }
  inspect(has_fcvt_s_d, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR float ceil through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([F32], [F32])
  let milk = @milkir.Function::with_signature("fceil_x64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(FloatUnary(Ceil)), [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_roundss_ceil = false
  for i in 0..<(plan.object.get_bytes().length() - 4) {
    if plan.object.get_bytes()[i] == 0x0f &&
      plan.object.get_bytes()[i + 1] == 0x3a &&
      plan.object.get_bytes()[i + 2] == 0x0a &&
      plan.object.get_bytes()[i + 4] == 0x02 {
      has_roundss_ceil = true
    }
  }
  inspect(has_roundss_ceil, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR float nearest through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([F64], [F64])
  let milk = @milkir.Function::with_signature("fnearest_aarch64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(FloatUnary(Nearest)), [input], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_frintn_d = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if (plan.object.get_bytes()[i + 1] & 0x40) == 0x40 &&
      plan.object.get_bytes()[i + 2] == 0x64 &&
      plan.object.get_bytes()[i + 3] == 0x1e {
      has_frintn_d = true
    }
  }
  inspect(has_frintn_d, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR float compare through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([F64, F64], [I32])
  let milk = @milkir.Function::with_signature("fcmp_eq_x64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(FloatCompare(Eq)), [lhs, rhs], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_ucomisd = false
  let mut has_setnp = false
  for i in 0..<(plan.object.get_bytes().length() - 2) {
    if plan.object.get_bytes()[i] == 0x66 &&
      plan.object.get_bytes()[i + 1] == 0x0f &&
      plan.object.get_bytes()[i + 2] == 0x2e {
      has_ucomisd = true
    }
    if plan.object.get_bytes()[i] == 0x0f &&
      plan.object.get_bytes()[i + 1] == 0x9b {
      has_setnp = true
    }
  }
  inspect(has_ucomisd, content="true")
  inspect(has_setnp, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR float compare through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([F32, F32], [I32])
  let milk = @milkir.Function::with_signature("fcmp_lt_aarch64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(FloatCompare(Lt)), [lhs, rhs], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_fcmp_s = false
  let mut has_cset_mi = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if (plan.object.get_bytes()[i + 2] & 0xe0) == 0x20 &&
      plan.object.get_bytes()[i + 3] == 0x1e {
      has_fcmp_s = true
    }
    if (plan.object.get_bytes()[i + 1] & 0xf0) == 0x50 &&
      plan.object.get_bytes()[i + 2] == 0x9f &&
      plan.object.get_bytes()[i + 3] == 0x9a {
      has_cset_mi = true
    }
  }
  inspect(has_fcmp_s, content="true")
  inspect(has_cset_mi, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR generic memory through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([Ptr, I32], [I32])
  let milk = @milkir.Function::with_signature("generic_mem_x64", signature)
  let ptr = milk.param(0).unwrap()
  let value = milk.param(1).unwrap()
  let loaded = milk.new_value(I32)
  let offset = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntConst(0L)), [], [offset]))
  entry.append_inst(milk.new_inst(Memory(Store(I32)), [ptr, value, offset], []))
  entry.append_inst(milk.new_inst(Memory(Load(I32)), [ptr, offset], [loaded]))
  entry.set_terminator(Return([loaded]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_store = false
  let mut has_load = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0x89 {
      has_store = true
    }
    if plan.object.get_bytes()[i] == 0x8b {
      has_load = true
    }
  }
  inspect(has_store, content="true")
  inspect(has_load, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR narrow memory through reusable x64 JIT pipeline" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("narrow_mem_x64")
  let ptr = builder.add_param(Ptr)
  let value = builder.add_param(I32)
  builder.add_result(I32)
  builder.store_ptr_narrow(16, ptr, value, builder.iconst_i64(8L))
  let loaded = builder.load_ptr_narrow(
    I32,
    8,
    false,
    ptr,
    builder.iconst_i64(4L),
  )
  builder.return_([loaded])
  let plan = plan_milkir_integration_for_target(builder.get_function(), X64)
  let mut has_store16 = false
  let mut has_load8u = false
  for i in 0..<(plan.object.get_bytes().length() - 2) {
    if plan.object.get_bytes()[i] == 0x66 &&
      plan.object.get_bytes()[i + 1] == 0x89 {
      has_store16 = true
    }
    if plan.object.get_bytes()[i] == 0x0f &&
      plan.object.get_bytes()[i + 1] == 0xb6 {
      has_load8u = true
    }
  }
  inspect(has_store16, content="true")
  inspect(has_load8u, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR generic memory through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([Ptr, I32], [I32])
  let milk = @milkir.Function::with_signature("generic_mem_aarch64", signature)
  let ptr = milk.param(0).unwrap()
  let value = milk.param(1).unwrap()
  let loaded = milk.new_value(I32)
  let offset = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntConst(0L)), [], [offset]))
  entry.append_inst(milk.new_inst(Memory(Store(I32)), [ptr, value, offset], []))
  entry.append_inst(milk.new_inst(Memory(Load(I32)), [ptr, offset], [loaded]))
  entry.set_terminator(Return([loaded]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_str_w = false
  let mut has_ldr_w = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if plan.object.get_bytes()[i + 3] == 0xb9 {
      has_str_w = true
    }
    if plan.object.get_bytes()[i + 3] == 0xb9 &&
      (plan.object.get_bytes()[i + 2] & 0x40) == 0x40 {
      has_ldr_w = true
    }
  }
  inspect(has_str_w, content="true")
  inspect(has_ldr_w, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR scalar float memory through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([Ptr, F64], [F64])
  let milk = @milkir.Function::with_signature("float_mem_x64", signature)
  let ptr = milk.param(0).unwrap()
  let value = milk.param(1).unwrap()
  let loaded = milk.new_value(F64)
  let offset = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntConst(0L)), [], [offset]))
  entry.append_inst(milk.new_inst(Memory(Store(F64)), [ptr, value, offset], []))
  entry.append_inst(milk.new_inst(Memory(Load(F64)), [ptr, offset], [loaded]))
  entry.set_terminator(Return([loaded]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_movsd_store = false
  let mut has_movsd_load = false
  for i in 0..<(plan.object.get_bytes().length() - 2) {
    if plan.object.get_bytes()[i] == 0xf2 &&
      plan.object.get_bytes()[i + 1] == 0x0f &&
      plan.object.get_bytes()[i + 2] == 0x11 {
      has_movsd_store = true
    }
    if plan.object.get_bytes()[i] == 0xf2 &&
      plan.object.get_bytes()[i + 1] == 0x0f &&
      plan.object.get_bytes()[i + 2] == 0x10 {
      has_movsd_load = true
    }
  }
  inspect(has_movsd_store, content="true")
  inspect(has_movsd_load, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR scalar float memory through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([Ptr, F64], [F64])
  let milk = @milkir.Function::with_signature("float_mem_aarch64", signature)
  let ptr = milk.param(0).unwrap()
  let value = milk.param(1).unwrap()
  let loaded = milk.new_value(F64)
  let offset = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntConst(0L)), [], [offset]))
  entry.append_inst(milk.new_inst(Memory(Store(F64)), [ptr, value, offset], []))
  entry.append_inst(milk.new_inst(Memory(Load(F64)), [ptr, offset], [loaded]))
  entry.set_terminator(Return([loaded]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_str_d = false
  let mut has_ldr_d = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if plan.object.get_bytes()[i + 3] == 0xfd {
      if (plan.object.get_bytes()[i + 2] & 0x40) == 0x40 {
        has_ldr_d = true
      } else {
        has_str_d = true
      }
    }
  }
  inspect(has_str_d, content="true")
  inspect(has_ldr_d, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR vector memory through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([Ptr, V128], [])
  let milk = @milkir.Function::with_signature("vector_mem_x64", signature)
  let ptr = milk.param(0).unwrap()
  let value = milk.param(1).unwrap()
  let loaded = milk.new_value(V128)
  let offset = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntConst(0L)), [], [offset]))
  entry.append_inst(
    milk.new_inst(Memory(Store(V128)), [ptr, value, offset], []),
  )
  entry.append_inst(milk.new_inst(Memory(Load(V128)), [ptr, offset], [loaded]))
  entry.set_terminator(Return([]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_movdqu_store = false
  let mut has_movdqu_load = false
  for i in 0..<(plan.object.get_bytes().length() - 2) {
    if plan.object.get_bytes()[i] == 0xf3 &&
      plan.object.get_bytes()[i + 1] == 0x0f &&
      plan.object.get_bytes()[i + 2] == 0x7f {
      has_movdqu_store = true
    }
    if plan.object.get_bytes()[i] == 0xf3 &&
      plan.object.get_bytes()[i + 1] == 0x0f &&
      plan.object.get_bytes()[i + 2] == 0x6f {
      has_movdqu_load = true
    }
  }
  inspect(has_movdqu_store, content="true")
  inspect(has_movdqu_load, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR vector memory through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([Ptr, V128], [])
  let milk = @milkir.Function::with_signature("vector_mem_aarch64", signature)
  let ptr = milk.param(0).unwrap()
  let value = milk.param(1).unwrap()
  let loaded = milk.new_value(V128)
  let offset = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntConst(0L)), [], [offset]))
  entry.append_inst(
    milk.new_inst(Memory(Store(V128)), [ptr, value, offset], []),
  )
  entry.append_inst(milk.new_inst(Memory(Load(V128)), [ptr, offset], [loaded]))
  entry.set_terminator(Return([]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_str_q = false
  let mut has_ldr_q = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if plan.object.get_bytes()[i + 3] == 0x3d {
      if (plan.object.get_bytes()[i + 2] & 0xc0) == 0xc0 {
        has_ldr_q = true
      } else if (plan.object.get_bytes()[i + 2] & 0x80) == 0x80 {
        has_str_q = true
      }
    }
  }
  inspect(has_str_q, content="true")
  inspect(has_ldr_q, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "emit VCode regalloc through reusable x64 pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("regalloc_x64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntBinary(Add)), [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  debug_inspect(
    plan.object,
    content=(
      #|{
      #|  code: [72, 137, 248, 72, 1, 240, 195],
      #|  frame_size: 0,
      #|  func_addr_fixups: [],
      #|  call_fixups: [],
      #|  gc_safepoints: [],
      #|}
    ),
  )
}

///|
test "plan Wasm body return area through reusable JIT pipeline" {
  let milk = @milkir.Function::new_empty("wasm_return_area")
  milk.add_param(Ptr) |> ignore
  let values : Array[@milkir.Value] = []
  let entry = milk.new_block([])
  for i in 0..<9 {
    let value = milk.new_value(I64)
    milk.add_result(I64)
    entry.append_inst(
      milk.new_inst(Scalar(IntConst(i.to_int64())), [], [value]),
    )
    values.push(value)
  }
  entry.set_terminator(Return(values))
  let x64_plan = plan_wasm_body_milkir_integration_for_target(
    milk,
    @wasm_milkir.WasmValidationContext::empty(),
    X64,
  )
  inspect(x64_plan.object.get_bytes().length() > 0, content="true")
  let a64_plan = plan_wasm_body_milkir_integration_for_target(
    milk,
    @wasm_milkir.WasmValidationContext::empty(),
    AArch64,
  )
  inspect(a64_plan.object.get_bytes().length() > 0, content="true")
}

///|
test "plan MilkIR popcnt through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [I64])
  let milk = @milkir.Function::with_signature("popcnt_x64", signature)
  let value = milk.param(0).unwrap()
  let count = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntUnary(PopulationCount)), [value], [count]),
  )
  entry.set_terminator(Return([count]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_shift = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0xd3 {
      has_shift = true
    }
  }
  inspect(has_shift, content="true")
  inspect(code_contains_byte(plan.object.get_bytes(), 0xc3), content="true")
}

///|
test "plan MilkIR bitcast through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [F64])
  let milk = @milkir.Function::with_signature("bitcast_i64_f64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(Convert(Bitcast)), [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_movq_to_xmm = false
  for i in 0..<(plan.object.get_bytes().length() - 2) {
    if plan.object.get_bytes()[i] == 0x0f &&
      plan.object.get_bytes()[i + 1] == 0x6e {
      has_movq_to_xmm = true
    }
  }
  inspect(has_movq_to_xmm, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR bitcast through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([F64], [I64])
  let milk = @milkir.Function::with_signature("bitcast_f64_i64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(Convert(Bitcast)), [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_fmov_to_gpr = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if plan.object.get_bytes()[i + 2] == 0x66 &&
      plan.object.get_bytes()[i + 3] == 0x9e {
      has_fmov_to_gpr = true
    }
  }
  inspect(has_fmov_to_gpr, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR sign-extension through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [I64])
  let milk = @milkir.Function::with_signature("sext8_x64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(SignExtendFrom(8)), [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_movsx = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0x0f &&
      plan.object.get_bytes()[i + 1] == 0xbe {
      has_movsx = true
    }
  }
  inspect(has_movsx, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR sign-extension through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [I64])
  let milk = @milkir.Function::with_signature("sext32_aarch64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(SignExtendFrom(32)), [input], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_sxtw = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if (plan.object.get_bytes()[i + 1] & 0x7c) == 0x7c &&
      plan.object.get_bytes()[i + 2] == 0x40 &&
      plan.object.get_bytes()[i + 3] == 0x93 {
      has_sxtw = true
    }
  }
  inspect(has_sxtw, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR unsigned extend through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I32], [I64])
  let milk = @milkir.Function::with_signature("uextend_x64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(Convert(UnsignedExtend)), [input], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_mov32 = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0x89 {
      has_mov32 = true
    }
  }
  inspect(has_mov32, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR integer reduce through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [I32])
  let milk = @milkir.Function::with_signature("ireduce_aarch64", signature)
  let input = milk.param(0).unwrap()
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(Convert(IntReduce)), [input], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_mov_w = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if plan.object.get_bytes()[i + 3] == 0x2a {
      has_mov_w = true
    }
  }
  inspect(
    has_mov_w,
    content=(
      #|false
    ),
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR integer select through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I32, I64, I64], [I64])
  let milk = @milkir.Function::with_signature("select_x64", signature)
  let cond = milk.param(0).unwrap()
  let true_value = milk.param(1).unwrap()
  let false_value = milk.param(2).unwrap()
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(Select), [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let bytes = plan.object.get_bytes()
  inspect(code_contains_pair(bytes, 0x0f, 0x45), content="true")
  inspect(code_contains_byte(bytes, 0xc3), content="true")
}

///|
test "plan MilkIR floating point select through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I32, F64, F64], [F64])
  let milk = @milkir.Function::with_signature("select_f64_x64", signature)
  let cond = milk.param(0).unwrap()
  let true_value = milk.param(1).unwrap()
  let false_value = milk.param(2).unwrap()
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(Select), [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let bytes = plan.object.get_bytes()
  debug_inspect(
    bytes,
    content=(
      #|[
      #|  133,
      #|  255,
      #|  102,
      #|  73,
      #|  15,
      #|  126,
      #|  194,
      #|  102,
      #|  73,
      #|  15,
      #|  126,
      #|  203,
      #|  77,
      #|  15,
      #|  69,
      #|  218,
      #|  102,
      #|  73,
      #|  15,
      #|  110,
      #|  195,
      #|  195,
      #|]
    ),
  )
}

///|
test "plan MilkIR integer select through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I32, I64, I64], [I64])
  let milk = @milkir.Function::with_signature("select_aarch64", signature)
  let cond = milk.param(0).unwrap()
  let true_value = milk.param(1).unwrap()
  let false_value = milk.param(2).unwrap()
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(Select), [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  inspect(plan.object.get_bytes().length() > 0, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR floating point select through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I32, F64, F64], [F64])
  let milk = @milkir.Function::with_signature("select_f64_aarch64", signature)
  let cond = milk.param(0).unwrap()
  let true_value = milk.param(1).unwrap()
  let false_value = milk.param(2).unwrap()
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(Select), [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  inspect(plan.object.get_bytes().length() > 0, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR signed integer division through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("sdiv64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let quotient = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntBinary(SignedDiv)), [lhs, rhs], [quotient]),
  )
  entry.set_terminator(Return([quotient]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_cqo = false
  let mut has_div_opcode = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0x48 &&
      plan.object.get_bytes()[i + 1] == 0x99 {
      has_cqo = true
    }
  }
  for byte in plan.object.get_bytes() {
    if byte == 0xf7 {
      has_div_opcode = true
    }
  }
  inspect(has_cqo, content="true")
  inspect(has_div_opcode, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR signed integer remainder through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("srem64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let rem = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntBinary(SignedRem)), [lhs, rhs], [rem]),
  )
  entry.set_terminator(Return([rem]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_cqo = false
  let mut has_div_opcode = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0x48 &&
      plan.object.get_bytes()[i + 1] == 0x99 {
      has_cqo = true
    }
  }
  for byte in plan.object.get_bytes() {
    if byte == 0xf7 {
      has_div_opcode = true
    }
  }
  inspect(has_cqo, content="true")
  inspect(has_div_opcode, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR signed multiply-high through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("smulh64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let high = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntBinary(SignedMulHigh)), [lhs, rhs], [high]),
  )
  entry.set_terminator(Return([high]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_mul_opcode = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0xf7 &&
      (plan.object.get_bytes()[i + 1] & 0x38) == 0x28 {
      has_mul_opcode = true
    }
  }
  inspect(has_mul_opcode, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR integer not through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [I64])
  let milk = @milkir.Function::with_signature("bnot64", signature)
  let input = milk.param(0).unwrap()
  let inverted = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Scalar(IntUnary(Not)), [input], [inverted]))
  entry.set_terminator(Return([inverted]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_not_opcode = false
  for byte in plan.object.get_bytes() {
    if byte == 0xf7 {
      has_not_opcode = true
    }
  }
  inspect(has_not_opcode, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR integer compare through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I32])
  let milk = @milkir.Function::with_signature("icmp_slt64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let is_less = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntCompare(Slt)), [lhs, rhs], [is_less]),
  )
  entry.set_terminator(Return([is_less]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_setcc = false
  let mut has_movzx = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0x0f &&
      plan.object.get_bytes()[i + 1] == 0x9c {
      has_setcc = true
    }
    if plan.object.get_bytes()[i] == 0x0f &&
      plan.object.get_bytes()[i + 1] == 0xb6 {
      has_movzx = true
    }
  }
  inspect(has_setcc, content="true")
  inspect(has_movzx, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR integer shift through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("shl64", signature)
  let value = milk.param(0).unwrap()
  let count = milk.param(1).unwrap()
  let shifted = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntBinary(ShiftLeft)), [value, count], [shifted]),
  )
  entry.set_terminator(Return([shifted]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_shift_cl = false
  for byte in plan.object.get_bytes() {
    if byte == 0xd3 {
      has_shift_cl = true
    }
  }
  inspect(has_shift_cl, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR integer rotate through reusable JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("rotr64", signature)
  let value = milk.param(0).unwrap()
  let count = milk.param(1).unwrap()
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntBinary(RotateRight)), [value, count], [rotated]),
  )
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let mut has_rotate_cl = false
  for i in 0..<(plan.object.get_bytes().length() - 1) {
    if plan.object.get_bytes()[i] == 0xd3 &&
      (plan.object.get_bytes()[i + 1] & 0x38) == 0x08 {
      has_rotate_cl = true
    }
  }
  inspect(has_rotate_cl, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="195",
  )
}

///|
test "plan MilkIR integer ctz through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [I64])
  let milk = @milkir.Function::with_signature("ctz64", signature)
  let value = milk.param(0).unwrap()
  let trailing = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntUnary(CountTrailingZeros)), [value], [trailing]),
  )
  entry.set_terminator(Return([trailing]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_rbit = false
  let mut has_clz = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if plan.object.get_bytes()[i + 2] == 0xc0 &&
      plan.object.get_bytes()[i + 3] == 0xda {
      if (plan.object.get_bytes()[i + 1] & 0x10) == 0 {
        has_rbit = true
      } else {
        has_clz = true
      }
    }
  }
  inspect(has_rbit, content="true")
  inspect(has_clz, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR integer clz through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [I64])
  let milk = @milkir.Function::with_signature("clz64_x64", signature)
  let value = milk.param(0).unwrap()
  let leading = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntUnary(CountLeadingZeros)), [value], [leading]),
  )
  entry.set_terminator(Return([leading]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let bytes = plan.object.get_bytes()
  inspect(code_contains_pair(bytes, 0x0f, 0xbd), content="true")
  inspect(code_contains_byte(bytes, 0xc3), content="true")
}

///|
test "plan MilkIR integer ctz through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64], [I64])
  let milk = @milkir.Function::with_signature("ctz64_x64", signature)
  let value = milk.param(0).unwrap()
  let trailing = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntUnary(CountTrailingZeros)), [value], [trailing]),
  )
  entry.set_terminator(Return([trailing]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  let bytes = plan.object.get_bytes()
  inspect(code_contains_pair(bytes, 0x0f, 0xbd), content="true")
  inspect(code_contains_byte(bytes, 0xc3), content="true")
}

///|
test "plan MilkIR unsigned multiply-high through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("umulh64", signature)
  let lhs = milk.param(0).unwrap()
  let rhs = milk.param(1).unwrap()
  let high = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntBinary(UnsignedMulHigh)), [lhs, rhs], [high]),
  )
  entry.set_terminator(Return([high]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_umulh = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if (plan.object.get_bytes()[i + 1] & 0x7c) == 0x7c &&
      (plan.object.get_bytes()[i + 2] & 0xc0) == 0xc0 &&
      plan.object.get_bytes()[i + 3] == 0x9b {
      has_umulh = true
    }
  }
  inspect(has_umulh, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR rotate-right through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("rotr64_aarch64", signature)
  let value = milk.param(0).unwrap()
  let count = milk.param(1).unwrap()
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntBinary(RotateRight)), [value, count], [rotated]),
  )
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_rorv = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if (plan.object.get_bytes()[i + 1] & 0x2c) == 0x2c &&
      (plan.object.get_bytes()[i + 2] & 0xc0) == 0xc0 &&
      plan.object.get_bytes()[i + 3] == 0x9a {
      has_rorv = true
    }
  }
  inspect(has_rorv, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "plan MilkIR rotate-left through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::with_signature("rotl64_aarch64", signature)
  let value = milk.param(0).unwrap()
  let count = milk.param(1).unwrap()
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Scalar(IntBinary(RotateLeft)), [value, count], [rotated]),
  )
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, AArch64)
  let mut has_rorv = false
  for i in 0..<(plan.object.get_bytes().length() - 3) {
    if (plan.object.get_bytes()[i + 1] & 0x2c) == 0x2c &&
      (plan.object.get_bytes()[i + 2] & 0xc0) == 0xc0 &&
      plan.object.get_bytes()[i + 3] == 0x9a {
      has_rorv = true
    }
  }
  inspect(has_rorv, content="true")
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 4],
    content="192",
  )
  inspect(
    plan.object.get_bytes()[plan.object.get_bytes().length() - 1],
    content="214",
  )
}

///|
test "native runtime cstring encoding lives in wasmoon_jit" {
  let encoded = make_cstring("wasi")
  inspect(encoded.length(), content="5")
  inspect(encoded[0].to_int(), content="119")
  inspect(encoded[1].to_int(), content="97")
  inspect(encoded[2].to_int(), content="115")
  inspect(encoded[3].to_int(), content="105")
  inspect(encoded[4].to_int(), content="0")
}

///|
test "reference encoding helpers roundtrip JIT values" {
  inspect(is_null_ref(encode_null_ref()), content="true")
  debug_inspect(decode_funcref_idx(encode_funcref_idx(7)), content="Some(7)")
  let tagged = tag_funcref_ptr(0x1000L)
  inspect(is_funcref_ptr(tagged), content="true")
  inspect(untag_funcref_ptr(tagged), content="4096")
  debug_inspect(decode_externref(encode_externref(11)), content="Some(11)")
  debug_inspect(decode_gc_heap_ref(encode_gc_heap_ref(3)), content="Some(3)")
  debug_inspect(decode_gc_heap_ref(encode_null_ref()), content="None")
}

///|
test "VMContext reusable ABI layout matches JIT fixed prefix" {
  let layout = vmcontext_layout()
  inspect(layout.memory0_offset, content="0")
  inspect(layout.memory0_base_offset, content="8")
  inspect(layout.memory0_size_offset, content="16")
  inspect(layout.func_table_offset, content="24")
  inspect(layout.table0_base_offset, content="32")
  inspect(layout.table0_elements_offset, content="40")
  inspect(layout.globals_offset, content="48")
  inspect(layout.tables_offset, content="56")
  inspect(layout.table_count_offset, content="64")
  inspect(layout.func_count_offset, content="68")
  inspect(layout.table_sizes_offset, content="72")
  inspect(layout.table_max_sizes_offset, content="80")
  inspect(layout.memories_offset, content="88")
  inspect(layout.memory_count_offset, content="96")
  inspect(layout.debug_current_func_idx_offset, content="100")
  inspect(layout.gc_heap_ptr_offset, content="104")
  inspect(layout.gc_heap_limit_offset, content="112")
  inspect(layout.gc_heap_offset, content="120")
  inspect(layout.pointer_stride, content="8")
  inspect(layout.global_value_stride, content="16")
  inspect(layout.table_entry_value_offset, content="0")
  inspect(layout.table_entry_stride, content="16")
  inspect(layout.func_table_entry_stride, content="8")
  let memory = memory_descriptor_layout()
  inspect(memory.base_offset, content="0")
  inspect(memory.current_length_offset, content="8")
}
