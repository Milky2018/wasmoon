///|
test "Preview 3 filesystem errno indices follow the Preview 3 WIT order" {
  debug_inspect(
    [
      ("ENOENT", preview3_filesystem_error_index(@wasi.Errno::NoEnt.to_i32())),
      ("ENOTDIR", preview3_filesystem_error_index(@wasi.Errno::NotDir.to_i32())),
      ("EPERM", preview3_filesystem_error_index(@wasi.Errno::Perm.to_i32())),
      ("EROFS", preview3_filesystem_error_index(@wasi.Errno::ROFS.to_i32())),
    ],
    content=(
      #|[("ENOENT", 19), ("ENOTDIR", 23), ("EPERM", 30), ("EROFS", 32)]
    ),
  )
}

///|
test "Preview 2 descriptor types preserve every native file type" {
  debug_inspect(
    Array::makei(9, native_file_type_to_component),
    content="[0, 1, 2, 3, 6, 7, 7, 5, 4]",
  )
}

///|
test "Preview 3 descriptor and error variants follow stable 0.3" {
  debug_inspect(
    (
      Array::makei(9, preview3_descriptor_type),
      [preview3_filesystem_error_for(NoEnt), preview3_filesystem_error_code(36)],
    ),
    content=(
      #|(
      #|  [
      #|    Variant(7, Some(Variant(0, None))),
      #|    Variant(0, None),
      #|    Variant(1, None),
      #|    Variant(2, None),
      #|    Variant(5, None),
      #|    Variant(6, None),
      #|    Variant(6, None),
      #|    Variant(4, None),
      #|    Variant(3, None),
      #|  ],
      #|  [
      #|    Variant(1, Some(Variant(19, None))),
      #|    Variant(1, Some(Variant(36, Some(Variant(0, None))))),
      #|  ],
      #|)
    ),
  )
}

///|
test "Preview 3 filesystem timestamps use signed system-clock instants" {
  debug_inspect(
    [
      parse_preview3_new_timestamp(
        Variant(2, Some(Tuple([S64(-1L), U32(999_999_999)]))),
        1,
        2,
      ),
      parse_preview3_new_timestamp(
        Variant(2, Some(Tuple([S64(9_223_372_036L), U32(854_775_807)]))),
        1,
        2,
      ),
      parse_preview3_new_timestamp(
        Variant(2, Some(Tuple([S64(9_223_372_036L), U32(854_775_808)]))),
        1,
        2,
      ),
    ],
    content="[Some((-1, 1)), Some((9223372036854775807, 1)), None]",
  )
}
