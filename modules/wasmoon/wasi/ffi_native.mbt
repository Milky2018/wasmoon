///|
/// Native FFI for file operations
/// These functions call C functions defined in ffi_native.c
/// which provides cross-platform support for Windows and Unix

///|
/// Open a file
/// Returns file descriptor or -1 on error
#borrow(path)
extern "c" fn c_open(path : FixedArray[Byte], flags : Int, mode : Int) -> Int = "wasmoon_wasi_open"

///|
#borrow(parent_path)
extern "c" fn c_open_parent_beneath(
  root_fd : Int,
  parent_path : FixedArray[Byte],
) -> Int = "wasmoon_wasi_open_parent_beneath"

///|
#borrow(parent_path, leaf)
extern "c" fn c_openat_beneath(
  root_fd : Int,
  parent_path : FixedArray[Byte],
  leaf : FixedArray[Byte],
  flags : Int,
  mode : Int,
  follow_final : Int,
) -> Int = "wasmoon_wasi_openat_beneath"

///|
extern "c" fn c_dup(fd : Int) -> Int = "wasmoon_wasi_dup"

///|
/// Close a file descriptor
extern "c" fn c_close(fd : Int) -> Int = "wasmoon_wasi_close"

///|
/// Read from a file descriptor
/// Returns number of bytes read, 0 for EOF, or -1 on error
#borrow(buf)
extern "c" fn c_read(fd : Int, buf : FixedArray[Byte], count : Int) -> Int = "wasmoon_wasi_read"

///|
/// Write to a file descriptor
/// Returns number of bytes written or -1 on error
#borrow(buf)
extern "c" fn c_write(fd : Int, buf : FixedArray[Byte], count : Int) -> Int = "wasmoon_wasi_write"

///|
#borrow(buf)
extern "c" fn c_pread(
  fd : Int,
  buf : FixedArray[Byte],
  count : Int,
  offset : Int64,
) -> Int = "wasmoon_wasi_pread"

///|
#borrow(buf)
extern "c" fn c_pwrite(
  fd : Int,
  buf : FixedArray[Byte],
  count : Int,
  offset : Int64,
) -> Int = "wasmoon_wasi_pwrite"

///|
/// Seek in a file
/// Returns new offset or -1 on error
extern "c" fn c_lseek(fd : Int, offset : Int64, whence : Int) -> Int64 = "wasmoon_wasi_lseek"

///|
/// Get error message for last error
extern "c" fn c_get_error_message() -> Bytes = "wasmoon_wasi_get_error_message"

///|
/// Get errno value
extern "c" fn c_get_errno() -> Int = "wasmoon_wasi_get_errno"

///|
/// Check whether file descriptor is a TTY
extern "c" fn c_isatty(fd : Int) -> Int = "wasmoon_wasi_isatty"

///|
/// Check whether target path remains within base after canonicalization
#borrow(base_path, target_path)
extern "c" fn c_path_within_base(
  base_path : FixedArray[Byte],
  target_path : FixedArray[Byte],
) -> Int = "wasmoon_wasi_path_within_base"

///|
/// Convert native errno to WASI errno
extern "c" fn c_errno_to_wasi(err : Int) -> Int = "wasmoon_wasi_errno_to_wasi"

///|
/// Platform-specific open flags (retrieved from C at runtime)
extern "c" fn c_o_rdonly() -> Int = "wasmoon_wasi_o_rdonly"

///|
extern "c" fn c_o_wronly() -> Int = "wasmoon_wasi_o_wronly"

///|
extern "c" fn c_o_rdwr() -> Int = "wasmoon_wasi_o_rdwr"

///|
extern "c" fn c_o_creat() -> Int = "wasmoon_wasi_o_creat"

///|
extern "c" fn c_o_trunc() -> Int = "wasmoon_wasi_o_trunc"

///|
extern "c" fn c_o_append() -> Int = "wasmoon_wasi_o_append"

///|
extern "c" fn c_o_excl() -> Int = "wasmoon_wasi_o_excl"

///|
extern "c" fn c_o_nonblock() -> Int = "wasmoon_wasi_o_nonblock"

///|
extern "c" fn c_o_directory() -> Int = "wasmoon_wasi_o_directory"

///|
extern "c" fn c_o_nofollow() -> Int = "wasmoon_wasi_o_nofollow"

///|
/// File open flags
pub(all) enum OpenFlags {
  ReadOnly
  WriteOnly
  ReadWrite
  Create
  Truncate
  Append
  Exclusive
  Directory
  NoFollow
}

///|
/// Convert OpenFlags to platform-specific int using C functions
fn open_flags_to_int(flags : Array[OpenFlags]) -> Int {
  let mut result = 0
  for flag in flags {
    let v = match flag {
      ReadOnly => c_o_rdonly()
      WriteOnly => c_o_wronly()
      ReadWrite => c_o_rdwr()
      Create => c_o_creat()
      Truncate => c_o_trunc()
      Append => c_o_append()
      Exclusive => c_o_excl()
      Directory => c_o_directory()
      NoFollow => c_o_nofollow()
    }
    result = result | v
  }
  result
}

