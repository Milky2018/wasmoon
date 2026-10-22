///|
/// Small integer bodies from this validated module, using the same embedding
/// and linker environment as ordinary translation. Imported callees are never
/// supplied. The optimizer separately rejects any emitted poll or other effect.
pub fn TranslationContext::scalar_callees(
  self : TranslationContext,
  module_ : @types.Module,
) -> Map[Int32, @milkir.Function] {
  let result : Map[Int32, @milkir.Function] = Map([])
  for index, code in module_.codes {
    if !code.locals.is_empty() || code.body.length() > 8 {
      continue
    }
    let ty = module_.validated_func_type_at(module_.funcs[index])
    if ty.results.length() != 1 || !(ty.results[0] is (I32 | I64)) {
      continue
    }
    let mut eligible = true
    for parameter in ty.params {
      if !(parameter is (I32 | I64)) {
        eligible = false
      }
    }
    for instruction in code.body {
      match instruction {
        LocalGet(_)
        | I32Const(_)
        | I64Const(_)
        | I32WrapI64
        | I64ExtendI32S
        | I64ExtendI32U
        | I32And
        | I64And
        | I32Add
        | I64Add
        | I32Sub
        | I64Sub
        | I32Mul
        | I64Mul => ()
        _ => eligible = false
      }
    }
    if eligible {
      let linked_index = self.func_base + self.num_imports + index
      result[linked_index] = translate_function_body(
        self,
        "scalar_callee_\{linked_index}",
        ty,
        code.locals,
        code.body,
      )
    }
  }
  result
}
