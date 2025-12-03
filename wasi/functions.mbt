///|
/// WASI function implementations
/// These are the host functions that implement the wasi_snapshot_preview1 interface

///|
/// Error type for WASI process exit
pub(all) suberror WasiExit Int

///|
/// fd_write - Write data to a file descriptor using scatter/gather I/O
///
/// Params:
/// - fd: File descriptor
/// - iovs: Pointer to iovec array in memory
/// - iovs_len: Number of iovecs
/// - nwritten: Pointer to store number of bytes written
///
/// Returns: errno
pub fn fd_write(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  iovs : Int,
  iovs_len : Int,
  nwritten_ptr : Int,
) -> Int {
  // Validate fd
  let fd_val = Fd(fd)
  if fd_val != stdout && fd_val != stderr {
    return Errno::Badf.to_i32()
  }
  // Collect all data from iovecs
  let mut total_written = 0
  for i in 0..<iovs_len {
    // Each iovec is 8 bytes: buf (4) + buf_len (4)
    let iov_offset = iovs + i * 8
    let buf_ptr = mem.read_i32(iov_offset)
    let buf_len = mem.read_i32(iov_offset + 4)
    if buf_len > 0 {
      let data = mem.read_bytes(buf_ptr, buf_len)
      if fd_val == stdout {
        (ctx.stdout_callback)(data)
      } else {
        (ctx.stderr_callback)(data)
      }
      total_written = total_written + buf_len
    }
  }
  // Write total bytes written
  mem.write_i32(nwritten_ptr, total_written)
  Errno::Success.to_i32()
}

///|
/// fd_read - Read data from a file descriptor using scatter/gather I/O
///
/// Params:
/// - fd: File descriptor
/// - iovs: Pointer to iovec array in memory
/// - iovs_len: Number of iovecs
/// - nread: Pointer to store number of bytes read
///
/// Returns: errno
pub fn fd_read(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  iovs : Int,
  iovs_len : Int,
  nread_ptr : Int,
) -> Int {
  // Only stdin (fd 0) is supported for reading
  if fd != 0 {
    return Errno::Badf.to_i32()
  }
  // Get input data
  let input_data = (ctx.stdin_callback)()
  let mut total_read = 0
  let mut input_offset = 0
  for i in 0..<iovs_len {
    if input_offset >= input_data.length() {
      break
    }
    // Each iovec is 8 bytes: buf (4) + buf_len (4)
    let iov_offset = iovs + i * 8
    let buf_ptr = mem.read_i32(iov_offset)
    let buf_len = mem.read_i32(iov_offset + 4)
    // Copy data to buffer
    let to_copy = @cmp.minimum(buf_len, input_data.length() - input_offset)
    for j in 0..<to_copy {
      mem.write_byte(buf_ptr + j, input_data[input_offset + j])
    }
    input_offset = input_offset + to_copy
    total_read = total_read + to_copy
  }
  // Write total bytes read
  mem.write_i32(nread_ptr, total_read)
  Errno::Success.to_i32()
}

///|
/// args_sizes_get - Get sizes of command-line arguments
///
/// Params:
/// - argc: Pointer to store argument count
/// - argv_buf_size: Pointer to store total size of argument strings
///
/// Returns: errno
pub fn args_sizes_get(
  ctx : WasiContext,
  mem : @runtime.Memory,
  argc_ptr : Int,
  argv_buf_size_ptr : Int,
) -> Int {
  let argc = ctx.args.length()
  let mut buf_size = 0
  for arg in ctx.args {
    buf_size = buf_size + arg.length() + 1 // +1 for null terminator
  }
  mem.write_i32(argc_ptr, argc)
  mem.write_i32(argv_buf_size_ptr, buf_size)
  Errno::Success.to_i32()
}

///|
/// args_get - Get command-line arguments
///
/// Params:
/// - argv: Pointer to array of string pointers
/// - argv_buf: Pointer to buffer for argument strings
///
/// Returns: errno
pub fn args_get(
  ctx : WasiContext,
  mem : @runtime.Memory,
  argv_ptr : Int,
  argv_buf_ptr : Int,
) -> Int {
  let mut buf_offset = 0
  for i, arg in ctx.args {
    // Write pointer to this argument
    mem.write_i32(argv_ptr + i * 4, argv_buf_ptr + buf_offset)
    // Write argument string (null-terminated)
    for j in 0..<arg.length() {
      let c = arg.code_unit_at(j) // String[Int] returns Int (char code)
      mem.write_byte(argv_buf_ptr + buf_offset + j, c.to_byte())
    }
    mem.write_byte(argv_buf_ptr + buf_offset + arg.length(), b'\x00')
    buf_offset = buf_offset + arg.length() + 1
  }
  Errno::Success.to_i32()
}

