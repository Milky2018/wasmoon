///|
test "stable Preview 3 contracts preserve direct-future boundaries" {
  debug_inspect(
    [
      ("exit-with-code", preview3_func("wasi:cli@0.3.0/exit", "exit-with-code")),
      ("stdout", preview3_func("wasi:cli@0.3.0/stdout", "write-via-stream")),
      (
        "filesystem-write",
        preview3_func(
          "wasi:filesystem@0.3.0/types", "[method]descriptor.write-via-stream",
        ),
      ),
      (
        "filesystem-read-directory",
        preview3_func(
          "wasi:filesystem@0.3.0/types", "[method]descriptor.read-directory",
        ),
      ),
      (
        "tcp-send",
        preview3_func("wasi:sockets@0.3.0/types", "[method]tcp-socket.send"),
      ),
    ],
    content=(
      #|[
      #|  (
      #|    "exit-with-code",
      #|    {
      #|      is_async: false,
      #|      params: [{ label: "status-code", ty: Prim(U8) }],
      #|      result: None,
      #|    },
      #|  ),
      #|  (
      #|    "stdout",
      #|    {
      #|      is_async: false,
      #|      params: [{ label: "data", ty: TypeIdx(88) }],
      #|      result: Some(TypeIdx(94)),
      #|    },
      #|  ),
      #|  (
      #|    "filesystem-write",
      #|    {
      #|      is_async: false,
      #|      params: [
      #|        { label: "self", ty: TypeIdx(23) },
      #|        { label: "data", ty: TypeIdx(24) },
      #|        { label: "offset", ty: TypeIdx(8) },
      #|      ],
      #|      result: Some(TypeIdx(26)),
      #|    },
      #|  ),
      #|  (
      #|    "filesystem-read-directory",
      #|    {
      #|      is_async: false,
      #|      params: [{ label: "self", ty: TypeIdx(23) }],
      #|      result: Some(TypeIdx(31)),
      #|    },
      #|  ),
      #|  (
      #|    "tcp-send",
      #|    {
      #|      is_async: false,
      #|      params: [
      #|        { label: "self", ty: TypeIdx(55) },
      #|        { label: "data", ty: TypeIdx(59) },
      #|      ],
      #|      result: Some(TypeIdx(60)),
      #|    },
      #|  ),
      #|]
    ),
  )
}
