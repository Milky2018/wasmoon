///|
/// Bounded leaf candidates from the validated module, using the ordinary
/// embedding/linker environment. The optimizer admits scalar/vector IR by cost
/// plus small GC reads and constructors. Semantic entry polls are preserved;
/// other calls and mutations are excluded.
/// Imports are excluded.
pub fn TranslationContext::scalar_callees(
  self : TranslationContext,
  module_ : @types.Module,
) -> Map[Int32, @milkir.Function] {
  let result : Map[Int32, @milkir.Function] = Map([])
  for index, code in module_.codes {
    // Bound translation work structurally, then let the IR cost/effect model
    // decide eligibility. Do not maintain an opcode or integer-only whitelist.
    if code.locals.length() > 8 ||
      code.body.length() > 24 ||
      code.body.any(instruction => {
        instruction
        is (Block(_, _) | Loop(_, _) | If(_, _, _) | TryTable(_, _, _))
      }) {
      continue
    }
    let ty = module_.validated_func_type_at(module_.funcs[index])
    if ty.results.length() != 1 {
      continue
    }
    let linked_index = self.func_base + self.num_imports + index
    result[linked_index] = translate_function_body(
      self,
      "scalar_callee_\{linked_index}",
      ty,
      code.locals,
      code.body,
    )
  }
  result
}