///|
/// environ_sizes_get - Get sizes of environment variables
///
/// Params:
/// - environc: Pointer to store environment variable count
/// - environ_buf_size: Pointer to store total size of environment strings
///
/// Returns: errno
pub fn environ_sizes_get(
  ctx : WasiContext,
  mem : @runtime.Memory,
  environc_ptr : Int,
  environ_buf_size_ptr : Int,
) -> Int {
  let environc = ctx.env.length()
  let mut buf_size = 0
  for env in ctx.env {
    buf_size = buf_size + env.length() + 1 // +1 for null terminator
  }
  mem.write_i32(environc_ptr, environc)
  mem.write_i32(environ_buf_size_ptr, buf_size)
  Errno::Success.to_i32()
}

///|
/// environ_get - Get environment variables
///
/// Params:
/// - environ: Pointer to array of string pointers
/// - environ_buf: Pointer to buffer for environment strings
///
/// Returns: errno
pub fn environ_get(
  ctx : WasiContext,
  mem : @runtime.Memory,
  environ_ptr : Int,
  environ_buf_ptr : Int,
) -> Int {
  let mut buf_offset = 0
  for i, env in ctx.env {
    // Write pointer to this environment variable
    mem.write_i32(environ_ptr + i * 4, environ_buf_ptr + buf_offset)
    // Write environment string (null-terminated)
    for j in 0..<env.length() {
      let c = env.code_unit_at(j) // String[Int] returns Int (char code)
      mem.write_byte(environ_buf_ptr + buf_offset + j, c.to_byte())
    }
    mem.write_byte(environ_buf_ptr + buf_offset + env.length(), b'\x00')
    buf_offset = buf_offset + env.length() + 1
  }
  Errno::Success.to_i32()
}

///|
/// proc_exit - Terminate the process
///
/// Params:
/// - exit_code: Exit code
///
/// This function does not return - it raises WasiExit
pub fn proc_exit(ctx : WasiContext, exit_code : Int) -> Unit raise WasiExit {
  ctx.exit_code = Some(exit_code)
  raise WasiExit(exit_code)
}

///|
/// clock_time_get - Get the current time
///
/// Params:
/// - clock_id: Clock identifier
/// - precision: Precision hint (ignored)
/// - time: Pointer to store timestamp (nanoseconds)
///
/// Returns: errno
pub fn clock_time_get(
  mem : @runtime.Memory,
  clock_id : Int,
  _precision : Int64,
  time_ptr : Int,
) -> Int {
  let clock = ClockId::from_i32(clock_id)
  if clock is None {
    return Errno::Inval.to_i32()
  }
  // Get current time in nanoseconds
  // For now, we return a monotonically increasing value based on a counter
  // In a real implementation, this would call system time functions
  let time_ns = get_current_time_ns()
  mem.write_i64(time_ptr, time_ns)
  Errno::Success.to_i32()
}

///|
/// Simple time counter (placeholder for real system time)
let time_counter : Ref[Int64] = { val: 0L }

///|
fn get_current_time_ns() -> Int64 {
  // Increment counter to simulate time passing
  // In real implementation, use platform-specific time APIs
  time_counter.val = time_counter.val + 1000000L // 1ms increments
  time_counter.val
}

///|
/// fd_prestat_get - Get prestat information for a preopened file descriptor
///
/// Returns: errno
pub fn fd_prestat_get(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  prestat_ptr : Int,
) -> Int {
  // Find preopen for this fd
  for preopen in ctx.preopens {
    let (preopen_fd, _, guest_path) = preopen
    if preopen_fd.to_int() == fd {
      // Write prestat struct: tag (1 byte) + padding (3 bytes) + pr_name_len (4 bytes)
      mem.write_byte(prestat_ptr, b'\x00') // tag = dir
      mem.write_byte(prestat_ptr + 1, b'\x00')
      mem.write_byte(prestat_ptr + 2, b'\x00')
      mem.write_byte(prestat_ptr + 3, b'\x00')
      mem.write_i32(prestat_ptr + 4, guest_path.length())
      return Errno::Success.to_i32()
    }
  }
  Errno::Badf.to_i32()
}

///|
/// fd_prestat_dir_name - Get the directory name of a preopened directory
///
/// Returns: errno
pub fn fd_prestat_dir_name(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  path_ptr : Int,
  path_len : Int,
) -> Int {
  // Find preopen for this fd
  for preopen in ctx.preopens {
    let (preopen_fd, _, guest_path) = preopen
    if preopen_fd.to_int() == fd {
      let to_copy = @cmp.minimum(path_len, guest_path.length())
      for i in 0..<to_copy {
        mem.write_byte(path_ptr + i, guest_path.code_unit_at(i).to_byte())
      }
      return Errno::Success.to_i32()
    }
  }
  Errno::Badf.to_i32()
}

