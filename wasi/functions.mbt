///|
/// WASI function implementations
/// These are the host functions that implement the wasi_snapshot_preview1 interface

///|
/// Error type for WASI process exit
pub(all) suberror WasiExit {
  WasiExit(Int)
}

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
  let fd_val = Fd(fd)
  // Handle stdout/stderr
  if fd_val == stdout || fd_val == stderr {
    let mut total_written = 0
    for i in 0..<iovs_len {
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
    mem.write_i32(nwritten_ptr, total_written)
    return Errno::Success.to_i32()
  }
  // Handle opened files
  match ctx.open_files.get(fd) {
    Some(file_entry) => {
      let mut total_written = 0
      for i in 0..<iovs_len {
        let iov_offset = iovs + i * 8
        let buf_ptr = mem.read_i32(iov_offset)
        let buf_len = mem.read_i32(iov_offset + 4)
        if buf_len > 0 {
          // Create buffer and copy data
          let buf = FixedArray::make(buf_len, b'\x00')
          for j in 0..<buf_len {
            buf[j] = mem.read_byte(buf_ptr + j)
          }
          let written = native_write(file_entry.native_fd, buf, buf_len)
          match written {
            Some(n) => total_written = total_written + n
            None => {
              mem.write_i32(nwritten_ptr, total_written)
              return Errno::IO.to_i32()
            }
          }
        }
      }
      mem.write_i32(nwritten_ptr, total_written)
      Errno::Success.to_i32()
    }
    None => Errno::Badf.to_i32()
  }
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
  // Handle stdin
  if fd == 0 {
    let input_data = (ctx.stdin_callback)()
    let mut total_read = 0
    let mut input_offset = 0
    for i in 0..<iovs_len {
      if input_offset >= input_data.length() {
        break
      }
      let iov_offset = iovs + i * 8
      let buf_ptr = mem.read_i32(iov_offset)
      let buf_len = mem.read_i32(iov_offset + 4)
      let to_copy = @cmp.minimum(buf_len, input_data.length() - input_offset)
      for j in 0..<to_copy {
        mem.write_byte(buf_ptr + j, input_data[input_offset + j])
      }
      input_offset = input_offset + to_copy
      total_read = total_read + to_copy
    }
    mem.write_i32(nread_ptr, total_read)
    return Errno::Success.to_i32()
  }
  // Handle opened files
  match ctx.open_files.get(fd) {
    Some(file_entry) => {
      let mut total_read = 0
      for i in 0..<iovs_len {
        let iov_offset = iovs + i * 8
        let buf_ptr = mem.read_i32(iov_offset)
        let buf_len = mem.read_i32(iov_offset + 4)
        if buf_len > 0 {
          let read_result = native_read_to_memory(
            file_entry.native_fd,
            mem,
            buf_ptr,
            buf_len,
          )
          match read_result {
            Some(n) => {
              total_read = total_read + n
              if n < buf_len {
                break // EOF or partial read
              }
            }
            None => {
              mem.write_i32(nread_ptr, total_read)
              return Errno::IO.to_i32()
            }
          }
        }
      }
      mem.write_i32(nread_ptr, total_read)
      Errno::Success.to_i32()
    }
    None => Errno::Badf.to_i32()
  }
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
  // Get current time in nanoseconds using system clock
  let time_ns = match clock.unwrap() {
    Realtime => native_clock_gettime_realtime()
    Monotonic => native_clock_gettime_monotonic()
    // For process/thread CPU time, fall back to monotonic clock
    // since we don't have platform-specific APIs for these yet
    ProcessCPUTimeId | ThreadCPUTimeId => native_clock_gettime_monotonic()
  }
  mem.write_i64(time_ptr, time_ns)
  Errno::Success.to_i32()
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
      if path_len < guest_path.length() {
        return Errno::NameTooLong.to_i32()
      }
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
/// random_get - Generate random bytes using system entropy
///
/// Returns: errno
pub fn random_get(mem : @runtime.Memory, buf_ptr : Int, buf_len : Int) -> Int {
  if buf_len <= 0 {
    return Errno::Success.to_i32()
  }
  // Get random bytes from system
  let buf = FixedArray::make(buf_len, b'\x00')
  if native_getrandom(buf, buf_len) {
    // Copy to WASM memory
    for i in 0..<buf_len {
      mem.write_byte(buf_ptr + i, buf[i])
    }
    Errno::Success.to_i32()
  } else {
    // System random failed
    Errno::IO.to_i32()
  }
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
  fs_rights_base : Int64,
  fs_rights_inheriting : Int64,
  fdflags : Int,
  opened_fd_ptr : Int,
) -> Int {
  // Validate rights - only bits 0-28 are valid
  if !is_valid_rights(fs_rights_base) || !is_valid_rights(fs_rights_inheriting) {
    return Errno::Inval.to_i32()
  }
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
/// fd_fdstat_get - Get file descriptor status
///
/// Params:
/// - fd: File descriptor
/// - fdstat_ptr: Pointer to store fdstat struct
///
/// Returns: errno
///
/// fdstat struct layout (24 bytes):
/// - fs_filetype: u8 (1 byte)
/// - fs_flags: u16 (2 bytes, offset 2)
/// - fs_rights_base: u64 (8 bytes, offset 8)
/// - fs_rights_inheriting: u64 (8 bytes, offset 16)
pub fn fd_fdstat_get(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  fdstat_ptr : Int,
) -> Int {
  // Determine file type
  let (file_type, flags) : (Int, Int) = if fd == 0 {
    // stdin - character device, read-only
    (2, 0) // filetype=2 (character_device)
  } else if fd == 1 || fd == 2 {
    // stdout/stderr - character device, append
    (2, 1) // filetype=2, flags=append
  } else {
    match ctx.get_file(fd) {
      Some(file) => {
        let ft = match file.file_type {
          RegularFile => 4 // regular_file
          Directory => 3 // directory
          CharacterDevice => 2 // character_device
        }
        (ft, file.flags & 0x01) // preserve append flag
      }
      None => {
        // Check if it's a preopen directory
        for preopen in ctx.preopens {
          let (preopen_fd, _, _) = preopen
          if preopen_fd.to_int() == fd {
            return {
              // It's a preopen directory
              mem.write_byte(fdstat_ptr, b'\x03') // fs_filetype = directory (3)
              mem.write_byte(fdstat_ptr + 1, b'\x00') // padding
              mem.write_byte(fdstat_ptr + 2, b'\x00') // fs_flags low byte
              mem.write_byte(fdstat_ptr + 3, b'\x00') // fs_flags high byte
              mem.write_i32(fdstat_ptr + 4, 0) // padding
              mem.write_i64(fdstat_ptr + 8, 0x1FFFFFFFL) // fs_rights_base (all rights)
              mem.write_i64(fdstat_ptr + 16, 0x1FFFFFFFL) // fs_rights_inheriting
              Errno::Success.to_i32()
            }
          }
        }
        return Errno::Badf.to_i32()
      }
    }
  }
  // Write fdstat struct
  mem.write_byte(fdstat_ptr, file_type.to_byte()) // fs_filetype
  mem.write_byte(fdstat_ptr + 1, b'\x00') // padding
  mem.write_byte(fdstat_ptr + 2, (flags & 0xFF).to_byte()) // fs_flags low byte
  mem.write_byte(fdstat_ptr + 3, ((flags >> 8) & 0xFF).to_byte()) // fs_flags high byte
  mem.write_i32(fdstat_ptr + 4, 0) // padding
  mem.write_i64(fdstat_ptr + 8, 0x1FFFFFFFL) // fs_rights_base (all rights for simplicity)
  mem.write_i64(fdstat_ptr + 16, 0x1FFFFFFFL) // fs_rights_inheriting
  Errno::Success.to_i32()
}

///|
/// clock_res_get - Get clock resolution
///
/// Params:
/// - clock_id: Clock identifier
/// - resolution_ptr: Pointer to store resolution (nanoseconds)
///
/// Returns: errno
pub fn clock_res_get(
  mem : @runtime.Memory,
  clock_id : Int,
  resolution_ptr : Int,
) -> Int {
  let clock = ClockId::from_i32(clock_id)
  if clock is None {
    return Errno::Inval.to_i32()
  }
  // Return a reasonable resolution (1 millisecond = 1_000_000 nanoseconds)
  // In a real implementation, this would depend on the system clock
  mem.write_i64(resolution_ptr, 1000000L)
  Errno::Success.to_i32()
}

///|
/// sched_yield - Yield the processor
///
/// Returns: errno
pub fn sched_yield() -> Int {
  // In a single-threaded context, this is essentially a no-op
  // Just return success
  Errno::Success.to_i32()
}

///|
/// path_create_directory - Create a directory
///
/// Params:
/// - dir_fd: Directory fd to create relative to
/// - path_ptr: Path pointer in memory
/// - path_len: Path length
///
/// Returns: errno
pub fn path_create_directory(
  ctx : WasiContext,
  mem : @runtime.Memory,
  dir_fd : Int,
  path_ptr : Int,
  path_len : Int,
) -> Int {
  let path = read_string_from_memory(mem, path_ptr, path_len)
  let host_path = ctx.resolve_path(dir_fd, path)
  if host_path is None {
    return Errno::Badf.to_i32()
  }
  let resolved_path = host_path.unwrap()
  if native_mkdir(resolved_path, 0o755) {
    Errno::Success.to_i32()
  } else {
    Errno::IO.to_i32()
  }
}

///|
/// fd_readdir - Read directory entries
///
/// Params:
/// - fd: Directory file descriptor
/// - buf_ptr: Buffer pointer
/// - buf_len: Buffer length
/// - cookie: Directory cookie (position)
/// - bufused_ptr: Pointer to store bytes used
///
/// Returns: errno
pub fn fd_readdir(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  buf_ptr : Int,
  buf_len : Int,
  cookie : Int64,
  bufused_ptr : Int,
) -> Int {
  if fd < 3 {
    return Errno::Badf.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    // Check if it's a preopen directory
    for preopen in ctx.preopens {
      let (preopen_fd, host_path, _) = preopen
      if preopen_fd.to_int() == fd {
        return readdir_impl(
          mem, host_path, buf_ptr, buf_len, cookie, bufused_ptr,
        )
      }
    }
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  if f.file_type is Directory {
    readdir_impl(mem, f.host_path, buf_ptr, buf_len, cookie, bufused_ptr)
  } else {
    Errno::NotDir.to_i32()
  }
}

///|
/// Helper: Implement readdir
fn readdir_impl(
  mem : @runtime.Memory,
  dir_path : String,
  buf_ptr : Int,
  buf_len : Int,
  cookie : Int64,
  bufused_ptr : Int,
) -> Int {
  let entries = native_readdir(dir_path)
  if entries is None {
    mem.write_i32(bufused_ptr, 0)
    return Errno::IO.to_i32()
  }
  let dir_entries = entries.unwrap()
  let mut offset = 0
  let mut entry_idx = 0L
  for entry in dir_entries {
    let (name, is_dir) = entry
    // Skip entries before cookie
    if entry_idx < cookie {
      entry_idx = entry_idx + 1L
      continue
    }
    // dirent struct layout (24 bytes + name):
    // - d_next: u64 (8 bytes) - cookie of next entry
    // - d_ino: u64 (8 bytes) - inode number
    // - d_namlen: u32 (4 bytes) - name length
    // - d_type: u8 (1 byte) - file type
    // - padding: 3 bytes
    // - d_name: name bytes (variable)
    let entry_size = 24 + name.length()
    if offset + entry_size > buf_len {
      break // Buffer full
    }
    // Write dirent
    mem.write_i64(buf_ptr + offset, entry_idx + 1L) // d_next
    mem.write_i64(buf_ptr + offset + 8, entry_idx + 1L) // d_ino (use index as fake inode)
    mem.write_i32(buf_ptr + offset + 16, name.length()) // d_namlen
    let file_type : Int = if is_dir { 3 } else { 4 } // 3=directory, 4=regular_file
    mem.write_byte(buf_ptr + offset + 20, file_type.to_byte()) // d_type
    mem.write_byte(buf_ptr + offset + 21, b'\x00') // padding
    mem.write_byte(buf_ptr + offset + 22, b'\x00')
    mem.write_byte(buf_ptr + offset + 23, b'\x00')
    // Write name
    for i in 0..<name.length() {
      mem.write_byte(buf_ptr + offset + 24 + i, name.code_unit_at(i).to_byte())
    }
    offset = offset + entry_size
    entry_idx = entry_idx + 1L
  }
  mem.write_i32(bufused_ptr, offset)
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

// ============================================================================
// Phase 1: Core file operations
// ============================================================================

///|
/// fd_sync - Synchronize file to disk
pub fn fd_sync_impl(ctx : WasiContext, fd : Int) -> Int {
  // stdin, stdout, stderr - no-op, return success
  if fd < 3 {
    return Errno::Success.to_i32()
  }
  match ctx.get_file(fd) {
    Some(file) =>
      if native_fsync(file.native_fd) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

///|
/// fd_datasync - Synchronize file data to disk
pub fn fd_datasync_impl(ctx : WasiContext, fd : Int) -> Int {
  // stdin, stdout, stderr - no-op, return success
  if fd < 3 {
    return Errno::Success.to_i32()
  }
  match ctx.get_file(fd) {
    Some(file) =>
      if native_fdatasync(file.native_fd) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

///|
/// path_unlink_file - Delete a file
pub fn path_unlink_file_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  dir_fd : Int,
  path_ptr : Int,
  path_len : Int,
) -> Int {
  let path = read_string_from_memory(mem, path_ptr, path_len)
  let host_path = ctx.resolve_path(dir_fd, path)
  match host_path {
    Some(resolved) =>
      if native_unlinkat(0, resolved, 0) {
        Errno::Success.to_i32()
      } else {
        Errno::NoEnt.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

///|
/// path_remove_directory - Delete a directory
pub fn path_remove_directory_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  dir_fd : Int,
  path_ptr : Int,
  path_len : Int,
) -> Int {
  let path = read_string_from_memory(mem, path_ptr, path_len)
  let host_path = ctx.resolve_path(dir_fd, path)
  match host_path {
    Some(resolved) =>
      if native_unlinkat(0, resolved, AT_REMOVEDIR) {
        Errno::Success.to_i32()
      } else {
        Errno::NoEnt.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

///|
/// path_rename - Rename a file or directory
pub fn path_rename_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  old_fd : Int,
  old_path_ptr : Int,
  old_path_len : Int,
  new_fd : Int,
  new_path_ptr : Int,
  new_path_len : Int,
) -> Int {
  let old_path = read_string_from_memory(mem, old_path_ptr, old_path_len)
  let new_path = read_string_from_memory(mem, new_path_ptr, new_path_len)
  let old_host_path = ctx.resolve_path(old_fd, old_path)
  let new_host_path = ctx.resolve_path(new_fd, new_path)
  match (old_host_path, new_host_path) {
    (Some(old_resolved), Some(new_resolved)) =>
      if native_renameat(0, old_resolved, 0, new_resolved) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    _ => Errno::Badf.to_i32()
  }
}

// ============================================================================
// Phase 2: File metadata operations
// ============================================================================

///|
/// fd_filestat_get - Get file statistics via file descriptor
pub fn fd_filestat_get_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  buf_ptr : Int,
) -> Int {
  // Handle special fds (stdin, stdout, stderr)
  if fd < 3 {
    // Write a minimal filestat for character devices
    mem.write_i64(buf_ptr, 0L) // dev
    mem.write_i64(buf_ptr + 8, 0L) // ino
    mem.write_byte(buf_ptr + 16, b'\x02') // filetype = character_device
    for i in 17..<24 {
      mem.write_byte(buf_ptr + i, b'\x00')
    }
    mem.write_i64(buf_ptr + 24, 1L) // nlink
    mem.write_i64(buf_ptr + 32, 0L) // size
    mem.write_i64(buf_ptr + 40, 0L) // atim
    mem.write_i64(buf_ptr + 48, 0L) // mtim
    mem.write_i64(buf_ptr + 56, 0L) // ctim
    return Errno::Success.to_i32()
  }
  match ctx.get_file(fd) {
    Some(file) => {
      let stat = native_fstat(file.native_fd)
      match stat {
        Some(s) => {
          write_filestat(mem, buf_ptr, s)
          Errno::Success.to_i32()
        }
        None => Errno::IO.to_i32()
      }
    }
    None => {
      // Check if it's a preopen directory
      for preopen in ctx.preopens {
        let (preopen_fd, _, _) = preopen
        if preopen_fd.to_int() == fd {
          // Return directory stat
          mem.write_i64(buf_ptr, 0L) // dev
          mem.write_i64(buf_ptr + 8, fd.to_int64()) // ino (use fd as fake inode)
          mem.write_byte(buf_ptr + 16, b'\x03') // filetype = directory
          for i in 17..<24 {
            mem.write_byte(buf_ptr + i, b'\x00')
          }
          mem.write_i64(buf_ptr + 24, 1L) // nlink
          mem.write_i64(buf_ptr + 32, 0L) // size
          mem.write_i64(buf_ptr + 40, 0L) // atim
          mem.write_i64(buf_ptr + 48, 0L) // mtim
          mem.write_i64(buf_ptr + 56, 0L) // ctim
          return Errno::Success.to_i32()
        }
      }
      Errno::Badf.to_i32()
    }
  }
}

///|
/// Helper: Write filestat to memory
fn write_filestat(
  mem : @runtime.Memory,
  buf_ptr : Int,
  stat : FileStat,
) -> Unit {
  mem.write_i64(buf_ptr, stat.dev.reinterpret_as_int64()) // dev
  mem.write_i64(buf_ptr + 8, stat.ino.reinterpret_as_int64()) // ino
  mem.write_byte(buf_ptr + 16, stat.filetype.to_byte()) // filetype
  for i in 17..<24 {
    mem.write_byte(buf_ptr + i, b'\x00') // padding
  }
  mem.write_i64(buf_ptr + 24, stat.nlink.reinterpret_as_int64()) // nlink
  mem.write_i64(buf_ptr + 32, stat.size.reinterpret_as_int64()) // size
  mem.write_i64(buf_ptr + 40, stat.atim.reinterpret_as_int64()) // atim
  mem.write_i64(buf_ptr + 48, stat.mtim.reinterpret_as_int64()) // mtim
  mem.write_i64(buf_ptr + 56, stat.ctim.reinterpret_as_int64()) // ctim
}

///|
/// path_filestat_get - Get file statistics via path
pub fn path_filestat_get_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  dir_fd : Int,
  flags : Int,
  path_ptr : Int,
  path_len : Int,
  buf_ptr : Int,
) -> Int {
  let path = read_string_from_memory(mem, path_ptr, path_len)
  let host_path = ctx.resolve_path(dir_fd, path)
  match host_path {
    Some(resolved) => {
      // Convert WASI flags to native flags
      let native_flags = if (flags & 0x01) != 0 {
        0
      } else {
        AT_SYMLINK_NOFOLLOW
      }
      let stat = native_fstatat(0, resolved, native_flags)
      match stat {
        Some(s) => {
          write_filestat(mem, buf_ptr, s)
          Errno::Success.to_i32()
        }
        None => Errno::NoEnt.to_i32()
      }
    }
    None => Errno::Badf.to_i32()
  }
}

///|
/// fd_filestat_set_size - Set file size (truncate)
pub fn fd_filestat_set_size_impl(
  ctx : WasiContext,
  fd : Int,
  size : Int64,
) -> Int {
  if fd < 3 {
    return Errno::Inval.to_i32()
  }
  match ctx.get_file(fd) {
    Some(file) =>
      if native_ftruncate(file.native_fd, size) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

///|
/// fd_filestat_set_times - Set file times via fd
pub fn fd_filestat_set_times_impl(
  ctx : WasiContext,
  fd : Int,
  atim : Int64,
  mtim : Int64,
  fst_flags : Int,
) -> Int {
  if fd < 3 {
    return Errno::Inval.to_i32()
  }
  match ctx.get_file(fd) {
    Some(file) =>
      if native_futimens(file.native_fd, atim, mtim, fst_flags) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

///|
/// path_filestat_set_times - Set file times via path
pub fn path_filestat_set_times_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  dir_fd : Int,
  flags : Int,
  path_ptr : Int,
  path_len : Int,
  atim : Int64,
  mtim : Int64,
  fst_flags : Int,
) -> Int {
  let path = read_string_from_memory(mem, path_ptr, path_len)
  let host_path = ctx.resolve_path(dir_fd, path)
  match host_path {
    Some(resolved) => {
      let lookup_flags = if (flags & 0x01) != 0 {
        0
      } else {
        AT_SYMLINK_NOFOLLOW
      }
      if native_utimensat(0, resolved, atim, mtim, fst_flags, lookup_flags) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    }
    None => Errno::Badf.to_i32()
  }
}

// ============================================================================
// Phase 3: Auxiliary functions
// ============================================================================

///|
/// fd_advise - Advise on file access patterns (no-op)
pub fn fd_advise_impl(
  ctx : WasiContext,
  fd : Int,
  _offset : Int64,
  _len : Int64,
  _advice : Int,
) -> Int {
  // Check fd validity - stdio fds are valid, others must be in file table
  if fd >= 3 {
    match ctx.get_file(fd) {
      Some(_) => ()
      None => return Errno::Badf.to_i32()
    }
  }
  // Just return success - advice is optional
  Errno::Success.to_i32()
}

///|
/// fd_allocate - Allocate space for file
pub fn fd_allocate_impl(
  ctx : WasiContext,
  fd : Int,
  offset : Int64,
  len : Int64,
) -> Int {
  if fd < 3 {
    return Errno::Inval.to_i32()
  }
  match ctx.get_file(fd) {
    Some(file) => {
      // Use ftruncate as fallback (extend file if needed)
      let stat = native_fstat(file.native_fd)
      match stat {
        Some(s) => {
          let new_size = offset + len
          if new_size > s.size.reinterpret_as_int64() {
            if native_ftruncate(file.native_fd, new_size) {
              Errno::Success.to_i32()
            } else {
              Errno::IO.to_i32()
            }
          } else {
            Errno::Success.to_i32()
          }
        }
        None => Errno::IO.to_i32()
      }
    }
    None => Errno::Badf.to_i32()
  }
}

///|
/// fd_fdstat_set_flags - Set file descriptor flags
pub fn fd_fdstat_set_flags_impl(
  ctx : WasiContext,
  fd : Int,
  flags : Int,
) -> Int {
  // Get the native file descriptor
  let native_fd = if fd < 3 {
    // stdin/stdout/stderr map directly to native 0/1/2
    fd
  } else {
    match ctx.get_file(fd) {
      Some(file) => file.native_fd
      None => return Errno::Badf.to_i32()
    }
  }
  // Convert WASI fdflags to native flags
  // WASI: 0x01 = APPEND, 0x02 = DSYNC, 0x04 = NONBLOCK, 0x08 = RSYNC, 0x10 = SYNC
  let native_flags = native_fcntl_getfl(native_fd)
  match native_flags {
    Some(current) => {
      let mut new_flags = current
      // O_APPEND = 0x400 on Linux, 0x8 on macOS
      if (flags & 0x01) != 0 {
        new_flags = new_flags | 0x8 // O_APPEND
      } else {
        new_flags = new_flags & (0x8).lnot()
      }
      // O_NONBLOCK = 0x800 on Linux, 0x4 on macOS
      if (flags & 0x04) != 0 {
        new_flags = new_flags | 0x4 // O_NONBLOCK
      } else {
        new_flags = new_flags & (0x4).lnot()
      }
      if native_fcntl_setfl(native_fd, new_flags) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    }
    None => Errno::IO.to_i32()
  }
}

///|
/// fd_fdstat_set_rights - Set file descriptor rights (no-op)
pub fn fd_fdstat_set_rights_impl(
  _ctx : WasiContext,
  _fd : Int,
  _fs_rights_base : Int64,
  _fs_rights_inheriting : Int64,
) -> Int {
  // Rights management is simplified - just return success
  Errno::Success.to_i32()
}

///|
/// fd_renumber - Renumber file descriptor
pub fn fd_renumber_impl(ctx : WasiContext, from : Int, to : Int) -> Int {
  if from < 3 || to < 3 {
    return Errno::Inval.to_i32()
  }
  match ctx.get_file(from) {
    Some(file) =>
      if native_dup2(file.native_fd, to) {
        // Close the old fd and update tracking
        ctx.close_fd(from) |> ignore
        // Note: In a real implementation, we'd also update ctx.open_files
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

// ============================================================================
// Phase 4: Symlink operations
// ============================================================================

///|
/// path_symlink - Create symbolic link
pub fn path_symlink_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  old_path_ptr : Int,
  old_path_len : Int,
  dir_fd : Int,
  new_path_ptr : Int,
  new_path_len : Int,
) -> Int {
  let old_path = read_string_from_memory(mem, old_path_ptr, old_path_len)
  let new_path = read_string_from_memory(mem, new_path_ptr, new_path_len)
  let new_host_path = ctx.resolve_path(dir_fd, new_path)
  match new_host_path {
    Some(resolved) =>
      if native_symlinkat(old_path, 0, resolved) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

///|
/// path_readlink - Read symbolic link
pub fn path_readlink_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  dir_fd : Int,
  path_ptr : Int,
  path_len : Int,
  buf_ptr : Int,
  buf_len : Int,
  bufused_ptr : Int,
) -> Int {
  let path = read_string_from_memory(mem, path_ptr, path_len)
  let host_path = ctx.resolve_path(dir_fd, path)
  match host_path {
    Some(resolved) => {
      let result = native_readlinkat(0, resolved, buf_len)
      match result {
        Some(link_target) => {
          let to_write = @cmp.minimum(link_target.length(), buf_len)
          for i in 0..<to_write {
            mem.write_byte(buf_ptr + i, link_target.code_unit_at(i).to_byte())
          }
          mem.write_i32(bufused_ptr, to_write)
          Errno::Success.to_i32()
        }
        None => Errno::NoEnt.to_i32()
      }
    }
    None => Errno::Badf.to_i32()
  }
}

///|
/// path_link - Create hard link
pub fn path_link_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  old_fd : Int,
  old_flags : Int,
  old_path_ptr : Int,
  old_path_len : Int,
  new_fd : Int,
  new_path_ptr : Int,
  new_path_len : Int,
) -> Int {
  let old_path = read_string_from_memory(mem, old_path_ptr, old_path_len)
  let new_path = read_string_from_memory(mem, new_path_ptr, new_path_len)
  let old_host_path = ctx.resolve_path(old_fd, old_path)
  let new_host_path = ctx.resolve_path(new_fd, new_path)
  match (old_host_path, new_host_path) {
    (Some(old_resolved), Some(new_resolved)) => {
      let flags = if (old_flags & 0x01) != 0 { 0x1000 } else { 0 } // AT_SYMLINK_FOLLOW
      if native_linkat(0, old_resolved, 0, new_resolved, flags) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    }
    _ => Errno::Badf.to_i32()
  }
}

// ============================================================================
// Phase 5: Poll and socket operations
// ============================================================================

///|
/// poll_oneoff - Wait for events on subscriptions
///
/// WASI subscription structure (48 bytes):
/// - userdata: u64 (8 bytes)
/// - u: union (40 bytes):
///   - tag: u8 (1 byte) - 0=clock, 1=fd_read, 2=fd_write
///   - For clock (tag=0):
///     - padding: 7 bytes
///     - id: u32 (4 bytes) - clock id
///     - padding: 4 bytes
///     - timeout: u64 (8 bytes) - absolute or relative time in ns
///     - precision: u64 (8 bytes)
///     - flags: u16 (2 bytes) - 0=relative, 1=absolute
///   - For fd_read/fd_write (tag=1,2):
///     - padding: 3 bytes
///     - fd: u32 (4 bytes)
///
/// WASI event structure (32 bytes):
/// - userdata: u64 (8 bytes)
/// - error: u16 (2 bytes)
/// - type: u8 (1 byte)
/// - padding: 5 bytes
/// - fd_readwrite: (16 bytes)
///   - nbytes: u64 (8 bytes)
///   - flags: u16 (2 bytes)
pub fn poll_oneoff_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  in_ptr : Int,
  out_ptr : Int,
  nsubscriptions : Int,
  nevents_ptr : Int,
) -> Int {
  if nsubscriptions == 0 {
    mem.write_i32(nevents_ptr, 0)
    return Errno::Success.to_i32()
  }
  let mut events_written = 0
  let mut min_timeout_ns : Int64 = -1L
  // First pass: find minimum clock timeout
  for i in 0..<nsubscriptions {
    let sub_ptr = in_ptr + i * 48
    let tag = mem.read_byte(sub_ptr + 8).to_int()
    if tag == 0 {
      // Clock subscription
      let timeout = mem.read_i64(sub_ptr + 24)
      let flags = mem.read_byte(sub_ptr + 40).to_int()
      let timeout_ns = if (flags & 0x01) != 0 {
        // Absolute time - convert to relative
        let now = native_clock_gettime_monotonic()
        if timeout > now {
          timeout - now
        } else {
          0L
        }
      } else {
        timeout
      }
      if min_timeout_ns < 0L || timeout_ns < min_timeout_ns {
        min_timeout_ns = timeout_ns
      }
    }
  }
  // Collect fd subscriptions
  let fds : Array[Int] = []
  let events : Array[Int] = []
  let sub_indices : Array[Int] = []
  for i in 0..<nsubscriptions {
    let sub_ptr = in_ptr + i * 48
    let tag = mem.read_byte(sub_ptr + 8).to_int()
    if tag == 1 || tag == 2 {
      // fd_read or fd_write
      let fd = mem.read_i32(sub_ptr + 12)
      // Get native fd
      let native_fd = match ctx.get_file(fd) {
        Some(file) => file.native_fd
        None => -1
      }
      if native_fd >= 0 {
        fds.push(native_fd)
        // POLLIN = 0x01, POLLOUT = 0x04
        events.push(if tag == 1 { 0x01 } else { 0x04 })
        sub_indices.push(i)
      }
    }
  }
  // Calculate timeout in ms
  let timeout_ms = if min_timeout_ns < 0L {
    -1 // Infinite
  } else if min_timeout_ns == 0L {
    0
  } else {
    let ms = (min_timeout_ns / 1000000L).to_int()
    if ms == 0 {
      1
    } else {
      ms
    }
  }
  // Do the poll
  let mut clock_ready = false
  if fds.length() > 0 {
    let poll_result = native_poll(fds, events, timeout_ms)
    match poll_result {
      Some(result) => {
        if result.ready_count == 0 {
          clock_ready = true
        }
        // Write fd events
        for i, sub_idx in sub_indices {
          let revent = result.revents[i]
          if revent != 0 {
            let sub_ptr = in_ptr + sub_idx * 48
            let userdata = mem.read_i64(sub_ptr)
            let tag = mem.read_byte(sub_ptr + 8).to_int()
            let event_ptr = out_ptr + events_written * 32
            mem.write_i64(event_ptr, userdata)
            mem.write_byte(event_ptr + 8, b'\x00') // error = success
            mem.write_byte(event_ptr + 9, b'\x00')
            mem.write_byte(event_ptr + 10, tag.to_byte()) // type
            // padding
            for j in 11..<16 {
              mem.write_byte(event_ptr + j, b'\x00')
            }
            mem.write_i64(event_ptr + 16, 0L) // nbytes (unknown)
            mem.write_byte(event_ptr + 24, b'\x00') // flags
            mem.write_byte(event_ptr + 25, b'\x00')
            // padding
            for j in 26..<32 {
              mem.write_byte(event_ptr + j, b'\x00')
            }
            events_written = events_written + 1
          }
        }
      }
      None => ()
    }
  } else if min_timeout_ns >= 0L {
    // Just sleep
    native_nanosleep(min_timeout_ns) |> ignore
    clock_ready = true
  }
  // Write clock events when the timeout expires.
  if clock_ready {
    for i in 0..<nsubscriptions {
      let sub_ptr = in_ptr + i * 48
      let tag = mem.read_byte(sub_ptr + 8).to_int()
      if tag == 0 {
        let userdata = mem.read_i64(sub_ptr)
        let event_ptr = out_ptr + events_written * 32
        mem.write_i64(event_ptr, userdata)
        mem.write_byte(event_ptr + 8, b'\x00') // error = success
        mem.write_byte(event_ptr + 9, b'\x00')
        mem.write_byte(event_ptr + 10, b'\x00') // type = clock
        // padding
        for j in 11..<32 {
          mem.write_byte(event_ptr + j, b'\x00')
        }
        events_written = events_written + 1
      }
    }
  }
  mem.write_i32(nevents_ptr, events_written)
  Errno::Success.to_i32()
}

///|
/// sock_recv - Receive data from socket
pub fn sock_recv_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  ri_data_ptr : Int,
  ri_data_len : Int,
  ri_flags : Int,
  ro_datalen_ptr : Int,
  ro_flags_ptr : Int,
) -> Int {
  match ctx.get_file(fd) {
    Some(file) => {
      let mut total_read = 0L
      for i in 0..<ri_data_len {
        let iov_ptr = ri_data_ptr + i * 8
        let buf_ptr = mem.read_i32(iov_ptr)
        let buf_len = mem.read_i32(iov_ptr + 4)
        if buf_len > 0 {
          let buf = FixedArray::make(buf_len, b'\x00')
          // Convert WASI flags to native flags
          let native_flags = if (ri_flags & 0x01) != 0 { 0x02 } else { 0 } // MSG_PEEK
          let n = native_recv(file.native_fd, buf, native_flags)
          if n < 0L {
            if total_read > 0L {
              break
            }
            mem.write_i32(ro_datalen_ptr, 0)
            mem.write_byte(ro_flags_ptr, b'\x00')
            mem.write_byte(ro_flags_ptr + 1, b'\x00')
            return Errno::IO.to_i32()
          }
          // Copy to WASM memory
          for j in 0..<n.to_int() {
            mem.write_byte(buf_ptr + j, buf[j])
          }
          total_read = total_read + n
          if n < buf_len.to_int64() {
            break
          }
        }
      }
      mem.write_i32(ro_datalen_ptr, total_read.to_int())
      mem.write_byte(ro_flags_ptr, b'\x00')
      mem.write_byte(ro_flags_ptr + 1, b'\x00')
      Errno::Success.to_i32()
    }
    None => Errno::Badf.to_i32()
  }
}

///|
/// sock_send - Send data to socket
pub fn sock_send_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  si_data_ptr : Int,
  si_data_len : Int,
  _si_flags : Int,
  so_datalen_ptr : Int,
) -> Int {
  match ctx.get_file(fd) {
    Some(file) => {
      let mut total_sent = 0L
      for i in 0..<si_data_len {
        let iov_ptr = si_data_ptr + i * 8
        let buf_ptr = mem.read_i32(iov_ptr)
        let buf_len = mem.read_i32(iov_ptr + 4)
        if buf_len > 0 {
          let buf = FixedArray::make(buf_len, b'\x00')
          for j in 0..<buf_len {
            buf[j] = mem.read_byte(buf_ptr + j)
          }
          let n = native_send(file.native_fd, buf, buf_len, 0)
          if n < 0L {
            if total_sent > 0L {
              break
            }
            mem.write_i32(so_datalen_ptr, 0)
            return Errno::IO.to_i32()
          }
          total_sent = total_sent + n
          if n < buf_len.to_int64() {
            break
          }
        }
      }
      mem.write_i32(so_datalen_ptr, total_sent.to_int())
      Errno::Success.to_i32()
    }
    None => Errno::Badf.to_i32()
  }
}

///|
/// sock_shutdown - Shutdown socket
pub fn sock_shutdown_impl(ctx : WasiContext, fd : Int, how : Int) -> Int {
  match ctx.get_file(fd) {
    Some(file) =>
      // WASI: 0=RD, 1=WR, 2=RDWR
      // POSIX: 0=SHUT_RD, 1=SHUT_WR, 2=SHUT_RDWR
      if native_shutdown(file.native_fd, how) {
        Errno::Success.to_i32()
      } else {
        Errno::IO.to_i32()
      }
    None => Errno::Badf.to_i32()
  }
}

///|
/// sock_accept - Accept a connection on a socket
pub fn sock_accept_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  _flags : Int,
  result_fd_ptr : Int,
) -> Int {
  match ctx.get_file(fd) {
    Some(file) => {
      let new_fd = native_accept(file.native_fd)
      if new_fd < 0 {
        return Errno::IO.to_i32()
      }
      // Register the new socket in WASI context
      let open_file : OpenFile = {
        native_fd: new_fd,
        file_type: CharacterDevice, // Use CharacterDevice for sockets
        host_path: "<socket>",
        position: 0L,
        flags: 0,
      }
      let wasi_fd = ctx.alloc_fd(open_file)
      mem.write_i32(result_fd_ptr, wasi_fd)
      Errno::Success.to_i32()
    }
    None => Errno::Badf.to_i32()
  }
}

///|
/// proc_raise - Send a signal to the process
pub fn proc_raise_impl(signal : Int) -> Int {
  // WASI signal codes (some common ones):
  // 0 = none, 1 = HUP, 2 = INT, 3 = QUIT, 6 = ABRT, 9 = KILL, 15 = TERM
  if native_raise(signal) {
    Errno::Success.to_i32()
  } else {
    Errno::Inval.to_i32()
  }
}
