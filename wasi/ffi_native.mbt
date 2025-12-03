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
