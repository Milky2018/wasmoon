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
      Directory => 0 // Not commonly used, platform-dependent
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
/// Create a directory
/// Returns 0 on success, -1 on error
#borrow(path)
extern "c" fn c_mkdir(path : FixedArray[Byte], mode : Int) -> Int = "wasmoon_wasi_mkdir"

///|
/// Read directory entries
/// Returns serialized entries or null on error
#borrow(path)
extern "c" fn c_readdir(path : FixedArray[Byte]) -> Bytes? = "wasmoon_wasi_readdir"

///|
/// Create a directory
/// Returns true on success
pub fn native_mkdir(path : String, mode : Int) -> Bool {
  let path_bytes = string_to_cstring(path)
  c_mkdir(path_bytes, mode) == 0
}

///|
/// Read directory entries
/// Returns array of (name, is_dir) tuples or None on error
pub fn native_readdir(path : String) -> Array[(String, Bool)]? {
  let path_bytes = string_to_cstring(path)
  let result = c_readdir(path_bytes)
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
  let entries : Array[(String, Bool)] = []
  let mut offset = 4
  for _ in 0..<count {
    if offset >= bytes.length() {
      break
    }
    // Read is_dir
    let is_dir = bytes[offset].to_int() != 0
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
    let name_chars : Array[Char] = []
    for i in 0..<name_len {
      name_chars.push(bytes[offset + i].to_int().unsafe_to_char())
    }
    offset = offset + name_len
    entries.push((String::from_array(name_chars), is_dir))
  }
  Some(entries)
}

///|
/// Convert a MoonBit string to a null-terminated C string (UTF-8)
fn string_to_cstring(s : String) -> FixedArray[Byte] {
  let len = s.length()
  // Estimate UTF-8 byte length (worst case: 4 bytes per char)
  let buf = FixedArray::make(len * 4 + 1, b'\x00')
  let mut pos = 0
  for i in 0..<len {
    let c = s.code_unit_at(i).to_int()
    if c < 0x80 {
      buf[pos] = c.to_byte()
      pos = pos + 1
    } else if c < 0x800 {
      buf[pos] = (0xC0 | (c >> 6)).to_byte()
      buf[pos + 1] = (0x80 | (c & 0x3F)).to_byte()
      pos = pos + 2
    } else if c >= 0xD800 && c <= 0xDBFF && i + 1 < len {
      // Surrogate pair
      let c2 = s.code_unit_at(i + 1).to_int()
      if c2 >= 0xDC00 && c2 <= 0xDFFF {
        let codepoint = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00)
        buf[pos] = (0xF0 | (codepoint >> 18)).to_byte()
        buf[pos + 1] = (0x80 | ((codepoint >> 12) & 0x3F)).to_byte()
        buf[pos + 2] = (0x80 | ((codepoint >> 6) & 0x3F)).to_byte()
        buf[pos + 3] = (0x80 | (codepoint & 0x3F)).to_byte()
        pos = pos + 4
      } else {
        // Invalid surrogate, encode as replacement character
        buf[pos] = b'\xEF'
        buf[pos + 1] = b'\xBF'
        buf[pos + 2] = b'\xBD'
        pos = pos + 3
      }
    } else {
      buf[pos] = (0xE0 | (c >> 12)).to_byte()
      buf[pos + 1] = (0x80 | ((c >> 6) & 0x3F)).to_byte()
      buf[pos + 2] = (0x80 | (c & 0x3F)).to_byte()
      pos = pos + 3
    }
  }
  buf[pos] = b'\x00' // Null terminator
  buf
}

///|
/// Convert UTF-8 bytes to a MoonBit string
fn utf8_bytes_to_string(bytes : Bytes) -> String {
  let len = bytes.length()
  let chars : Array[Char] = []
  let mut i = 0
  while i < len {
    let b = bytes[i].to_int()
    if b == 0 {
      break // Stop at null terminator
    }
    if b < 0x80 {
      chars.push(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xE0 && i + 1 < len {
      let c = ((b & 0x1F) << 6) | (bytes[i + 1].to_int() & 0x3F)
      chars.push(c.unsafe_to_char())
      i = i + 2
    } else if b < 0xF0 && i + 2 < len {
      let c = ((b & 0x0F) << 12) |
        ((bytes[i + 1].to_int() & 0x3F) << 6) |
        (bytes[i + 2].to_int() & 0x3F)
      chars.push(c.unsafe_to_char())
      i = i + 3
    } else if b < 0xF8 && i + 3 < len {
      let codepoint = ((b & 0x07) << 18) |
        ((bytes[i + 1].to_int() & 0x3F) << 12) |
        ((bytes[i + 2].to_int() & 0x3F) << 6) |
        (bytes[i + 3].to_int() & 0x3F)
      // Convert to surrogate pair
      let adjusted = codepoint - 0x10000
      chars.push((0xD800 + (adjusted >> 10)).unsafe_to_char())
      chars.push((0xDC00 + (adjusted & 0x3FF)).unsafe_to_char())
      i = i + 4
    } else {
      // Invalid UTF-8, skip byte
      i = i + 1
    }
  }
  String::from_array(chars)
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
    let chars : Array[Char] = []
    for i in 0..<len {
      chars.push(buf[i].to_int().unsafe_to_char())
    }
    Some(String::from_array(chars))
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
