///|
test "host instance function imports require the exact component signature" {
  let expected : FuncType = {
    is_async: false,
    params: [{ label: "value", ty: Prim(U32) }],
    result: Some(Prim(U32)),
  }
  let actual_type : FuncType = {
    is_async: false,
    params: [{ label: "value", ty: Prim(U32) }],
    result: Some(Prim(U64)),
  }
  let actual = ComponentFunc::Host(actual_type, [], fn(
    _args : Array[ComponentValue],
    _table : ResourceTable,
  ) -> Array[ComponentValue] raise ComponentRuntimeError {
    if _args.length() > 0 {
      raise HostCallError("not called by this test")
    }
    []
  })
  try
    require_component_func_type(
      "convert",
      0,
      [Some(FuncType(expected))],
      actual,
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|ImportTypeMismatch("instance function export signature mismatch: convert")
        ),
      )
  } noraise {
    _ => fail("expected mismatched host function signature to be rejected")
  }
}

///|
test "host instance function imports accept structurally equal type spaces" {
  let expected_types : Array[TypeDef?] = [
    Some(List(Prim(U8))),
    Some(FuncType({ is_async: false, params: [], result: Some(TypeIdx(0)) })),
  ]
  let actual_types : Array[TypeDef?] = [Some(List(Prim(U8)))]
  let actual = ComponentFunc::Host(
    { is_async: false, params: [], result: Some(TypeIdx(0)) },
    actual_types,
    fn(
      _args : Array[ComponentValue],
      _table : ResourceTable,
    ) -> Array[ComponentValue] raise ComponentRuntimeError {
      if _args.length() > 0 {
        raise HostCallError("not called by this test")
      }
      []
    },
  )
  require_component_func_type("read", 1, expected_types, actual)
}
