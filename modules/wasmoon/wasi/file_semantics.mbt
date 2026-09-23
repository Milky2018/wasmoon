///|
using @native_io {c_allocate}

///|
// Synchronization belongs to the descriptor contract rather than F_SETFL:
// several supported kernels cannot change O_SYNC after a file is opened.
// A full flush is a valid stronger implementation of data-only synchronization.
fn OpenFile::synchronize(self : OpenFile, before_read : Bool) -> Int {
  if before_read && (self.flags & 0x08) == 0 {
    return 0
  }
  let sync = self.flags & 0x1A
  if sync == 0 {
    return 0
  }
  let success = if (sync & 0x10) != 0 || (sync & 0x08) != 0 {
    native_fsync(self.native_fd)
  } else {
    native_fdatasync(self.native_fd)
  }
  if success {
    0
  } else {
    native_last_errno_to_wasi()
  }
}