///|
/// Whence for seek
pub(all) enum Whence {
  Set // Seek from beginning
  Cur // Seek from current position
  End // Seek from end
}

///|
fn whence_to_int(w : Whence) -> Int {
  match w {
    Set => 0
    Cur => 1
    End => 2
  }
}

///|
/// Open a file with the given path and flags
/// Returns file descriptor or None on error
pub fn native_open(path : String, flags : Array[OpenFlags], mode : Int) -> Int? {
  let path_bytes = string_to_cstring(path)
  let flags_int = open_flags_to_int(flags)
  let fd = c_open(path_bytes, flags_int, mode)
  if fd < 0 {
    None
  } else {
    Some(fd)
  }
}

///|
pub fn native_open_parent_beneath(root_fd : Int, parent_path : String) -> Int? {
  let path_bytes = string_to_cstring(parent_path)
  let fd = c_open_parent_beneath(root_fd, path_bytes)
  if fd < 0 {
    None
  } else {
    Some(fd)
  }
}

///|
pub fn native_openat_beneath(
  root_fd : Int,
  parent_path : String,
  leaf : String,
  flags : Array[OpenFlags],
  mode : Int,
  follow_final : Bool,
) -> Int? {
  let parent_bytes = string_to_cstring(parent_path)
  let leaf_bytes = string_to_cstring(leaf)
  let fd = c_openat_beneath(
    root_fd,
    parent_bytes,
    leaf_bytes,
    open_flags_to_int(flags),
    mode,
    if follow_final {
      1
    } else {
      0
    },
  )
  if fd < 0 {
    None
  } else {
    Some(fd)
  }
}

///|
pub fn native_dup(fd : Int) -> Int? {
  let result = c_dup(fd)
  if result < 0 {
    None
  } else {
    Some(result)
  }
}

///|
/// Open a file for reading
pub fn native_open_read(path : String) -> Int? {
  native_open(path, [ReadOnly], 0)
}

///|
/// Open a file for writing (create if not exists, truncate if exists)
pub fn native_open_write(path : String) -> Int? {
  native_open(path, [WriteOnly, Create, Truncate], 0o644)
}

///|
pub fn native_o_rdonly() -> Int {
  c_o_rdonly()
}

///|
pub fn native_o_wronly() -> Int {
  c_o_wronly()
}

///|
pub fn native_o_rdwr() -> Int {
  c_o_rdwr()
}

///|
pub fn native_o_append() -> Int {
  c_o_append()
}

///|
pub fn native_o_nonblock() -> Int {
  c_o_nonblock()
}

///|
pub fn native_isatty(fd : Int) -> Bool {
  c_isatty(fd) != 0
}

///|
/// Close a file descriptor
/// Returns true on success
pub fn native_close(fd : Int) -> Bool {
  c_close(fd) == 0
}

///|
/// Read from a file descriptor into a buffer
/// Returns number of bytes read or None on error
pub fn native_read(fd : Int, buf : FixedArray[Byte], count : Int) -> Int? {
  let n = c_read(fd, buf, count)
  if n < 0 {
    None
  } else {
    Some(n)
  }
}

///|
/// Write to a file descriptor from a buffer
/// Returns number of bytes written or None on error
pub fn native_write(fd : Int, buf : FixedArray[Byte], count : Int) -> Int? {
  let n = c_write(fd, buf, count)
  if n < 0 {
    None
  } else {
    Some(n)
  }
}

///|
pub fn native_pread(
  fd : Int,
  buf : FixedArray[Byte],
  count : Int,
  offset : Int64,
) -> Int? {
  let result = c_pread(fd, buf, count, offset)
  if result < 0 {
    None
  } else {
    Some(result)
  }
}

///|
pub fn native_pwrite(
  fd : Int,
  buf : FixedArray[Byte],
  count : Int,
  offset : Int64,
) -> Int? {
  let result = c_pwrite(fd, buf, count, offset)
  if result < 0 {
    None
  } else {
    Some(result)
  }
}

///|
/// Seek in a file
/// Returns new offset or None on error
pub fn native_seek(fd : Int, offset : Int64, whence : Whence) -> Int64? {
  let pos = c_lseek(fd, offset, whence_to_int(whence))
  if pos < 0L {
    None
  } else {
    Some(pos)
  }
}

///|
/// Get current position in a file
/// Returns current offset or None on error
pub fn native_tell(fd : Int) -> Int64? {
  native_seek(fd, 0L, Cur)
}

///|
/// Get the last error message
pub fn native_get_error_message() -> String {
  let bytes = c_get_error_message()
  utf8_bytes_to_string(bytes)
}

///|
/// Get the last errno value
pub fn native_get_errno() -> Int {
  c_get_errno()
}

///|
/// Convert current native errno to WASI errno
pub fn native_last_errno_to_wasi() -> Int {
  c_errno_to_wasi(c_get_errno())
}

///|
pub fn native_errno_to_wasi(errno : Int) -> Int {
  c_errno_to_wasi(errno)
}

