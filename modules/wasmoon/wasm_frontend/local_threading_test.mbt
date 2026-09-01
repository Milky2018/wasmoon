///|
/// How many locals a control merge carries (#486 item 1).
///
/// The frontend used to give every merge one parameter per local, so a function
/// with L locals and M merges built L*M merge parameters regardless of what the
/// merges did with them. These pin the property that replaced it: a merge
/// carries the locals its region writes and nothing else, so the count follows
/// the writes instead of the product.
///
/// The counts here are of parameters the translator emits, before any
/// optimization. That is the number that matters for #486, because it is what
/// the translator has to build and hold before an optimizer ever sees it.

///|
fn count_block_params(func : @milkir.Function) -> Int {
  let mut total = 0
  for block in func.blocks {
    total = total + block.params.length()
  }
  total
}

///|
/// A function of `num_locals` i32 locals whose body is `num_merges` sequential
/// `if`s, each writing the first `written_per_merge` of them. The locals are
/// the function's parameters, which is what the translator threads.
fn locals_by_merges(
  num_locals : Int,
  num_merges : Int,
  written_per_merge : Int,
) -> @types.Module {
  let params : Array[@types.ValueType] = []
  for _ in 0..<num_locals {
    params.push(I32)
  }
  let body : Array[@types.Instruction] = []
  for _ in 0..<num_merges {
    let then_body : Array[@types.Instruction] = []
    for i in 0..<written_per_merge {
      then_body.push(I32Const(1))
      then_body.push(LocalSet(i))
    }
    body.push(LocalGet(0))
    body.push(If(Empty, then_body, []))
  }
  @types.Module::simple(params, [], body, "run")
}

///|
/// Merge parameters beyond what the function's own entry block carries, so the
/// signature contributes nothing to the comparison.
fn merge_params(num_locals : Int, num_merges : Int, written : Int) -> Int raise {
  let baseline = count_block_params(
    translate_function(native_test_env(), locals_by_merges(num_locals, 0, 0), 0),
  )
  let func = translate_function(
    native_test_env(),
    locals_by_merges(num_locals, num_merges, written),
    0,
  )
  @wasm_milkir.verify_function(func)
  count_block_params(func) - baseline
}

///|
test "br_if passes block arguments without a taken trampoline" {
  let mod_ = @types.Module::simple(
    [I32],
    [I32],
    [Block(Value(I32), [I32Const(7), LocalGet(0), BrIf(0), Drop, I32Const(9)])],
    "direct_br_if_args",
  )
  let func = translate_function(native_test_env(), mod_, 0)
  @wasm_milkir.verify_function(func)
  let text = func.print()
  inspect(text.contains("branch "), content="true")
  inspect(text.contains("brnz "), content="false")
}

///|
/// 32 locals across 24 merges, one local written per merge. Threading every
/// local would build 32 * 24 = 768 parameters; only the written one needs to
/// cross each merge, so 24 do.
test "sparse writes cost one merge parameter each, not the product" {
  inspect(merge_params(32, 24, 1), content="24")
}

///|
/// The same shape with every local written keeps the full product, which is
/// the point: the parameters that disappeared were the ones no edge could
/// disagree about, not ones the merge needed.
test "dense writes still cost the full product" {
  inspect(merge_params(32, 24, 32), content="768")
}

///|
/// Growth in the number of merges stays linear in what they write rather than
/// in the local count, which is the sub-product property #486 asks for.
test "merge parameters track writes, not locals times merges" {
  inspect(merge_params(64, 8, 1), content="8")
  inspect(merge_params(64, 16, 1), content="16")
  inspect(merge_params(64, 16, 2), content="32")
}

///|
/// A merge whose region writes nothing carries nothing: the value in hand is
/// already correct on every edge into the continuation.
test "a region that writes no local carries no local" {
  inspect(merge_params(32, 24, 0), content="0")
}

///|
/// A write buried in a nested region still reaches every enclosing merge,
/// since a branch out of the nest can carry it past all of them.
test "a nested write reaches every enclosing merge" {
  let inner : Array[@types.Instruction] = [I32Const(1), LocalSet(3)]
  let mod_ = @types.Module::simple(
    [I32, I32, I32, I32],
    [],
    [Block(Empty, [Block(Empty, [Loop(Empty, inner)])])],
    "nested",
  )
  let func = translate_function(native_test_env(), mod_, 0)
  @wasm_milkir.verify_function(func)
  let baseline = count_block_params(
    translate_function(
      native_test_env(),
      @types.Module::simple([I32, I32, I32, I32], [], [], "nested"),
      0,
    ),
  )
  // One parameter on each of the two block continuations and the loop header,
  // for the single local written at the bottom.
  inspect(count_block_params(func) - baseline, content="3")
}

///|
/// An `if` merges both arms, so a local either arm writes has to cross even
/// though no single arm writes both.
test "an if carries what either arm writes" {
  let mod_ = @types.Module::simple(
    [I32, I32, I32],
    [],
    [
      LocalGet(0),
      If(Empty, [I32Const(1), LocalSet(1)], [I32Const(2), LocalSet(2)]),
    ],
    "either_arm",
  )
  let func = translate_function(native_test_env(), mod_, 0)
  @wasm_milkir.verify_function(func)
  let baseline = count_block_params(
    translate_function(
      native_test_env(),
      @types.Module::simple([I32, I32, I32], [], [], "either_arm"),
      0,
    ),
  )
  inspect(count_block_params(func) - baseline, content="2")
}
