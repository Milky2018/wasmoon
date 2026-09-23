///|
/// Open a file
/// Returns file descriptor or -1 on error
#borrow(path)
pub extern "c" fn c_open(
  path : FixedArray[Byte],
  flags : Int,
  mode : Int,
) -> Int = "wasmoon_wasi_open"

///|
#borrow(parent_path)
pub extern "c" fn c_open_parent_beneath(
  root_fd : Int,
  parent_path : FixedArray[Byte],
) -> Int = "wasmoon_wasi_open_parent_beneath"

///|
#borrow(parent_path, leaf)
pub extern "c" fn c_openat_beneath(
  root_fd : Int,
  parent_path : FixedArray[Byte],
  leaf : FixedArray[Byte],
  flags : Int,
  mode : Int,
  follow_final : Int,
) -> Int = "wasmoon_wasi_openat_beneath"

///|
pub extern "c" fn c_dup(fd : Int) -> Int = "wasmoon_wasi_dup"

///|
/// Close a file descriptor
pub extern "c" fn c_close(fd : Int) -> Int = "wasmoon_wasi_close"

///|
/// Read from a file descriptor
/// Returns number of bytes read, 0 for EOF, or -1 on error
#borrow(buf)
extern "c" fn raw_c_read(fd : Int, buf : FixedArray[Byte], count : Int) -> Int = "wasmoon_wasi_read"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_read(fd : Int, buf : FixedArray[Byte], count : Int) -> Int {
  if count < 0 || count > buf.length() {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_read(fd, buf, count)
}

///|
/// Write to a file descriptor
/// Returns number of bytes written or -1 on error
#borrow(buf)
extern "c" fn raw_c_write(fd : Int, buf : FixedArray[Byte], count : Int) -> Int = "wasmoon_wasi_write"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_write(fd : Int, buf : FixedArray[Byte], count : Int) -> Int {
  if count < 0 || count > buf.length() {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_write(fd, buf, count)
}

///|
#borrow(buf)
extern "c" fn raw_c_pread(
  fd : Int,
  buf : FixedArray[Byte],
  count : Int,
  offset : Int64,
) -> Int = "wasmoon_wasi_pread"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_pread(
  fd : Int,
  buf : FixedArray[Byte],
  count : Int,
  offset : Int64,
) -> Int {
  if count < 0 || count > buf.length() {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_pread(fd, buf, count, offset)
}

///|
#borrow(buf)
extern "c" fn raw_c_pwrite(
  fd : Int,
  buf : FixedArray[Byte],
  count : Int,
  offset : Int64,
) -> Int = "wasmoon_wasi_pwrite"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_pwrite(
  fd : Int,
  buf : FixedArray[Byte],
  count : Int,
  offset : Int64,
) -> Int {
  if count < 0 || count > buf.length() {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_pwrite(fd, buf, count, offset)
}

///|
/// Seek in a file
/// Returns new offset or -1 on error
pub extern "c" fn c_lseek(fd : Int, offset : Int64, whence : Int) -> Int64 = "wasmoon_wasi_lseek"

///|
/// Get error message for last error
pub extern "c" fn c_get_error_message() -> Bytes = "wasmoon_wasi_get_error_message"

///|
/// Get errno value
pub extern "c" fn c_get_errno() -> Int = "wasmoon_wasi_get_errno"

///|
pub extern "c" fn c_set_errno_invalid_argument() -> Unit = "wasmoon_wasi_set_errno_invalid_argument"

///|
pub extern "c" fn c_set_errno_illegal_byte_sequence() -> Unit = "wasmoon_wasi_set_errno_illegal_byte_sequence"

///|
/// Check whether file descriptor is a TTY
pub extern "c" fn c_isatty(fd : Int) -> Int = "wasmoon_wasi_isatty"

///|
/// Check whether target path remains within base after canonicalization
#borrow(base_path, target_path)
pub extern "c" fn c_path_within_base(
  base_path : FixedArray[Byte],
  target_path : FixedArray[Byte],
) -> Int = "wasmoon_wasi_path_within_base"

///|
/// Convert native errno to WASI errno
pub extern "c" fn c_errno_to_wasi(err : Int) -> Int = "wasmoon_wasi_errno_to_wasi"

///|
/// Platform-specific open flags (retrieved from C at runtime)
pub extern "c" fn c_o_rdonly() -> Int = "wasmoon_wasi_o_rdonly"

///|
pub extern "c" fn c_o_wronly() -> Int = "wasmoon_wasi_o_wronly"

///|
pub extern "c" fn c_o_rdwr() -> Int = "wasmoon_wasi_o_rdwr"

///|
pub extern "c" fn c_o_creat() -> Int = "wasmoon_wasi_o_creat"

///|
pub extern "c" fn c_o_trunc() -> Int = "wasmoon_wasi_o_trunc"

///|
pub extern "c" fn c_o_append() -> Int = "wasmoon_wasi_o_append"

///|
pub extern "c" fn c_o_excl() -> Int = "wasmoon_wasi_o_excl"

///|
pub extern "c" fn c_o_nonblock() -> Int = "wasmoon_wasi_o_nonblock"

///|
pub extern "c" fn c_o_directory() -> Int = "wasmoon_wasi_o_directory"

///|
pub extern "c" fn c_o_nofollow() -> Int = "wasmoon_wasi_o_nofollow"

///|
/// Create a directory
/// Returns 0 on success, -1 on error
#borrow(path)
pub extern "c" fn c_mkdir(path : FixedArray[Byte], mode : Int) -> Int = "wasmoon_wasi_mkdir"

///|
#borrow(path)
pub extern "c" fn c_mkdirat(
  dirfd : Int,
  path : FixedArray[Byte],
  mode : Int,
) -> Int = "wasmoon_wasi_mkdirat"

///|
/// Read directory entries
/// Returns serialized entries or null on error
#borrow(path)
pub extern "c" fn c_readdir(path : FixedArray[Byte]) -> Bytes? = "wasmoon_wasi_readdir"

///|
pub extern "c" fn c_readdir_fd(fd : Int) -> Bytes? = "wasmoon_wasi_readdir_fd"

///|
/// Print string to stdout without newline
#borrow(str)
extern "c" fn raw_c_print_string(str : FixedArray[Byte], len : Int) -> Unit = "wasmoon_print_string"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_print_string(str : FixedArray[Byte], len : Int) -> Unit {
  if len < 0 || len > str.length() {
    c_set_errno_invalid_argument()
    return ()
  }
  raw_c_print_string(str, len)
}

///|
/// Print a single character to stdout
pub extern "c" fn c_putchar(c : Int) -> Unit = "wasmoon_putchar"

///|
/// Sync file to disk
pub extern "c" fn c_fsync(fd : Int) -> Int = "wasmoon_wasi_fsync"

///|
/// Sync file data (not metadata) to disk
pub extern "c" fn c_fdatasync(fd : Int) -> Int = "wasmoon_wasi_fdatasync"

///|
/// Unlink file or directory
#borrow(path)
pub extern "c" fn c_unlinkat(
  dirfd : Int,
  path : FixedArray[Byte],
  flags : Int,
) -> Int = "wasmoon_wasi_unlinkat"

///|
/// Rename file or directory
#borrow(old_path, new_path)
pub extern "c" fn c_renameat(
  old_dirfd : Int,
  old_path : FixedArray[Byte],
  new_dirfd : Int,
  new_path : FixedArray[Byte],
) -> Int = "wasmoon_wasi_renameat"

///|
/// Get file stat via fd
#borrow(dev, ino, filetype, nlink, size, atim, mtim, ctim)
extern "c" fn raw_c_fstat(
  fd : Int,
  dev : FixedArray[UInt64],
  ino : FixedArray[UInt64],
  filetype : FixedArray[Byte],
  nlink : FixedArray[UInt64],
  size : FixedArray[UInt64],
  atim : FixedArray[UInt64],
  mtim : FixedArray[UInt64],
  ctim : FixedArray[UInt64],
) -> Int = "wasmoon_wasi_fstat"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_fstat(
  fd : Int,
  dev : FixedArray[UInt64],
  ino : FixedArray[UInt64],
  filetype : FixedArray[Byte],
  nlink : FixedArray[UInt64],
  size : FixedArray[UInt64],
  atim : FixedArray[UInt64],
  mtim : FixedArray[UInt64],
  ctim : FixedArray[UInt64],
) -> Int {
  if dev.length() < 1 ||
    ino.length() < 1 ||
    filetype.length() < 1 ||
    nlink.length() < 1 ||
    size.length() < 1 ||
    atim.length() < 1 ||
    mtim.length() < 1 ||
    ctim.length() < 1 {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_fstat(fd, dev, ino, filetype, nlink, size, atim, mtim, ctim)
}

///|
/// Get file stat via path
#borrow(path, dev, ino, filetype, nlink, size, atim, mtim, ctim)
extern "c" fn raw_c_fstatat(
  dirfd : Int,
  path : FixedArray[Byte],
  flags : Int,
  dev : FixedArray[UInt64],
  ino : FixedArray[UInt64],
  filetype : FixedArray[Byte],
  nlink : FixedArray[UInt64],
  size : FixedArray[UInt64],
  atim : FixedArray[UInt64],
  mtim : FixedArray[UInt64],
  ctim : FixedArray[UInt64],
) -> Int = "wasmoon_wasi_fstatat"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_fstatat(
  dirfd : Int,
  path : FixedArray[Byte],
  flags : Int,
  dev : FixedArray[UInt64],
  ino : FixedArray[UInt64],
  filetype : FixedArray[Byte],
  nlink : FixedArray[UInt64],
  size : FixedArray[UInt64],
  atim : FixedArray[UInt64],
  mtim : FixedArray[UInt64],
  ctim : FixedArray[UInt64],
) -> Int {
  if dev.length() < 1 ||
    ino.length() < 1 ||
    filetype.length() < 1 ||
    nlink.length() < 1 ||
    size.length() < 1 ||
    atim.length() < 1 ||
    mtim.length() < 1 ||
    ctim.length() < 1 {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_fstatat(
    dirfd, path, flags, dev, ino, filetype, nlink, size, atim, mtim, ctim,
  )
}

///|
/// Truncate file
pub extern "c" fn c_ftruncate(fd : Int, size : Int64) -> Int = "wasmoon_wasi_ftruncate"

///|
/// Set file times via fd
pub extern "c" fn c_futimens(
  fd : Int,
  atim : Int64,
  mtim : Int64,
  fst_flags : Int,
) -> Int = "wasmoon_wasi_futimens"

///|
/// Set file times via path
#borrow(path)
pub extern "c" fn c_utimensat(
  dirfd : Int,
  path : FixedArray[Byte],
  atim : Int64,
  mtim : Int64,
  fst_flags : Int,
  lookup_flags : Int,
) -> Int = "wasmoon_wasi_utimensat"

///|
/// Set fd flags
pub extern "c" fn c_fcntl_setfl(fd : Int, flags : Int) -> Int = "wasmoon_wasi_fcntl_setfl"

///|
/// Get fd flags
pub extern "c" fn c_fcntl_getfl(fd : Int) -> Int = "wasmoon_wasi_fcntl_getfl"

///|
/// Duplicate fd
pub extern "c" fn c_dup2(oldfd : Int, newfd : Int) -> Int = "wasmoon_wasi_dup2"

///|
/// Create symbolic link
#borrow(target, linkpath)
pub extern "c" fn c_symlinkat(
  target : FixedArray[Byte],
  dirfd : Int,
  linkpath : FixedArray[Byte],
) -> Int = "wasmoon_wasi_symlinkat"

///|
/// Read symbolic link
#borrow(path, buf)
extern "c" fn raw_c_readlinkat(
  dirfd : Int,
  path : FixedArray[Byte],
  buf : FixedArray[Byte],
  bufsize : Int64,
) -> Int64 = "wasmoon_wasi_readlinkat"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_readlinkat(
  dirfd : Int,
  path : FixedArray[Byte],
  buf : FixedArray[Byte],
  bufsize : Int64,
) -> Int64 {
  if bufsize < 0L || bufsize > buf.length().to_int64() {
    c_set_errno_invalid_argument()
    return -1L
  }
  raw_c_readlinkat(dirfd, path, buf, bufsize)
}

///|
/// Create hard link
#borrow(oldpath, newpath)
pub extern "c" fn c_linkat(
  olddirfd : Int,
  oldpath : FixedArray[Byte],
  newdirfd : Int,
  newpath : FixedArray[Byte],
  flags : Int,
) -> Int = "wasmoon_wasi_linkat"

///|
/// Nanosleep
pub extern "c" fn c_nanosleep(ns : Int64) -> Int = "wasmoon_wasi_nanosleep"

///|
/// Get monotonic time in nanoseconds
pub extern "c" fn c_clock_gettime_monotonic() -> Int64 = "wasmoon_wasi_clock_gettime_monotonic"

///|
/// Get realtime in nanoseconds
pub extern "c" fn c_clock_gettime_realtime() -> Int64 = "wasmoon_wasi_clock_gettime_realtime"

///|
/// Get monotonic clock resolution in nanoseconds
pub extern "c" fn c_clock_getres_monotonic() -> Int64 = "wasmoon_wasi_clock_getres_monotonic"

///|
/// Get realtime clock resolution in nanoseconds
pub extern "c" fn c_clock_getres_realtime() -> Int64 = "wasmoon_wasi_clock_getres_realtime"

///|
/// Poll on file descriptors
#borrow(fds, events, revents)
extern "c" fn raw_c_poll(
  fds : FixedArray[Int],
  events : FixedArray[Int],
  revents : FixedArray[Int],
  nfds : Int,
  timeout_ms : Int,
) -> Int = "wasmoon_wasi_poll"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_poll(
  fds : FixedArray[Int],
  events : FixedArray[Int],
  revents : FixedArray[Int],
  nfds : Int,
  timeout_ms : Int,
) -> Int {
  if nfds < 0 ||
    nfds > fds.length() ||
    nfds > events.length() ||
    nfds > revents.length() {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_poll(fds, events, revents, nfds, timeout_ms)
}

///|
pub extern "c" fn c_socket_bytes_available(fd : Int) -> Int64 = "wasmoon_wasi_socket_bytes_available"

///|
pub extern "c" fn c_socket_create(family : Int, kind : Int) -> Int = "wasmoon_wasi_socket_create"

///|
#borrow(address)
extern "c" fn raw_c_socket_bind(
  fd : Int,
  family : Int,
  address : FixedArray[Byte],
  port : Int,
  scope_id : Int,
) -> Int = "wasmoon_wasi_socket_bind"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_socket_bind(
  fd : Int,
  family : Int,
  address : FixedArray[Byte],
  port : Int,
  scope_id : Int,
) -> Int {
  if address.length() < (if family == 4 { 4 } else { 16 }) {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_socket_bind(fd, family, address, port, scope_id)
}

///|
#borrow(address)
extern "c" fn raw_c_socket_connect(
  fd : Int,
  family : Int,
  address : FixedArray[Byte],
  port : Int,
  scope_id : Int,
) -> Int = "wasmoon_wasi_socket_connect"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_socket_connect(
  fd : Int,
  family : Int,
  address : FixedArray[Byte],
  port : Int,
  scope_id : Int,
) -> Int {
  if address.length() < (if family == 4 { 4 } else { 16 }) {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_socket_connect(fd, family, address, port, scope_id)
}

///|
pub extern "c" fn c_socket_disconnect(fd : Int) -> Int = "wasmoon_wasi_socket_disconnect"

///|
#borrow(data, family, address, port, scope_id)
extern "c" fn raw_c_socket_recv_from(
  fd : Int,
  data : FixedArray[Byte],
  length : Int,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  port : FixedArray[UInt16],
  scope_id : FixedArray[UInt],
) -> Int64 = "wasmoon_wasi_socket_recv_from"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_socket_recv_from(
  fd : Int,
  data : FixedArray[Byte],
  length : Int,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  port : FixedArray[UInt16],
  scope_id : FixedArray[UInt],
) -> Int64 {
  if length < 0 ||
    length > data.length() ||
    family.length() < 1 ||
    address.length() < 16 ||
    port.length() < 1 ||
    scope_id.length() < 1 {
    c_set_errno_invalid_argument()
    return -1L
  }
  raw_c_socket_recv_from(fd, data, length, family, address, port, scope_id)
}

///|
#borrow(data, address)
extern "c" fn raw_c_socket_send_to(
  fd : Int,
  data : FixedArray[Byte],
  length : Int,
  has_address : Int,
  family : Int,
  address : FixedArray[Byte],
  port : Int,
  scope_id : Int,
) -> Int64 = "wasmoon_wasi_socket_send_to"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_socket_send_to(
  fd : Int,
  data : FixedArray[Byte],
  length : Int,
  has_address : Int,
  family : Int,
  address : FixedArray[Byte],
  port : Int,
  scope_id : Int,
) -> Int64 {
  if length < 0 ||
    length > data.length() ||
    (has_address != 0 && address.length() < (if family == 4 { 4 } else { 16 })) {
    c_set_errno_invalid_argument()
    return -1L
  }
  raw_c_socket_send_to(
    fd, data, length, has_address, family, address, port, scope_id,
  )
}

///|
pub extern "c" fn c_socket_listen(fd : Int, backlog : Int) -> Int = "wasmoon_wasi_socket_listen"

///|
pub extern "c" fn c_socket_error(fd : Int) -> Int = "wasmoon_wasi_socket_error"

///|
#borrow(family, address, port, scope_id)
extern "c" fn raw_c_socket_address_get(
  fd : Int,
  peer : Int,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  port : FixedArray[UInt16],
  scope_id : FixedArray[UInt],
) -> Int = "wasmoon_wasi_socket_address_get"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_socket_address_get(
  fd : Int,
  peer : Int,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  port : FixedArray[UInt16],
  scope_id : FixedArray[UInt],
) -> Int {
  if family.length() < 1 ||
    address.length() < 16 ||
    port.length() < 1 ||
    scope_id.length() < 1 {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_socket_address_get(fd, peer, family, address, port, scope_id)
}

///|
pub extern "c" fn c_socket_option_get(
  fd : Int,
  family : Int,
  option : Int,
) -> Int = "wasmoon_wasi_socket_option_get"

///|
pub extern "c" fn c_socket_option_set(
  fd : Int,
  family : Int,
  option : Int,
  value : Int,
) -> Int = "wasmoon_wasi_socket_option_set"

///|
#borrow(name, poll_fd)
extern "c" fn raw_c_resolver_start(
  name : FixedArray[Byte],
  poll_fd : FixedArray[Int],
) -> Int64 = "wasmoon_wasi_resolver_start"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_resolver_start(
  name : FixedArray[Byte],
  poll_fd : FixedArray[Int],
) -> Int64 {
  if poll_fd.length() < 1 {
    c_set_errno_invalid_argument()
    return 0L
  }
  raw_c_resolver_start(name, poll_fd)
}

///|
#borrow(family, address, scope_id)
extern "c" fn raw_c_resolver_next(
  resolver : Int64,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  scope_id : FixedArray[UInt],
) -> Int = "wasmoon_wasi_resolver_next"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_resolver_next(
  resolver : Int64,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  scope_id : FixedArray[UInt],
) -> Int {
  if family.length() < 1 || address.length() < 16 || scope_id.length() < 1 {
    c_set_errno_invalid_argument()
    return 5
  }
  raw_c_resolver_next(resolver, family, address, scope_id)
}

///|
pub extern "c" fn c_resolver_drop(resolver : Int64) = "wasmoon_wasi_resolver_drop"

///|
/// Socket recv
#borrow(buf)
extern "c" fn raw_c_recv(
  sockfd : Int,
  buf : FixedArray[Byte],
  len : Int64,
  flags : Int,
) -> Int64 = "wasmoon_wasi_recv"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_recv(
  sockfd : Int,
  buf : FixedArray[Byte],
  len : Int64,
  flags : Int,
) -> Int64 {
  if len < 0L || len > buf.length().to_int64() {
    c_set_errno_invalid_argument()
    return -1L
  }
  raw_c_recv(sockfd, buf, len, flags)
}

///|
/// Socket send
#borrow(buf)
extern "c" fn raw_c_send(
  sockfd : Int,
  buf : FixedArray[Byte],
  len : Int64,
  flags : Int,
) -> Int64 = "wasmoon_wasi_send"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_send(
  sockfd : Int,
  buf : FixedArray[Byte],
  len : Int64,
  flags : Int,
) -> Int64 {
  if len < 0L || len > buf.length().to_int64() {
    c_set_errno_invalid_argument()
    return -1L
  }
  raw_c_send(sockfd, buf, len, flags)
}

///|
/// Socket shutdown
pub extern "c" fn c_shutdown(sockfd : Int, how : Int) -> Int = "wasmoon_wasi_shutdown"

///|
/// Socket accept
pub extern "c" fn c_accept(sockfd : Int) -> Int = "wasmoon_wasi_accept"

///|
/// Raise signal
pub extern "c" fn c_raise(sig : Int) -> Int = "wasmoon_wasi_raise"

///|
/// Get random bytes from system
#borrow(buf)
extern "c" fn raw_c_getrandom(buf : FixedArray[Byte], len : Int) -> Int = "wasmoon_wasi_getrandom"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_getrandom(buf : FixedArray[Byte], len : Int) -> Int {
  if len < 0 || len > buf.length() {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_getrandom(buf, len)
}

///|
#borrow(path, dev, ino, filetype, nlink, size, atim, mtim, ctim)
extern "c" fn raw_c_fstat_beneath(
  dirfd : Int,
  path : FixedArray[Byte],
  flags : Int,
  dev : FixedArray[UInt64],
  ino : FixedArray[UInt64],
  filetype : FixedArray[Byte],
  nlink : FixedArray[UInt64],
  size : FixedArray[UInt64],
  atim : FixedArray[UInt64],
  mtim : FixedArray[UInt64],
  ctim : FixedArray[UInt64],
) -> Int = "wasmoon_wasi_fstat_beneath"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_fstat_beneath(
  dirfd : Int,
  path : FixedArray[Byte],
  flags : Int,
  dev : FixedArray[UInt64],
  ino : FixedArray[UInt64],
  filetype : FixedArray[Byte],
  nlink : FixedArray[UInt64],
  size : FixedArray[UInt64],
  atim : FixedArray[UInt64],
  mtim : FixedArray[UInt64],
  ctim : FixedArray[UInt64],
) -> Int {
  if dev.length() < 1 ||
    ino.length() < 1 ||
    filetype.length() < 1 ||
    nlink.length() < 1 ||
    size.length() < 1 ||
    atim.length() < 1 ||
    mtim.length() < 1 ||
    ctim.length() < 1 {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_fstat_beneath(
    dirfd, path, flags, dev, ino, filetype, nlink, size, atim, mtim, ctim,
  )
}

///|
#borrow(path)
pub extern "c" fn c_utimens_beneath(
  root : Int,
  path : FixedArray[Byte],
  follow : Int,
  atim : Int64,
  mtim : Int64,
  flags : Int,
) -> Int = "wasmoon_wasi_utimens_beneath"