///|
/// Check whether target path stays within base after symlink resolution
pub fn native_path_within_base(
  base_path : String,
  target_path : String,
) -> Bool {
  let base_path_bytes = string_to_cstring(base_path)
  let target_path_bytes = string_to_cstring(target_path)
  c_path_within_base(base_path_bytes, target_path_bytes) != 0
}

///|
/// Create a directory
/// Returns 0 on success, -1 on error
#borrow(path)
extern "c" fn c_mkdir(path : FixedArray[Byte], mode : Int) -> Int = "wasmoon_wasi_mkdir"

///|
#borrow(path)
extern "c" fn c_mkdirat(
  dirfd : Int,
  path : FixedArray[Byte],
  mode : Int,
) -> Int = "wasmoon_wasi_mkdirat"

///|
/// Read directory entries
/// Returns serialized entries or null on error
#borrow(path)
extern "c" fn c_readdir(path : FixedArray[Byte]) -> Bytes? = "wasmoon_wasi_readdir"

///|
extern "c" fn c_readdir_fd(fd : Int) -> Bytes? = "wasmoon_wasi_readdir_fd"

///|
/// Create a directory
/// Returns true on success
pub fn native_mkdir(path : String, mode : Int) -> Bool {
  let path_bytes = string_to_cstring(path)
  c_mkdir(path_bytes, mode) == 0
}

///|
pub fn native_mkdirat(dirfd : Int, path : String, mode : Int) -> Bool {
  c_mkdirat(dirfd, string_to_cstring(path), mode) == 0
}

///|
fn parse_native_readdir(result : Bytes?) -> Array[(String, Int)]? {
  if result is None {
    return None
  }
  let bytes = result.unwrap()
  if bytes.length() < 4 {
    return Some([])
  }
  // Parse count (little-endian)
  let count = bytes[0].to_int() |
    (bytes[1].to_int() << 8) |
    (bytes[2].to_int() << 16) |
    (bytes[3].to_int() << 24)
  let entries : Array[(String, Int)] = []
  let mut offset = 4
  for _ in 0..<count {
    if offset >= bytes.length() {
      break
    }
    let file_type = bytes[offset].to_int()
    offset = offset + 1
    // Read name_len (little-endian)
    if offset + 4 > bytes.length() {
      break
    }
    let name_len = bytes[offset].to_int() |
      (bytes[offset + 1].to_int() << 8) |
      (bytes[offset + 2].to_int() << 16) |
      (bytes[offset + 3].to_int() << 24)
    offset = offset + 4
    // Read name
    if offset + name_len > bytes.length() {
      break
    }
    let name = @utf8.decode(bytes[offset:offset + name_len]) catch {
      _ => return None
    }
    offset = offset + name_len
    entries.push((name, file_type))
  }
  Some(entries)
}

///|
/// Read directory entries.
///
/// Each entry contains its name and native file-type token. Tokens 0-7 match
/// WASI Preview 1 filetype; token 8 denotes a FIFO.
pub fn native_readdir(path : String) -> Array[(String, Int)]? {
  parse_native_readdir(c_readdir(string_to_cstring(path)))
}

///|
/// Read directory entries from an opened directory fd.
///
/// Each entry contains its name and native file-type token. Tokens 0-7 match
/// WASI Preview 1 filetype; token 8 denotes a FIFO.
pub fn native_readdir_fd(fd : Int) -> Array[(String, Int)]? {
  parse_native_readdir(c_readdir_fd(fd))
}

///|
/// Convert a MoonBit string to a null-terminated C string (UTF-8)
fn string_to_cstring(s : String) -> FixedArray[Byte] {
  let encoded = @utf8.encode(s)
  let buf = FixedArray::make(encoded.length() + 1, b'\x00')
  for i in 0..<encoded.length() {
    buf[i] = encoded[i]
  }
  buf
}