///|
/// fd_close - Close a file descriptor
///
/// Returns: errno
pub fn fd_close(ctx : WasiContext, fd : Int) -> Int {
  // stdin, stdout, stderr cannot be closed
  if fd < 3 {
    return Errno::Badf.to_i32()
  }
  // Close the file and remove from tracking
  if ctx.close_fd(fd) {
    Errno::Success.to_i32()
  } else {
    Errno::Badf.to_i32()
  }
}

///|
/// random_get - Generate random bytes
///
/// Returns: errno
pub fn random_get(mem : @runtime.Memory, buf_ptr : Int, buf_len : Int) -> Int {
  // Simple PRNG for now (not cryptographically secure)
  let seed : Ref[Int] = { val: 12345 }
  for i in 0..<buf_len {
    seed.val = (seed.val * 1103515245 + 12345) & 0x7FFFFFFF
    mem.write_byte(buf_ptr + i, (seed.val % 256).to_byte())
  }
  Errno::Success.to_i32()
}

///|
/// path_open - Open a file or directory
///
/// Params:
/// - fd: Directory fd to open relative to
/// - dirflags: Path lookup flags
/// - path: Path pointer in memory
/// - path_len: Path length
/// - oflags: Open flags
/// - fs_rights_base: Requested rights
/// - fs_rights_inheriting: Inherited rights
/// - fdflags: FD flags
/// - opened_fd: Pointer to store opened fd
///
/// Returns: errno
pub fn path_open(
  ctx : WasiContext,
  mem : @runtime.Memory,
  dir_fd : Int,
  _dirflags : Int,
  path_ptr : Int,
  path_len : Int,
  oflags : Int,
  _fs_rights_base : Int64,
  _fs_rights_inheriting : Int64,
  fdflags : Int,
  opened_fd_ptr : Int,
) -> Int {
  // Read path from memory
  let path = read_string_from_memory(mem, path_ptr, path_len)
  // Resolve the full host path
  let host_path = ctx.resolve_path(dir_fd, path)
  if host_path is None {
    return Errno::Badf.to_i32()
  }
  let resolved_path = host_path.unwrap()
  // Determine open flags
  let open_flags : Array[OpenFlags] = []
  // WASI oflags:
  // 0x01 = O_CREAT, 0x02 = O_DIRECTORY, 0x04 = O_EXCL, 0x08 = O_TRUNC
  if (oflags & 0x01) != 0 {
    open_flags.push(Create)
  }
  if (oflags & 0x02) != 0 {
    open_flags.push(Directory)
  }
  if (oflags & 0x04) != 0 {
    open_flags.push(Exclusive)
  }
  if (oflags & 0x08) != 0 {
    open_flags.push(Truncate)
  }
  // WASI fdflags:
  // 0x01 = APPEND, 0x02 = DSYNC, 0x04 = NONBLOCK, 0x08 = RSYNC, 0x10 = SYNC
  if (fdflags & 0x01) != 0 {
    open_flags.push(Append)
  }
  // Default to read-write if creating, read-only otherwise
  if open_flags.is_empty() || (oflags & 0x02) != 0 {
    open_flags.push(ReadOnly)
  } else {
    open_flags.push(ReadWrite)
  }
  // Open the file
  let native_fd = native_open(resolved_path, open_flags, 0o644)
  if native_fd is None {
    return Errno::NoEnt.to_i32()
  }
  let nfd = native_fd.unwrap()
  // Determine file type
  let file_type : FileType = if (oflags & 0x02) != 0 {
    Directory
  } else {
    RegularFile
  }
  // Allocate WASI fd
  let wasi_fd = ctx.alloc_fd({
    native_fd: nfd,
    file_type,
    host_path: resolved_path,
    position: 0L,
    flags: oflags,
  })
  // Write opened fd to memory
  mem.write_i32(opened_fd_ptr, wasi_fd)
  Errno::Success.to_i32()
}

