///|
test "stream payload layout uses canonical variant memory layout" {
  let types : Array[TypeDef?] = [
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Result(None, Some(TypeIdx(0)))),
    Some(Option(Prim(U64))),
  ]
  debug_inspect(
    [
      stream_payload_info(Some(TypeIdx(1)), types),
      stream_payload_info(Some(TypeIdx(2)), types),
    ],
    content="[(2, None), (16, None)]",
  )
}
