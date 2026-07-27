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

///|
test "host instance function import matching ignores parameter labels" {
  let expected : FuncType = {
    is_async: false,
    params: [{ label: "expected-name", ty: Prim(U32) }],
    result: None,
  }
  let actual = ComponentFunc::Host(
    {
      is_async: false,
      params: [{ label: "producer-name", ty: Prim(U32) }],
      result: None,
    },
    [],
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
  require_component_func_type(
    "accept-renamed-parameter",
    0,
    [Some(FuncType(expected))],
    actual,
  )
}

///|
test "outer type aliases preserve referenced type context" {
  let source_types : Array[TypeDef?] = [
    Some(Tuple([Prim(U32), Prim(U64)])),
    Some(FuncType({ is_async: false, params: [], result: Some(TypeIdx(0)) })),
  ]
  let local_types : Array[TypeDef?] = []
  materialize_outer_type(1, source_types, local_types)
  debug_inspect(
    local_types,
    content=(
      #|[
      #|  Some(FuncType({ is_async: false, params: [], result: Some(TypeIdx(1)) })),
      #|  Some(([Prim(U32), Prim(U64)])),
      #|]
    ),
  )
}
