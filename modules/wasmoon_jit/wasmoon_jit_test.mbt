///|
test "resolve runtime helper relocations into linked code" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Call("wasmoon.runtime.helper")))
  let object = try! @machv_emit.emit_function(func)
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol("wasmoon.runtime.helper", 4096L)
  let linked = try! link_code_object(object, resolver)
  inspect(linked.runtime_relocations.length(), content="1")
  inspect(linked.block_fixups.length(), content="0")
}

///|
test "wrap linked code as cwasm artifact" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function(func)
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
  let plan = try! plan_integration(milk, mach)
  inspect(plan.entry_symbol, content="entry")
  inspect(plan.native_glue.length(), content="6")
  inspect(plan.object.debug_entries.length(), content="1")
}
