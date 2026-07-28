///|
test "Preview 3 socket errors follow stable 0.3 variants" {
  debug_inspect(
    [
      (
        "EACCES",
        preview3_socket_error_case(@wasi.Errno::Acces.to_i32()),
        preview3_socket_error_code(0),
      ),
      (
        "EPIPE",
        preview3_socket_error_case(@wasi.Errno::Pipe.to_i32()),
        preview3_socket_error_code(10),
      ),
      ("other", preview3_socket_error_case(-1), preview3_socket_error_code(14)),
    ],
    content=(
      #|[
      #|  ("EACCES", 0, Variant(1, Some(Variant(0, None)))),
      #|  ("EPIPE", 10, Variant(1, Some(Variant(10, None)))),
      #|  ("other", 14, Variant(1, Some(Variant(14, Some(Variant(0, None)))))),
      #|]
    ),
  )
}

///|
test "Preview 3 lookup errors include a structured other case" {
  debug_inspect(
    [preview3_lookup_error(0), preview3_lookup_error(5)],
    content=(
      #|[
      #|  Variant(1, Some(Variant(0, None))),
      #|  Variant(1, Some(Variant(5, Some(Variant(0, None))))),
      #|]
    ),
  )
}
