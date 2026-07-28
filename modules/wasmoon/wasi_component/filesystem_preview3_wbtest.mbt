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
