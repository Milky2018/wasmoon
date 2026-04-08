///|
test "runtime helper fixup index: jit libcall roundtrip" {
  let idx = jit_libcall_fixup_idx(@instr.MemoryFillMem0)
  inspect(idx < 0, content="true")
  inspect(resolve_runtime_func_fixup_idx(idx) is Some(_), content="true")
}

///|
test "runtime helper fixup index: gc libcall roundtrip" {
  let idx = gc_libcall_fixup_idx(@instr.ArrayInitElem)
  inspect(idx < 0, content="true")
  inspect(resolve_runtime_func_fixup_idx(idx) is Some(_), content="true")
}

///|
test "runtime helper fixup index: exception libcall roundtrip" {
  let idx = exception_libcall_fixup_idx(@instr.ThrowTag)
  inspect(idx < 0, content="true")
  inspect(resolve_runtime_func_fixup_idx(idx) is Some(_), content="true")
}
