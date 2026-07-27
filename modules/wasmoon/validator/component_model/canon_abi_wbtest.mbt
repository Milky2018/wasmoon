///|
test "canon lift only requires realloc for values written into core memory" {
  let scalar_params : Array[@component.Param] = []
  for i in 0..<17 {
    scalar_params.push({ label: "p\{i}", ty: Prim(U32) })
  }
  let cases : Array[(String, @component.FuncType)] = [
    (
      "string-result",
      { is_async: false, params: [], result: Some(Prim(String)) },
    ),
    (
      "string-parameter",
      {
        is_async: false,
        params: [{ label: "value", ty: Prim(String) }],
        result: None,
      },
    ),
    (
      "indirect-parameters",
      { is_async: false, params: scalar_params, result: None },
    ),
  ]
  let results = []
  for case in cases {
    let (label, func_type) = case
    results.push((label, functype_needs_realloc_for_lift(func_type, [])))
  }
  debug_inspect(
    results,
    content=(
      #|[
      #|  ("string-result", false),
      #|  ("string-parameter", true),
      #|  ("indirect-parameters", true),
      #|]
    ),
  )
}

///|
test "canon lower only requires realloc for values written into core memory" {
  let cases : Array[(String, @component.FuncType)] = [
    (
      "string-parameter",
      {
        is_async: false,
        params: [{ label: "value", ty: Prim(String) }],
        result: None,
      },
    ),
    (
      "string-result",
      { is_async: false, params: [], result: Some(Prim(String)) },
    ),
  ]
  let results = []
  for case in cases {
    let (label, func_type) = case
    results.push((label, functype_needs_realloc_for_lower(func_type, [])))
  }
  debug_inspect(
    results,
    content="[(\"string-parameter\", false), (\"string-result\", true)]",
  )
}
