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

///|
test "canonical memory address type follows the selected memory" {
  let memory32 : @types.MemoryType = {
    limits: { min: 1L, max: None },
    is_memory64: false,
    page_size_log2: 16,
  }
  let memory64 : @types.MemoryType = {
    limits: { min: 1L, max: None },
    is_memory64: true,
    page_size_log2: 16,
  }
  debug_inspect(
    [
      canon_address_type([Memory(0)], [Some(memory32)]),
      canon_address_type([Memory(0)], [Some(memory64)]),
    ],
    content="[I32, I64]",
  )
}

///|
test "memory64 canonical realloc requires an i64 address signature" {
  let memory64 : @types.MemoryType = {
    limits: { min: 1L, max: None },
    is_memory64: true,
    page_size_log2: 16,
  }
  let func_type : @component.FuncType = {
    is_async: false,
    params: [{ label: "value", ty: Prim(String) }],
    result: None,
  }
  let invalid_realloc : @types.FuncType = {
    params: [I32, I32, I32, I32],
    results: [I32],
  }
  let result = try {
    validate_canon(
      Lower(0, [Memory(0), Realloc(0)]),
      [],
      [],
      0,
      [Some(memory64)],
      [Some(invalid_realloc)],
      [Some(func_type)],
    )
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(
    result,
    content=(
      #|CanonCoreFuncTypeMismatch("canonical option `realloc` uses a core function with an incorrect signature")
    ),
  )
}