///|
/// fd_seek - Move file cursor
///
/// Params:
/// - fd: File descriptor
/// - offset: Offset to seek
/// - whence: 0=SET, 1=CUR, 2=END
/// - newoffset: Pointer to store new offset
///
/// Returns: errno
pub fn fd_seek(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  offset : Int64,
  whence : Int,
  newoffset_ptr : Int,
) -> Int {
  // stdin, stdout, stderr don't support seeking
  if fd < 3 {
    return Errno::SPipe.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  // Convert WASI whence to native
  let native_whence : Whence = match whence {
    0 => Set
    1 => Cur
    2 => End
    _ => return Errno::Inval.to_i32()
  }
  let new_pos = native_seek(f.native_fd, offset, native_whence)
  if new_pos is None {
    return Errno::IO.to_i32()
  }
  let pos = new_pos.unwrap()
  f.position = pos
  mem.write_i64(newoffset_ptr, pos)
  Errno::Success.to_i32()
}

///|
/// fd_tell - Get current file cursor position
///
/// Params:
/// - fd: File descriptor
/// - offset: Pointer to store offset
///
/// Returns: errno
pub fn fd_tell(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  offset_ptr : Int,
) -> Int {
  // stdin, stdout, stderr don't support tell
  if fd < 3 {
    return Errno::SPipe.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  let pos = native_tell(f.native_fd)
  if pos is None {
    return Errno::IO.to_i32()
  }
  let p = pos.unwrap()
  f.position = p
  mem.write_i64(offset_ptr, p)
  Errno::Success.to_i32()
}

///|
/// fd_pread - Read from a file at a specific offset (without moving cursor)
///
/// Params:
/// - fd: File descriptor
/// - iovs: IO vectors pointer
/// - iovs_len: Number of IO vectors
/// - offset: File offset to read from
/// - nread: Pointer to store bytes read
///
/// Returns: errno
pub fn fd_pread(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  iovs : Int,
  iovs_len : Int,
  offset : Int64,
  nread_ptr : Int,
) -> Int {
  if fd < 3 {
    return Errno::SPipe.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  // Save current position
  let saved_pos = native_tell(f.native_fd)
  if saved_pos is None {
    return Errno::IO.to_i32()
  }
  // Seek to offset
  let seek_result = native_seek(f.native_fd, offset, Set)
  if seek_result is None {
    return Errno::IO.to_i32()
  }
  // Read data
  let mut total_read = 0
  for i in 0..<iovs_len {
    let iov_offset = iovs + i * 8
    let buf_ptr = mem.read_i32(iov_offset)
    let buf_len = mem.read_i32(iov_offset + 4)
    if buf_len > 0 {
      let buf = FixedArray::make(buf_len, b'\x00')
      let n = native_read(f.native_fd, buf, buf_len)
      if n is None {
        // Restore position and return error
        native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
        return Errno::IO.to_i32()
      }
      let bytes_read = n.unwrap()
      // Copy to WASM memory
      for j in 0..<bytes_read {
        mem.write_byte(buf_ptr + j, buf[j])
      }
      total_read = total_read + bytes_read
      if bytes_read < buf_len {
        break // EOF
      }
    }
  }
  // Restore position
  native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
  mem.write_i32(nread_ptr, total_read)
  Errno::Success.to_i32()
}

///|
/// fd_pwrite - Write to a file at a specific offset (without moving cursor)
///
/// Params:
/// - fd: File descriptor
/// - iovs: IO vectors pointer
/// - iovs_len: Number of IO vectors
/// - offset: File offset to write to
/// - nwritten: Pointer to store bytes written
///
/// Returns: errno
pub fn fd_pwrite(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  iovs : Int,
  iovs_len : Int,
  offset : Int64,
  nwritten_ptr : Int,
) -> Int {
  if fd < 3 {
    return Errno::SPipe.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  // Save current position
  let saved_pos = native_tell(f.native_fd)
  if saved_pos is None {
    return Errno::IO.to_i32()
  }
  // Seek to offset
  let seek_result = native_seek(f.native_fd, offset, Set)
  if seek_result is None {
    return Errno::IO.to_i32()
  }
  // Write data
  let mut total_written = 0
  for i in 0..<iovs_len {
    let iov_offset = iovs + i * 8
    let buf_ptr = mem.read_i32(iov_offset)
    let buf_len = mem.read_i32(iov_offset + 4)
    if buf_len > 0 {
      let buf = FixedArray::make(buf_len, b'\x00')
      // Copy from WASM memory
      for j in 0..<buf_len {
        buf[j] = mem.read_byte(buf_ptr + j)
      }
      let n = native_write(f.native_fd, buf, buf_len)
      if n is None {
        // Restore position and return error
        native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
        return Errno::IO.to_i32()
      }
      total_written = total_written + n.unwrap()
    }
  }
  // Restore position
  native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
  mem.write_i32(nwritten_ptr, total_written)
  Errno::Success.to_i32()
}

///|
/// Helper: Read a string from WASM memory
fn read_string_from_memory(
  mem : @runtime.Memory,
  ptr : Int,
  len : Int,
) -> String {
  let buf = StringBuilder::new()
  for i in 0..<len {
    let c = mem.read_byte(ptr + i).to_int()
    if c >= 32 && c < 127 {
      buf.write_char(c.unsafe_to_char())
    } else if c == 0 {
      break
    }
  }
  buf.to_string()
}
