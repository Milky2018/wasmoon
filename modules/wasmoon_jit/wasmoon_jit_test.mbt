///|
test "resolve runtime helper relocations into linked code" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Call("wasmoon.runtime.helper")))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol("wasmoon.runtime.helper", 4096L)
  let linked = try! link_code_object(object, resolver)
  inspect(linked.code.length(), content="5")
  inspect(linked.runtime_relocations.length(), content="1")
  inspect(linked.block_fixups.length(), content="0")
}

///|
test "wrap linked code as cwasm artifact" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let resolver = RuntimeSymbolResolver::new()
  let linked = try! link_code_object(object, resolver)
  let artifact = CwasmArtifact::from_linked_code(linked, 7)
  inspect(artifact.functions.length(), content="1")
  inspect(artifact.manifest().length(), content="5")
}

///|
test "plan Wasmoon JIT integration without leaking into machv_emit" {
  let milk = @milkir.Function::new("entry", @milkir.Signature::new([], []))
  let mach = @machv.Function::new("entry")
  let entry = mach.new_block()
  entry.append(mach.new_inst(Return))
  let plan = try! plan_integration_for_target(milk, mach, X64)
  inspect(plan.entry_symbol, content="entry")
  debug_inspect(plan.target, content="X64")
  inspect(plan.native_glue.length(), content="6")
  inspect(plan.object.debug_entries.length(), content="1")
  inspect(plan.object.code.length(), content="1")
}

///|
test "plan MilkIR through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("add64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="add64")
  debug_inspect(plan.object.code, content="[72, 137, 240, 72, 1, 248, 195]")
  inspect(plan.object.debug_entries.length(), content="2")
}

///|
test "plan MilkIR floating point through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([F64, F64], [F64])
  let milk = @milkir.Function::new("fadd64", signature)
  let lhs = milk.new_value(F64)
  let rhs = milk.new_value(F64)
  let sum = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="fadd64")
  debug_inspect(
    plan.object.code,
    content="[242, 15, 16, 208, 242, 15, 88, 209, 195]",
  )
  inspect(plan.object.debug_entries.length(), content="2")
}

///|
test "wrap reusable JIT plan as cwasm artifact" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("add64_artifact", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  let artifact = try! CwasmArtifact::from_jit_plan(
    plan,
    RuntimeSymbolResolver::new(),
    3,
  )
  inspect(artifact.functions.length(), content="1")
  inspect(artifact.functions[0].function_index, content="3")
  inspect(artifact.code.length() > 0, content="true")
  inspect(artifact.debug_entries.length(), content="2")
}
