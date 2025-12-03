///|
/// Native FFI for file operations
/// These functions call C standard library functions

///|
/// Open a file
/// Returns file descriptor or -1 on error
#borrow(path)
extern "c" fn c_open(path : FixedArray[Byte], flags : Int, mode : Int) -> Int = "open"

///|
/// Close a file descriptor
extern "c" fn c_close(fd : Int) -> Int = "close"

///|
/// Read from a file descriptor
/// Returns number of bytes read, 0 for EOF, or -1 on error
#borrow(buf)
extern "c" fn c_read(fd : Int, buf : FixedArray[Byte], count : Int) -> Int = "read"

///|
/// Write to a file descriptor
/// Returns number of bytes written or -1 on error
#borrow(buf)
extern "c" fn c_write(fd : Int, buf : FixedArray[Byte], count : Int) -> Int = "write"

///|
/// Seek in a file
/// Returns new offset or -1 on error
extern "c" fn c_lseek(fd : Int, offset : Int64, whence : Int) -> Int64 = "lseek"

///|
/// File open flags (combined from macOS and Linux)
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
/// Convert OpenFlags to platform-specific int
/// macOS values (Darwin)
fn open_flags_to_int(flags : Array[OpenFlags]) -> Int {
  let mut result = 0
  for flag in flags {
    let v = match flag {
      ReadOnly => 0 // O_RDONLY
      WriteOnly => 1 // O_WRONLY
      ReadWrite => 2 // O_RDWR
      Create => 0x200 // O_CREAT on macOS
      Truncate => 0x400 // O_TRUNC on macOS
      Append => 0x8 // O_APPEND on macOS
      Exclusive => 0x800 // O_EXCL on macOS
      Directory => 0x100000 // O_DIRECTORY on macOS
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
/// Convert a MoonBit string to a null-terminated C string
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
