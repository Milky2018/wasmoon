///|
test "canonical core signatures model indirect parameters and results" {
  let scalar_params : Array[Param] = []
  for i in 0..<17 {
    scalar_params.push({ label: "p\{i}", ty: Prim(U32) })
  }
  let record_type = Some(
    Record([{ label: "x", ty: Prim(U32) }, { label: "name", ty: Prim(String) }]),
  )
  debug_inspect(
    (
      canonical_lift_core_func_type(
        {
          is_async: false,
          params: [{ label: "value", ty: Prim(String) }],
          result: Some(Prim(String)),
        },
        [],
        I32,
      ),
      canonical_lower_core_func_type(
        {
          is_async: false,
          params: [{ label: "value", ty: Prim(String) }],
          result: Some(Prim(String)),
        },
        [],
        I32,
      ),
      canonical_lower_core_func_type(
        { is_async: false, params: scalar_params, result: None },
        [],
        I64,
      ),
      canonical_lower_core_func_type(
        { is_async: false, params: [], result: Some(TypeIdx(0)) },
        [record_type],
        I64,
      ),
    ),
    content=(
      #|(
      #|  Some({ params: [I32, I32], results: [I32] }),
      #|  Some({ params: [I32, I32, I32], results: [] }),
      #|  Some({ params: [I64], results: [] }),
      #|  Some({ params: [I64], results: [] }),
      #|)
    ),
  )
}
