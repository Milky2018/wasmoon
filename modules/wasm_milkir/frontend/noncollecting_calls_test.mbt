///|
test "noncollecting direct call proofs are transitive local and poll-specific" {
  let module_ = @types.Module::simple([], [I32], [I32Const(42)], "leaf")
  module_.imports.push({ mod_name: "host", name: "value", desc: Func(0), })
  module_.types.push(
    @types.SubType::simple(
      Struct({ fields: [{ storage_type: Val(I32), mutable: true, }], }),
    ),
  )
  module_.type_rec_groups.push(1)
  module_.globals.push({
    type_: { value_type: I32, mutable: true, },
    init: [I32Const(0)],
  })
  let bodies : Array[ReadOnlyArray[@types.Instruction]] = [
    [Call(1)],
    [Call(0)],
    [Call(3)],
    [Call(5)],
    [I32Const(7), StructNew(1), Drop, I32Const(42)],
    [Call(6)],
    [I32Const(1), If(Value(I32), [Call(2)], [I32Const(0)])],
    [I32Const(7), GlobalSet(0), I32Const(42)],
    [Call(9)],
  ]
  for body in bodies {
    module_.funcs.push(0)
    module_.codes.push({ locals: [], body, })
  }
  for polling in [false, true] {
    let translation = @frontend.translation_context_from_module(
      module_,
      { ..native_test_env(), cancellation_safepoints: polling, },
      func_base=10,
      import_remap=[100],
    )
    let context = @frontend.wasm_validation_context(translation)
    for index in [11, 12, 18] {
      assert_eq(context.function_is_noncollecting(index), !polling)
      assert_eq(context.function_is_readonly(index), !polling)
    }
    for index in [19, 20] {
      assert_eq(context.function_is_noncollecting(index), !polling)
      assert_false(context.function_is_readonly(index))
    }
    for index in [-1, 0, 13, 14, 15, 16, 17, 100] {
      assert_false(context.function_is_noncollecting(index))
    }
  }
}

///|
test "noncollecting summaries conservatively reject indirect tail and unknown operations" {
  let bodies : Array[ReadOnlyArray[@types.Instruction]] = [
    [RefFunc(0), CallRef(0)],
    [I32Const(0), CallIndirect(0, 0)],
    [ReturnCall(0)],
    [RefNull(ExternRef), AnyConvertExtern, Drop, I32Const(42)],
  ]
  for body in bodies {
    let module_ = @types.Module::simple([], [I32], body, "unsupported")
    let translation = @frontend.translation_context_from_module(
      module_,
      native_test_env(),
    )
    assert_false(
      @frontend.wasm_validation_context(translation).function_is_noncollecting(
        0,
      ),
    )
  }
}
