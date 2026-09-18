///|
test "wasm_core root exposes construction entrypoints" {
  let empty = @wasm_core.empty_module()
  inspect(empty.codes.length(), content="0")
  let ty = @wasm_core.func_type([I32], [I64])
  inspect(ty.params.length(), content="1")
  inspect(ty.results.length(), content="1")
  let subtype = @wasm_core.func_subtype([I32], [I64])
  inspect(subtype.composite is Func(_), content="true")
  let mod_ = @wasm_core.simple_module([I32], [I64], [I64Const(1L)], "f")
  inspect(mod_.exports.length(), content="1")
  inspect(mod_.func_type_at(0).unwrap().results.length(), content="1")
}