///|
/// Convert UTF-8 bytes to a MoonBit string
fn utf8_bytes_to_string(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
/// Print string to stdout without newline
#borrow(str)
extern "c" fn c_print_string(str : FixedArray[Byte], len : Int) -> Unit = "wasmoon_print_string"

///|
/// Print a single character to stdout
extern "c" fn c_putchar(c : Int) -> Unit = "wasmoon_putchar"

///|
/// Print a single character to stdout (public wrapper)
pub fn putchar(c : Int) -> Unit {
  c_putchar(c)
}

///|
/// Print a string to stdout without newline
pub fn print_string(s : String) -> Unit {
  let bytes = string_to_cstring(s)
  // Find actual length (excluding null terminator)
  let mut len = 0
  while len < bytes.length() && bytes[len] != b'\x00' {
    len = len + 1
  }
  c_print_string(bytes, len)
}

///|
/// Read from a file descriptor directly into WASM memory
/// This avoids the FixedArray issue by reading byte by byte
pub fn native_read_to_memory(
  fd : Int,
  mem : @runtime.Memory,
  buf_ptr : Int,
  count : Int,
) -> Int? {
  let buf = FixedArray::make(1, b'\x00')
  let mut total_read = 0
  for i in 0..<count {
    let n = c_read(fd, buf, 1)
    if n < 0 {
      return if total_read > 0 { Some(total_read) } else { None }
    }
    if n == 0 {
      break // EOF
    }
    mem.write_byte(buf_ptr + i, buf[0])
    total_read = total_read + 1
  }
  Some(total_read)
}

// ============================================================================
// Phase 1: Core file operations
// ============================================================================

///|
/// Sync file to disk
extern "c" fn c_fsync(fd : Int) -> Int = "wasmoon_wasi_fsync"

///|
/// Sync file data (not metadata) to disk
extern "c" fn c_fdatasync(fd : Int) -> Int = "wasmoon_wasi_fdatasync"

///|
/// Unlink file or directory
#borrow(path)
extern "c" fn c_unlinkat(
  dirfd : Int,
  path : FixedArray[Byte],
  flags : Int,
) -> Int = "wasmoon_wasi_unlinkat"

///|
/// Rename file or directory
#borrow(old_path, new_path)
extern "c" fn c_renameat(
  old_dirfd : Int,
  old_path : FixedArray[Byte],
  new_dirfd : Int,
  new_path : FixedArray[Byte],
) -> Int = "wasmoon_wasi_renameat"

///|
/// Sync file to disk (returns 0 on success, -1 on error)
pub fn native_fsync(fd : Int) -> Bool {
  c_fsync(fd) == 0
}

///|
/// Sync file data to disk (returns 0 on success, -1 on error)
pub fn native_fdatasync(fd : Int) -> Bool {
  c_fdatasync(fd) == 0
}

///|
/// AT_REMOVEDIR flag for unlinkat
pub const AT_REMOVEDIR : Int = 0x200

///|
/// Unlink file (returns 0 on success, -1 on error)
pub fn native_unlinkat(dirfd : Int, path : String, flags : Int) -> Bool {
  let path_bytes = string_to_cstring(path)
  c_unlinkat(dirfd, path_bytes, flags) == 0
}

///|
/// Rename file or directory
pub fn native_renameat(
  old_dirfd : Int,
  old_path : String,
  new_dirfd : Int,
  new_path : String,
) -> Bool {
  let old_path_bytes = string_to_cstring(old_path)
  let new_path_bytes = string_to_cstring(new_path)
  c_renameat(old_dirfd, old_path_bytes, new_dirfd, new_path_bytes) == 0
}

// ============================================================================
// Phase 2: File metadata operations
// ============================================================================

///|
/// File stat result
pub(all) struct FileStat {
  dev : UInt64
  ino : UInt64
  filetype : Int
  nlink : UInt64
  size : UInt64
  atim : UInt64
  mtim : UInt64
  ctim : UInt64
}

///|
/// Get file stat via fd
#borrow(dev, ino, filetype, nlink, size, atim, mtim, ctim)
extern "c" fn c_fstat(
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
/// Get file stat via path
#borrow(path, dev, ino, filetype, nlink, size, atim, mtim, ctim)
extern "c" fn c_fstatat(
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
/// Truncate file
extern "c" fn c_ftruncate(fd : Int, size : Int64) -> Int = "wasmoon_wasi_ftruncate"

///|
/// Set file times via fd
extern "c" fn c_futimens(
  fd : Int,
  atim : Int64,
  mtim : Int64,
  fst_flags : Int,
) -> Int = "wasmoon_wasi_futimens"

///|
/// Set file times via path
#borrow(path)
extern "c" fn c_utimensat(
  dirfd : Int,
  path : FixedArray[Byte],
  atim : Int64,
  mtim : Int64,
  fst_flags : Int,
  lookup_flags : Int,
) -> Int = "wasmoon_wasi_utimensat"

///|
/// Get file stat via fd
pub fn native_fstat(fd : Int) -> FileStat? {
  let dev = FixedArray::make(1, 0UL)
  let ino = FixedArray::make(1, 0UL)
  let filetype = FixedArray::make(1, b'\x00')
  let nlink = FixedArray::make(1, 0UL)
  let size = FixedArray::make(1, 0UL)
  let atim = FixedArray::make(1, 0UL)
  let mtim = FixedArray::make(1, 0UL)
  let ctim = FixedArray::make(1, 0UL)
  if c_fstat(fd, dev, ino, filetype, nlink, size, atim, mtim, ctim) == 0 {
    Some({
      dev: dev[0],
      ino: ino[0],
      filetype: filetype[0].to_int(),
      nlink: nlink[0],
      size: size[0],
      atim: atim[0],
      mtim: mtim[0],
      ctim: ctim[0],
    })
  } else {
    None
  }
}

///|
/// AT_SYMLINK_NOFOLLOW flag
pub const AT_SYMLINK_NOFOLLOW : Int = 0x100

///|
/// Get file stat via path
pub fn native_fstatat(dirfd : Int, path : String, flags : Int) -> FileStat? {
  let path_bytes = string_to_cstring(path)
  let dev = FixedArray::make(1, 0UL)
  let ino = FixedArray::make(1, 0UL)
  let filetype = FixedArray::make(1, b'\x00')
  let nlink = FixedArray::make(1, 0UL)
  let size = FixedArray::make(1, 0UL)
  let atim = FixedArray::make(1, 0UL)
  let mtim = FixedArray::make(1, 0UL)
  let ctim = FixedArray::make(1, 0UL)
  if c_fstatat(
      dirfd, path_bytes, flags, dev, ino, filetype, nlink, size, atim, mtim, ctim,
    ) ==
    0 {
    Some({
      dev: dev[0],
      ino: ino[0],
      filetype: filetype[0].to_int(),
      nlink: nlink[0],
      size: size[0],
      atim: atim[0],
      mtim: mtim[0],
      ctim: ctim[0],
    })
  } else {
    None
  }
}

///|
/// Truncate file
pub fn native_ftruncate(fd : Int, size : Int64) -> Bool {
  c_ftruncate(fd, size) == 0
}

///|
/// Set file times via fd
pub fn native_futimens(
  fd : Int,
  atim : Int64,
  mtim : Int64,
  fst_flags : Int,
) -> Bool {
  c_futimens(fd, atim, mtim, fst_flags) == 0
}

///|
/// Set file times via path
pub fn native_utimensat(
  dirfd : Int,
  path : String,
  atim : Int64,
  mtim : Int64,
  fst_flags : Int,
  lookup_flags : Int,
) -> Bool {
  let path_bytes = string_to_cstring(path)
  c_utimensat(dirfd, path_bytes, atim, mtim, fst_flags, lookup_flags) == 0
}

// ============================================================================
// Phase 3: Auxiliary functions
// ============================================================================

///|
/// Set fd flags
extern "c" fn c_fcntl_setfl(fd : Int, flags : Int) -> Int = "wasmoon_wasi_fcntl_setfl"

///|
/// Get fd flags
extern "c" fn c_fcntl_getfl(fd : Int) -> Int = "wasmoon_wasi_fcntl_getfl"

///|
/// Duplicate fd
extern "c" fn c_dup2(oldfd : Int, newfd : Int) -> Int = "wasmoon_wasi_dup2"

///|
/// Set fd flags
pub fn native_fcntl_setfl(fd : Int, flags : Int) -> Bool {
  c_fcntl_setfl(fd, flags) >= 0
}

///|
/// Get fd flags
pub fn native_fcntl_getfl(fd : Int) -> Int? {
  let result = c_fcntl_getfl(fd)
  if result >= 0 {
    Some(result)
  } else {
    None
  }
}

///|
/// Duplicate fd to specific number
pub fn native_dup2(oldfd : Int, newfd : Int) -> Bool {
  c_dup2(oldfd, newfd) >= 0
}

// ============================================================================
// Phase 4: Symlink operations
// ============================================================================

///|
/// Create symbolic link
#borrow(target, linkpath)
extern "c" fn c_symlinkat(
  target : FixedArray[Byte],
  dirfd : Int,
  linkpath : FixedArray[Byte],
) -> Int = "wasmoon_wasi_symlinkat"

///|
/// Read symbolic link
#borrow(path, buf)
extern "c" fn c_readlinkat(
  dirfd : Int,
  path : FixedArray[Byte],
  buf : FixedArray[Byte],
  bufsize : Int64,
) -> Int64 = "wasmoon_wasi_readlinkat"

///|
/// Create hard link
#borrow(oldpath, newpath)
extern "c" fn c_linkat(
  olddirfd : Int,
  oldpath : FixedArray[Byte],
  newdirfd : Int,
  newpath : FixedArray[Byte],
  flags : Int,
) -> Int = "wasmoon_wasi_linkat"

///|
/// Create symbolic link
pub fn native_symlinkat(
  target : String,
  dirfd : Int,
  linkpath : String,
) -> Bool {
  let target_bytes = string_to_cstring(target)
  let linkpath_bytes = string_to_cstring(linkpath)
  c_symlinkat(target_bytes, dirfd, linkpath_bytes) == 0
}

///|
/// Read symbolic link
pub fn native_readlinkat(dirfd : Int, path : String, bufsize : Int) -> String? {
  let path_bytes = string_to_cstring(path)
  let buf = FixedArray::make(bufsize, b'\x00')
  let result = c_readlinkat(dirfd, path_bytes, buf, bufsize.to_int64())
  if result < 0L {
    None
  } else {
    let len = result.to_int()
    let bytes = Bytes::makei(len, fn(i) { buf[i] })
    try @utf8.decode(bytes) catch {
      _ => None
    } noraise {
      target => Some(target)
    }
  }
}

///|
/// Create hard link
pub fn native_linkat(
  olddirfd : Int,
  oldpath : String,
  newdirfd : Int,
  newpath : String,
  flags : Int,
) -> Bool {
  let oldpath_bytes = string_to_cstring(oldpath)
  let newpath_bytes = string_to_cstring(newpath)
  c_linkat(olddirfd, oldpath_bytes, newdirfd, newpath_bytes, flags) == 0
}

// ============================================================================
// Phase 5: Poll and socket operations
// ============================================================================

///|
/// Nanosleep
extern "c" fn c_nanosleep(ns : Int64) -> Int = "wasmoon_wasi_nanosleep"

///|
/// Get monotonic time in nanoseconds
extern "c" fn c_clock_gettime_monotonic() -> Int64 = "wasmoon_wasi_clock_gettime_monotonic"

///|
/// Get realtime in nanoseconds
extern "c" fn c_clock_gettime_realtime() -> Int64 = "wasmoon_wasi_clock_gettime_realtime"

///|
/// Get monotonic clock resolution in nanoseconds
extern "c" fn c_clock_getres_monotonic() -> Int64 = "wasmoon_wasi_clock_getres_monotonic"

///|
/// Get realtime clock resolution in nanoseconds
extern "c" fn c_clock_getres_realtime() -> Int64 = "wasmoon_wasi_clock_getres_realtime"

///|
/// Poll on file descriptors
#borrow(fds, events, revents)
extern "c" fn c_poll(
  fds : FixedArray[Int],
  events : FixedArray[Int],
  revents : FixedArray[Int],
  nfds : Int,
  timeout_ms : Int,
) -> Int = "wasmoon_wasi_poll"

///|
extern "c" fn c_socket_bytes_available(fd : Int) -> Int64 = "wasmoon_wasi_socket_bytes_available"

///|
extern "c" fn c_socket_create(family : Int, kind : Int) -> Int = "wasmoon_wasi_socket_create"

///|
#borrow(address)
extern "c" fn c_socket_bind(
  fd : Int,
  family : Int,
  address : FixedArray[Byte],
  port : Int,
  scope_id : Int,
) -> Int = "wasmoon_wasi_socket_bind"

///|
#borrow(address)
extern "c" fn c_socket_connect(
  fd : Int,
  family : Int,
  address : FixedArray[Byte],
  port : Int,
  scope_id : Int,
) -> Int = "wasmoon_wasi_socket_connect"

///|
extern "c" fn c_socket_disconnect(fd : Int) -> Int = "wasmoon_wasi_socket_disconnect"

///|
#borrow(data, family, address, port, scope_id)
extern "c" fn c_socket_recv_from(
  fd : Int,
  data : FixedArray[Byte],
  length : Int,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  port : FixedArray[UInt16],
  scope_id : FixedArray[UInt],
) -> Int64 = "wasmoon_wasi_socket_recv_from"

///|
#borrow(data, address)
extern "c" fn c_socket_send_to(
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
extern "c" fn c_socket_listen(fd : Int, backlog : Int) -> Int = "wasmoon_wasi_socket_listen"

///|
extern "c" fn c_socket_error(fd : Int) -> Int = "wasmoon_wasi_socket_error"

///|
#borrow(family, address, port, scope_id)
extern "c" fn c_socket_address_get(
  fd : Int,
  peer : Int,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  port : FixedArray[UInt16],
  scope_id : FixedArray[UInt],
) -> Int = "wasmoon_wasi_socket_address_get"

///|
extern "c" fn c_socket_option_get(fd : Int, family : Int, option : Int) -> Int = "wasmoon_wasi_socket_option_get"

///|
extern "c" fn c_socket_option_set(
  fd : Int,
  family : Int,
  option : Int,
  value : Int,
) -> Int = "wasmoon_wasi_socket_option_set"

///|
#borrow(name, poll_fd)
extern "c" fn c_resolver_start(
  name : FixedArray[Byte],
  poll_fd : FixedArray[Int],
) -> Int64 = "wasmoon_wasi_resolver_start"

///|
#borrow(family, address, scope_id)
extern "c" fn c_resolver_next(
  resolver : Int64,
  family : FixedArray[Byte],
  address : FixedArray[Byte],
  scope_id : FixedArray[UInt],
) -> Int = "wasmoon_wasi_resolver_next"

///|
extern "c" fn c_resolver_drop(resolver : Int64) = "wasmoon_wasi_resolver_drop"

///|
extern "c" fn c_active_jit_context_ptr() -> Int64 = "wasmoon_jit_active_context_ptr"

///|
extern "c" fn c_jit_poll_resolve_fd(
  context : Int64,
  fd : Int,
  event_type : Int,
) -> Int = "wasmoon_jit_poll_resolve_fd"

///|
extern "c" fn c_jit_poll_fd_read_nbytes(context : Int64, fd : Int) -> Int64 = "wasmoon_jit_poll_fd_read_nbytes"

///|
extern "c" fn c_jit_poll_fd_read_flags(context : Int64, fd : Int) -> Int = "wasmoon_jit_poll_fd_read_flags"

///|
/// Socket recv
#borrow(buf)
extern "c" fn c_recv(
  sockfd : Int,
  buf : FixedArray[Byte],
  len : Int64,
  flags : Int,
) -> Int64 = "wasmoon_wasi_recv"

///|
/// Socket send
#borrow(buf)
extern "c" fn c_send(
  sockfd : Int,
  buf : FixedArray[Byte],
  len : Int64,
  flags : Int,
) -> Int64 = "wasmoon_wasi_send"

///|
/// Socket shutdown
extern "c" fn c_shutdown(sockfd : Int, how : Int) -> Int = "wasmoon_wasi_shutdown"

///|
/// Socket accept
extern "c" fn c_accept(sockfd : Int) -> Int = "wasmoon_wasi_accept"

///|
/// Raise signal
extern "c" fn c_raise(sig : Int) -> Int = "wasmoon_wasi_raise"

///|
/// Nanosleep
pub fn native_nanosleep(ns : Int64) -> Bool {
  c_nanosleep(ns) == 0
}

///|
/// Get monotonic time in nanoseconds
pub fn native_clock_gettime_monotonic() -> Int64 {
  c_clock_gettime_monotonic()
}

///|
/// Get realtime in nanoseconds
pub fn native_clock_gettime_realtime() -> Int64 {
  c_clock_gettime_realtime()
}

///|
/// Get monotonic clock resolution in nanoseconds
pub fn native_clock_getres_monotonic() -> Int64? {
  let res = c_clock_getres_monotonic()
  if res < 0L {
    None
  } else {
    Some(res)
  }
}

///|
/// Get realtime clock resolution in nanoseconds
pub fn native_clock_getres_realtime() -> Int64? {
  let res = c_clock_getres_realtime()
  if res < 0L {
    None
  } else {
    Some(res)
  }
}

///|
/// Poll result
pub(all) struct PollResult {
  ready_count : Int
  revents : Array[Int]
}

///|
/// Poll on file descriptors
pub fn native_poll(
  fds : Array[Int],
  events : Array[Int],
  timeout_ms : Int,
) -> PollResult? {
  let nfds = fds.length()
  if nfds == 0 || nfds != events.length() {
    return None
  }
  let fds_arr = FixedArray::make(nfds, 0)
  let events_arr = FixedArray::make(nfds, 0)
  let revents_arr = FixedArray::make(nfds, 0)
  for i in 0..<nfds {
    fds_arr[i] = fds[i]
    events_arr[i] = events[i]
  }
  let result = c_poll(fds_arr, events_arr, revents_arr, nfds, timeout_ms)
  if result < 0 {
    None
  } else {
    let revents : Array[Int] = []
    for i in 0..<nfds {
      revents.push(revents_arr[i])
    }
    Some({ ready_count: result, revents })
  }
}

///|
fn native_socket_bytes_available(fd : Int) -> Int64? {
  let available = c_socket_bytes_available(fd)
  if available < 0L {
    None
  } else {
    Some(available)
  }
}

///|
pub(all) struct NativeSocketAddress {
  family : Int
  address : FixedArray[Byte]
  port : Int
  scope_id : Int
}

///|
pub fn native_socket_create(family : Int, kind : Int) -> Int? {
  let fd = c_socket_create(family, kind)
  if fd < 0 {
    None
  } else {
    Some(fd)
  }
}

///|
pub fn native_socket_bind(fd : Int, address : NativeSocketAddress) -> Bool {
  c_socket_bind(
    fd,
    address.family,
    address.address,
    address.port,
    address.scope_id,
  ) ==
  0
}

///|
pub fn native_socket_connect(fd : Int, address : NativeSocketAddress) -> Int {
  c_socket_connect(
    fd,
    address.family,
    address.address,
    address.port,
    address.scope_id,
  )
}

///|
pub fn native_socket_disconnect(fd : Int) -> Bool {
  c_socket_disconnect(fd) == 0
}

///|
pub(all) struct NativeSocketDatagram {
  data : Bytes
  address : NativeSocketAddress
}

///|
pub fn native_socket_recv_from(
  fd : Int,
  capacity : Int,
) -> NativeSocketDatagram? {
  if capacity < 0 {
    return None
  }
  let data = FixedArray::make(capacity, b'\x00')
  let family = FixedArray::make(1, b'\x00')
  let address = FixedArray::make(16, b'\x00')
  let port : FixedArray[UInt16] = FixedArray::make(1, 0)
  let scope_id = FixedArray::make(1, 0U)
  let received = c_socket_recv_from(
    fd, data, capacity, family, address, port, scope_id,
  )
  if received < 0L || received > capacity.to_int64() {
    None
  } else {
    let bytes : Array[Byte] = []
    for i in 0..<received.to_int() {
      bytes.push(data[i])
    }
    Some({
      data: Bytes::from_array(bytes),
      address: {
        family: family[0].to_int(),
        address,
        port: port[0].to_uint().reinterpret_as_int(),
        scope_id: scope_id[0].reinterpret_as_int(),
      },
    })
  }
}

///|
pub fn native_socket_send_to(
  fd : Int,
  data : FixedArray[Byte],
  address : NativeSocketAddress?,
) -> Int64 {
  match address {
    Some(address) =>
      c_socket_send_to(
        fd,
        data,
        data.length(),
        1,
        address.family,
        address.address,
        address.port,
        address.scope_id,
      )
    None =>
      c_socket_send_to(
        fd,
        data,
        data.length(),
        0,
        4,
        FixedArray::make(4, b'\x00'),
        0,
        0,
      )
  }
}

///|
pub fn native_socket_listen(fd : Int, backlog : Int) -> Bool {
  c_socket_listen(fd, backlog) == 0
}

///|
pub fn native_socket_error(fd : Int) -> Int? {
  let error = c_socket_error(fd)
  if error < 0 {
    None
  } else {
    Some(error)
  }
}

///|
pub fn native_socket_address(fd : Int, peer : Bool) -> NativeSocketAddress? {
  let family = FixedArray::make(1, b'\x00')
  let address = FixedArray::make(16, b'\x00')
  let port : FixedArray[UInt16] = FixedArray::make(1, 0)
  let scope_id = FixedArray::make(1, 0U)
  if c_socket_address_get(
      fd,
      if peer {
        1
      } else {
        0
      },
      family,
      address,
      port,
      scope_id,
    ) ==
    0 {
    Some({
      family: family[0].to_int(),
      address,
      port: port[0].to_uint().reinterpret_as_int(),
      scope_id: scope_id[0].reinterpret_as_int(),
    })
  } else {
    None
  }
}

///|
pub fn native_socket_option_get(fd : Int, family : Int, option : Int) -> Int? {
  let value = c_socket_option_get(fd, family, option)
  if value < 0 {
    None
  } else {
    Some(value)
  }
}

///|
pub fn native_socket_option_set(
  fd : Int,
  family : Int,
  option : Int,
  value : Int,
) -> Bool {
  c_socket_option_set(fd, family, option, value) == 0
}

///|
pub(all) struct NativeResolver {
  handle : Int64
  poll_fd : Int
}

///|
pub fn native_resolver_start(name : String) -> NativeResolver? {
  let poll_fd = FixedArray::make(1, -1)
  let handle = c_resolver_start(string_to_cstring(name), poll_fd)
  if handle == 0L || poll_fd[0] < 0 {
    None
  } else {
    Some({ handle, poll_fd: poll_fd[0] })
  }
}

///|
pub(all) enum NativeResolverNext {
  Address(NativeSocketAddress)
  Pending
  Finished
  NameUnresolvable
  TemporaryFailure
  PermanentFailure
}

///|
pub fn native_resolver_next(resolver : Int64) -> NativeResolverNext {
  let family = FixedArray::make(1, b'\x00')
  let address = FixedArray::make(16, b'\x00')
  let scope_id = FixedArray::make(1, 0U)
  match c_resolver_next(resolver, family, address, scope_id) {
    0 =>
      Address({
        family: family[0].to_int(),
        address,
        port: 0,
        scope_id: scope_id[0].reinterpret_as_int(),
      })
    1 => Pending
    2 => Finished
    3 => NameUnresolvable
    4 => TemporaryFailure
    _ => PermanentFailure
  }
}

///|
pub fn native_resolver_drop(resolver : Int64) -> Unit {
  c_resolver_drop(resolver)
}

///|
fn active_jit_context_ptr() -> Int64 {
  c_active_jit_context_ptr()
}

///|
fn jit_poll_resolve_fd(context : Int64, fd : Int, event_type : Int) -> Int {
  c_jit_poll_resolve_fd(context, fd, event_type)
}

///|
fn jit_poll_fd_read_nbytes(context : Int64, fd : Int) -> Int64 {
  c_jit_poll_fd_read_nbytes(context, fd)
}

///|
fn jit_poll_fd_read_flags(context : Int64, fd : Int) -> Int {
  c_jit_poll_fd_read_flags(context, fd)
}

///|
/// Socket recv
pub fn native_recv(sockfd : Int, buf : FixedArray[Byte], flags : Int) -> Int64 {
  c_recv(sockfd, buf, buf.length().to_int64(), flags)
}

///|
/// Socket send
pub fn native_send(
  sockfd : Int,
  buf : FixedArray[Byte],
  len : Int,
  flags : Int,
) -> Int64 {
  c_send(sockfd, buf, len.to_int64(), flags)
}

///|
/// Socket shutdown
pub fn native_shutdown(sockfd : Int, how : Int) -> Bool {
  c_shutdown(sockfd, how) == 0
}

///|
/// Socket accept - returns new socket fd or -1 on error
pub fn native_accept(sockfd : Int) -> Int {
  c_accept(sockfd)
}

///|
/// Raise signal
pub fn native_raise(sig : Int) -> Bool {
  c_raise(sig) == 0
}

// ============================================================================
// Random number generation
// ============================================================================

///|
/// Get random bytes from system
#borrow(buf)
extern "c" fn c_getrandom(buf : FixedArray[Byte], len : Int) -> Int = "wasmoon_wasi_getrandom"

///|
/// Get random bytes from system
/// Returns true on success
pub fn native_getrandom(buf : FixedArray[Byte], len : Int) -> Bool {
  c_getrandom(buf, len) == 0
}
