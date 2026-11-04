///|
/// Count nested conditional bodies against the same fixed translation
/// allowance. Loops, explicit block scopes and exception regions remain
/// outside the bounded checked-leaf collection.
fn count_leaf_body(
  body : ReadOnlyArray[@types.Instruction],
  budget : Int32,
) -> Int32 {
  let mut remaining = budget
  for instruction in body {
    if remaining <= 0 {
      return -1
    }
    remaining -= 1
    match instruction {
      If(_, yes, no) => {
        remaining = count_leaf_body(yes, remaining)
        if remaining < 0 {
          return -1
        }
        remaining = count_leaf_body(no, remaining)
        if remaining < 0 {
          return -1
        }
      }
      Block(_, _) | Loop(_, _) | TryTable(_, _, _) => return -1
      _ => ()
    }
  }
  remaining
}

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
    if code.locals.length() > 8 || code.body.length() > 24 {
      continue
    }
    let ty = module_.validated_func_type_at(module_.funcs[index])
    let returns_value = ty.results.length() == 1 &&
      !code.body.any(instruction => {
        instruction
        is (Block(_, _) | Loop(_, _) | If(_, _, _) | TryTable(_, _, _))
      })
    let guards_only = ty.results.is_empty() &&
      ty.params is [I32, I32, I32] &&
      code.body.any(instruction => instruction is If(_, _, _)) &&
      count_leaf_body(code.body, 16) >= 0
    if !returns_value && !guards_only {
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
