///|
/// WASI function implementations
/// These are the host functions that implement the wasi_snapshot_preview1 interface

///|
/// Error type for WASI process exit
pub(all) suberror WasiExit {
  WasiExit(Int)
}

///|
fn check_mem_range(mem : @runtime.Memory, ptr : Int, len : Int) -> Bool {
  if ptr < 0 || len < 0 {
    return false
  }
  let start = ptr.to_int64()
  let end = start + len.to_int64()
  end >= start && end <= mem.byte_len()
}

///|
fn check_iovecs_mem_range(
  mem : @runtime.Memory,
  iovs : Int,
  iovs_len : Int,
) -> Bool {
  if iovs_len < 0 {
    return false
  }
  let iovs_bytes = iovs_len * 8
  if !check_mem_range(mem, iovs, iovs_bytes) {
    return false
  }
  for i in 0..<iovs_len {
    let iov_offset = iovs + i * 8
    let buf_ptr = mem.read_i32(iov_offset)
    let buf_len = mem.read_i32(iov_offset + 4)
    if !check_mem_range(mem, buf_ptr, buf_len) {
      return false
    }
  }
  true
}

///|
fn is_stdio_open(ctx : WasiContext, fd : Int) -> Bool {
  match stdio_slot_for_fd(ctx, fd) {
    Some(0) => ctx.stdin_open
    Some(1) => ctx.stdout_open
    Some(2) => ctx.stderr_open
    _ => false
  }
}

///|
fn stdio_slot_for_fd(ctx : WasiContext, fd : Int) -> Int? {
  if fd == ctx.stdin_fd {
    Some(0)
  } else if fd == ctx.stdout_fd {
    Some(1)
  } else if fd == ctx.stderr_fd {
    Some(2)
  } else {
    None
  }
}

///|
fn is_stdio_descriptor(ctx : WasiContext, fd : Int) -> Bool {
  stdio_slot_for_fd(ctx, fd) is Some(_)
}

///|
fn clear_stdio_slot(ctx : WasiContext, slot : Int) -> Unit {
  if slot == 0 {
    ctx.stdin_open = false
    ctx.stdin_fd = -1
  } else if slot == 1 {
    ctx.stdout_open = false
    ctx.stdout_fd = -1
  } else if slot == 2 {
    ctx.stderr_open = false
    ctx.stderr_fd = -1
  }
}

///|
fn move_stdio_slot_to_fd(ctx : WasiContext, slot : Int, fd : Int) -> Unit {
  if slot == 0 {
    ctx.stdin_fd = fd
    ctx.stdin_open = true
  } else if slot == 1 {
    ctx.stdout_fd = fd
    ctx.stdout_open = true
  } else if slot == 2 {
    ctx.stderr_fd = fd
    ctx.stderr_open = true
  }
}

///|
fn close_stdio_fd(ctx : WasiContext, fd : Int) -> Bool {
  match stdio_slot_for_fd(ctx, fd) {
    Some(0) =>
      if !ctx.stdin_open {
        false
      } else {
        clear_stdio_slot(ctx, 0)
        true
      }
    Some(1) =>
      if !ctx.stdout_open {
        false
      } else {
        clear_stdio_slot(ctx, 1)
        true
      }
    Some(2) =>
      if !ctx.stderr_open {
        false
      } else {
        clear_stdio_slot(ctx, 2)
        true
      }
    _ => false
  }
}

///|
fn stdio_filetype(ctx : WasiContext, fd : Int) -> Int {
  match stdio_slot_for_fd(ctx, fd) {
    Some(0) => if ctx.stdin_is_native && native_isatty(0) { 2 } else { 0 }
    Some(1) => if ctx.stdout_is_native && native_isatty(1) { 2 } else { 0 }
    Some(2) => if ctx.stderr_is_native && native_isatty(2) { 2 } else { 0 }
    _ => 0
  }
}

///|
fn open_file_type_from_native(stat_filetype : Int) -> FileType {
  match stat_filetype {
    3 => Directory
    2 => CharacterDevice
    6 => SocketStream
    _ => RegularFile
  }
}

///|
fn first_non_empty_iov(
  mem : @runtime.Memory,
  iovs : Int,
  iovs_len : Int,
) -> (Int, Int)? {
  for i in 0..<iovs_len {
    let iov_offset = iovs + i * 8
    let buf_ptr = mem.read_i32(iov_offset)
    let buf_len = mem.read_i32(iov_offset + 4)
    if buf_len > 0 {
      return Some((buf_ptr, buf_len))
    }
  }
  None
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
  if !check_mem_range(mem, nwritten_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  if iovs_len < 0 || !check_mem_range(mem, iovs, iovs_len * 8) {
    return Errno::Fault.to_i32()
  }
  // Handle stdio streams
  if stdio_slot_for_fd(ctx, fd) is Some(slot) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    if slot == 0 {
      return Errno::Badf.to_i32()
    }
    let mut total_written = 0
    if first_non_empty_iov(mem, iovs, iovs_len) is Some(entry) {
      let (buf_ptr, buf_len) = entry
      if !check_mem_range(mem, buf_ptr, buf_len) {
        return Errno::Fault.to_i32()
      }
      let data = mem.read_bytes(buf_ptr, buf_len)
      if slot == 1 {
        (ctx.stdout_callback)(data)
      } else {
        (ctx.stderr_callback)(data)
      }
      total_written = buf_len
    }
    mem.write_i32(nwritten_ptr, total_written)
    return Errno::Success.to_i32()
  }
  // Handle opened files
  match ctx.open_files.get(fd) {
    Some(file_entry) => {
      match file_entry.file_type {
        RegularFile => ()
        _ => return Errno::Badf.to_i32()
      }
      let mut total_written = 0
      if first_non_empty_iov(mem, iovs, iovs_len) is Some(entry) {
        let (buf_ptr, buf_len) = entry
        if !check_mem_range(mem, buf_ptr, buf_len) {
          return Errno::Fault.to_i32()
        }
        let buf = FixedArray::make(buf_len, b'\x00')
        for j in 0..<buf_len {
          buf[j] = mem.read_byte(buf_ptr + j)
        }
        let written = native_write(file_entry.native_fd, buf, buf_len)
        match written {
          Some(n) => total_written = n
          None => {
            mem.write_i32(nwritten_ptr, total_written)
            return native_last_errno_to_wasi()
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
  if !check_mem_range(mem, nread_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  if iovs_len < 0 || !check_mem_range(mem, iovs, iovs_len * 8) {
    return Errno::Fault.to_i32()
  }
  // Handle stdio streams
  if stdio_slot_for_fd(ctx, fd) is Some(slot) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    if slot != 0 {
      return Errno::Badf.to_i32()
    }
    let input_data = (ctx.stdin_callback)()
    let mut total_read = 0
    if first_non_empty_iov(mem, iovs, iovs_len) is Some(entry) {
      let (buf_ptr, buf_len) = entry
      if !check_mem_range(mem, buf_ptr, buf_len) {
        return Errno::Fault.to_i32()
      }
      let to_copy = @cmp.minimum(buf_len, input_data.length())
      for j in 0..<to_copy {
        mem.write_byte(buf_ptr + j, input_data[j])
      }
      total_read = to_copy
    }
    mem.write_i32(nread_ptr, total_read)
    return Errno::Success.to_i32()
  }
  // Handle opened files
  match ctx.open_files.get(fd) {
    Some(file_entry) => {
      match file_entry.file_type {
        RegularFile => ()
        _ => return Errno::Badf.to_i32()
      }
      let mut total_read = 0
      if first_non_empty_iov(mem, iovs, iovs_len) is Some(entry) {
        let (buf_ptr, buf_len) = entry
        if !check_mem_range(mem, buf_ptr, buf_len) {
          return Errno::Fault.to_i32()
        }
        let read_result = native_read_to_memory(
          file_entry.native_fd,
          mem,
          buf_ptr,
          buf_len,
        )
        match read_result {
          Some(n) => total_read = n
          None => {
            mem.write_i32(nread_ptr, total_read)
            return native_last_errno_to_wasi()
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
  if !check_mem_range(mem, argc_ptr, 4) ||
    !check_mem_range(mem, argv_buf_size_ptr, 4) {
    return Errno::Fault.to_i32()
  }
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
  let argc = ctx.args.length()
  if !check_mem_range(mem, argv_ptr, argc * 4) {
    return Errno::Fault.to_i32()
  }
  let mut buf_size = 0
  for arg in ctx.args {
    buf_size = buf_size + arg.length() + 1
  }
  if !check_mem_range(mem, argv_buf_ptr, buf_size) {
    return Errno::Fault.to_i32()
  }
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
  if !check_mem_range(mem, environc_ptr, 4) ||
    !check_mem_range(mem, environ_buf_size_ptr, 4) {
    return Errno::Fault.to_i32()
  }
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
  let environc = ctx.env.length()
  if !check_mem_range(mem, environ_ptr, environc * 4) {
    return Errno::Fault.to_i32()
  }
  let mut buf_size = 0
  for env in ctx.env {
    buf_size = buf_size + env.length() + 1
  }
  if !check_mem_range(mem, environ_buf_ptr, buf_size) {
    return Errno::Fault.to_i32()
  }
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
  if !check_mem_range(mem, time_ptr, 8) {
    return Errno::Fault.to_i32()
  }
  let clock = ClockId::from_i32(clock_id)
  if clock is None {
    return Errno::Inval.to_i32()
  }
  // Get current time in nanoseconds using system clock
  let time_ns = match clock.unwrap() {
    Realtime => native_clock_gettime_realtime()
    Monotonic => native_clock_gettime_monotonic()
    // Match wasmtime p1: CPU-time clocks are unsupported in preview1.
    ProcessCPUTimeId | ThreadCPUTimeId => return Errno::Badf.to_i32()
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
  if !check_mem_range(mem, prestat_ptr, 8) {
    return Errno::Fault.to_i32()
  }
  if !ctx.is_valid_fd(fd) {
    return Errno::Badf.to_i32()
  }
  // Find preopen for this fd
  for preopen in ctx.preopens {
    let (preopen_fd, _, guest_path) = preopen
    if preopen_fd.to_int() == fd && ctx.open_files.contains(fd) {
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
  if !check_mem_range(mem, path_ptr, path_len) {
    return Errno::Fault.to_i32()
  }
  if !ctx.is_valid_fd(fd) {
    return Errno::Badf.to_i32()
  }
  // Find preopen for this fd
  for preopen in ctx.preopens {
    let (preopen_fd, _, guest_path) = preopen
    if preopen_fd.to_int() == fd && ctx.open_files.contains(fd) {
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
  Errno::NotDir.to_i32()
}

///|
/// fd_close - Close a file descriptor
///
/// Returns: errno
pub fn fd_close(ctx : WasiContext, fd : Int) -> Int {
  if is_stdio_descriptor(ctx, fd) {
    if close_stdio_fd(ctx, fd) {
      return Errno::Success.to_i32()
    }
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
  if !check_mem_range(mem, buf_ptr, buf_len) {
    return Errno::Fault.to_i32()
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
    native_last_errno_to_wasi()
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
  dirflags : Int,
  path_ptr : Int,
  path_len : Int,
  oflags : Int,
  fs_rights_base : Int64,
  fs_rights_inheriting : Int64,
  fdflags : Int,
  opened_fd_ptr : Int,
) -> Int {
  if !check_mem_range(mem, opened_fd_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  let lookupflags_check = validate_lookupflags(dirflags)
  if lookupflags_check != Errno::Success.to_i32() {
    return lookupflags_check
  }
  let known_oflags_mask = 0x0F
  if (oflags & known_oflags_mask.lnot()) != 0 {
    return Errno::Inval.to_i32()
  }
  let known_fdflags_mask = 0x1F
  if (fdflags & known_fdflags_mask.lnot()) != 0 {
    return Errno::Inval.to_i32()
  }
  ignore(fs_rights_inheriting)
  // Read path from memory
  let path = match read_path_from_memory(mem, path_ptr, path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let has_trailing_slash = path.length() > 0 &&
    path.code_unit_at(path.length() - 1) == '/'
  if is_stdio_descriptor(ctx, dir_fd) {
    if !is_stdio_open(ctx, dir_fd) {
      return Errno::Badf.to_i32()
    }
    return Errno::Badf.to_i32()
  }
  match ctx.get_file(dir_fd) {
    Some(file) =>
      match file.file_type {
        Directory => ()
        RegularFile => return Errno::NotDir.to_i32()
        _ => return Errno::Badf.to_i32()
      }
    None => return Errno::Badf.to_i32()
  }
  let follow_symlink = (dirflags & 0x01) != 0
  let resolved_path_result = if follow_symlink {
    resolve_host_path(ctx, dir_fd, path)
  } else {
    resolve_host_path_nofollow_leaf(ctx, dir_fd, path)
  }
  let resolved_path = match resolved_path_result {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  // Determine open flags
  let open_flags : Array[OpenFlags] = []
  let has_create = (oflags & 0x01) != 0
  let has_directory = (oflags & 0x02) != 0
  let has_exclusive = (oflags & 0x04) != 0
  let has_truncate = (oflags & 0x08) != 0
  let has_append = (fdflags & 0x01) != 0
  let has_sync = (fdflags & 0x1A) != 0 // 0x02 DSYNC, 0x08 RSYNC, 0x10 SYNC
  if has_directory && (has_create || has_exclusive || has_truncate) {
    return Errno::Inval.to_i32()
  }
  if has_sync {
    return Errno::NotSup.to_i32()
  }
  // WASI oflags:
  // 0x01 = O_CREAT, 0x02 = O_DIRECTORY, 0x04 = O_EXCL, 0x08 = O_TRUNC
  if has_create {
    open_flags.push(Create)
  }
  if has_directory {
    open_flags.push(Directory)
  }
  if has_exclusive {
    open_flags.push(Exclusive)
  }
  if has_truncate {
    open_flags.push(Truncate)
  }
  // WASI fdflags:
  // 0x01 = APPEND, 0x02 = DSYNC, 0x04 = NONBLOCK, 0x08 = RSYNC, 0x10 = SYNC
  if has_append {
    open_flags.push(Append)
  }
  if !follow_symlink {
    open_flags.push(NoFollow)
  }
  let allow_read = (fs_rights_base & right_fd_read) != 0L
  let allow_write = (fs_rights_base & right_fd_write) != 0L
  // Match wasmtime's open-mode policy:
  // - explicit FD_WRITE implies writable open
  // - create/truncate/append require writable host mode
  // - otherwise default to read-only
  let requires_write = allow_write || has_create || has_truncate || has_append
  if allow_read && requires_write {
    open_flags.push(ReadWrite)
  } else if requires_write {
    open_flags.push(WriteOnly)
  } else {
    open_flags.push(ReadOnly)
  }
  // Open the file
  let open_path = if has_trailing_slash {
    resolved_path + "/"
  } else {
    resolved_path
  }
  let native_fd = native_open(open_path, open_flags, 0o644)
  if native_fd is None {
    let errno = native_last_errno_to_wasi()
    if has_trailing_slash && errno == Errno::NotDir.to_i32() {
      return Errno::NoEnt.to_i32()
    }
    return errno
  }
  let nfd = native_fd.unwrap()
  let stat = native_fstat(nfd)
  if stat is None {
    native_close(nfd) |> ignore
    return native_last_errno_to_wasi()
  }
  let file_type = open_file_type_from_native(stat.unwrap().filetype)
  if has_directory {
    match file_type {
      Directory => ()
      _ => {
        native_close(nfd) |> ignore
        return Errno::NotDir.to_i32()
      }
    }
  }
  // Allocate WASI fd
  let wasi_fd = ctx.alloc_fd({
    native_fd: nfd,
    file_type,
    host_path: resolved_path,
    position: 0L,
    flags: fdflags,
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
  if !check_mem_range(mem, newoffset_ptr, 8) {
    return Errno::Fault.to_i32()
  }
  // stdio streams don't support seeking
  if is_stdio_descriptor(ctx, fd) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    return Errno::SPipe.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  match f.file_type {
    RegularFile => ()
    _ => return Errno::Badf.to_i32()
  }
  // Convert WASI whence to native
  let native_whence : Whence = match whence {
    0 => Set
    1 => Cur
    2 => End
    _ => return Errno::Inval.to_i32()
  }
  let new_pos = native_seek(f.native_fd, offset, native_whence)
  if new_pos is None {
    return native_last_errno_to_wasi()
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
  if !check_mem_range(mem, offset_ptr, 8) {
    return Errno::Fault.to_i32()
  }
  // stdio streams don't support tell
  if is_stdio_descriptor(ctx, fd) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    return Errno::SPipe.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  match f.file_type {
    RegularFile => ()
    _ => return Errno::Badf.to_i32()
  }
  let pos = native_tell(f.native_fd)
  if pos is None {
    return native_last_errno_to_wasi()
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
  if !check_mem_range(mem, nread_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  if iovs_len < 0 || !check_mem_range(mem, iovs, iovs_len * 8) {
    return Errno::Fault.to_i32()
  }
  if stdio_slot_for_fd(ctx, fd) is Some(slot) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    if slot == 0 {
      return Errno::SPipe.to_i32()
    }
    return Errno::Badf.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  match f.file_type {
    RegularFile => ()
    _ => return Errno::Badf.to_i32()
  }
  // Save current position
  let saved_pos = native_tell(f.native_fd)
  if saved_pos is None {
    return native_last_errno_to_wasi()
  }
  // Seek to offset
  let seek_result = native_seek(f.native_fd, offset, Set)
  if seek_result is None {
    return native_last_errno_to_wasi()
  }
  // Read data from the first non-empty iovec only (wasmtime parity).
  let mut total_read = 0
  if first_non_empty_iov(mem, iovs, iovs_len) is Some(entry) {
    let (buf_ptr, buf_len) = entry
    if !check_mem_range(mem, buf_ptr, buf_len) {
      native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
      return Errno::Fault.to_i32()
    }
    let buf = FixedArray::make(buf_len, b'\x00')
    let n = native_read(f.native_fd, buf, buf_len)
    if n is None {
      let errno = native_last_errno_to_wasi()
      // Restore position and return error
      native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
      return errno
    }
    let bytes_read = n.unwrap()
    // Copy to WASM memory
    for j in 0..<bytes_read {
      mem.write_byte(buf_ptr + j, buf[j])
    }
    total_read = bytes_read
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
  if !check_mem_range(mem, nwritten_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  if iovs_len < 0 || !check_mem_range(mem, iovs, iovs_len * 8) {
    return Errno::Fault.to_i32()
  }
  if stdio_slot_for_fd(ctx, fd) is Some(slot) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    if slot == 0 {
      return Errno::Badf.to_i32()
    }
    return Errno::SPipe.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  match f.file_type {
    RegularFile => ()
    _ => return Errno::Badf.to_i32()
  }
  // Save current position
  let saved_pos = native_tell(f.native_fd)
  if saved_pos is None {
    return native_last_errno_to_wasi()
  }
  // Seek to offset
  let seek_result = native_seek(f.native_fd, offset, Set)
  if seek_result is None {
    return native_last_errno_to_wasi()
  }
  // Write data from the first non-empty iovec only (wasmtime parity).
  let mut total_written = 0
  if first_non_empty_iov(mem, iovs, iovs_len) is Some(entry) {
    let (buf_ptr, buf_len) = entry
    if !check_mem_range(mem, buf_ptr, buf_len) {
      native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
      return Errno::Fault.to_i32()
    }
    let buf = FixedArray::make(buf_len, b'\x00')
    // Copy from WASM memory
    for j in 0..<buf_len {
      buf[j] = mem.read_byte(buf_ptr + j)
    }
    let n = native_write(f.native_fd, buf, buf_len)
    if n is None {
      let errno = native_last_errno_to_wasi()
      // Restore position and return error
      native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
      return errno
    }
    total_written = n.unwrap()
  }
  // Restore position
  native_seek(f.native_fd, saved_pos.unwrap(), Set) |> ignore
  mem.write_i32(nwritten_ptr, total_written)
  Errno::Success.to_i32()
}

///|
fn fd_rights_for_stdio_slot(slot : Int) -> Int64 {
  if slot == 0 {
    right_fd_read
  } else if slot == 1 || slot == 2 {
    right_fd_write
  } else {
    0L
  }
}

///|
fn fd_rights_for_preopen_directory_base() -> Int64 {
  right_path_create_directory |
  right_path_create_file |
  right_path_link_source |
  right_path_link_target |
  right_path_open |
  right_fd_readdir |
  right_path_readlink |
  right_path_rename_source |
  right_path_rename_target |
  right_path_symlink |
  right_path_remove_directory |
  right_path_unlink_file |
  right_path_filestat_get |
  right_path_filestat_set_times |
  right_fd_filestat_get |
  right_fd_filestat_set_times
}

///|
fn fd_rights_for_preopen_directory_inheriting() -> Int64 {
  let base = fd_rights_for_preopen_directory_base()
  base |
  right_fd_datasync |
  right_fd_read |
  right_fd_seek |
  right_fd_fdstat_set_flags |
  right_fd_sync |
  right_fd_tell |
  right_fd_write |
  right_fd_advise |
  right_fd_allocate |
  right_fd_filestat_get |
  right_fd_filestat_set_size |
  right_fd_filestat_set_times |
  right_poll_fd_readwrite
}

///|
fn fd_rights_for_socket(can_read : Bool, can_write : Bool) -> Int64 {
  let mut rights = right_fd_fdstat_set_flags | right_sock_shutdown
  if can_read {
    rights = rights | right_fd_read
  }
  if can_write {
    rights = rights | right_fd_write
  }
  if can_read || can_write {
    rights = rights | right_poll_fd_readwrite
  }
  rights
}

///|
fn fd_rights_for_descriptor(
  file_type : FileType,
  can_read : Bool,
  can_write : Bool,
) -> Int64 {
  if file_type is SocketStream {
    return fd_rights_for_socket(can_read, can_write)
  }
  let mut rights = rights_all_valid
  if file_type is Directory {
    rights = rights & right_fd_seek.lnot()
    rights = rights & right_fd_filestat_set_size.lnot()
    rights = rights & right_path_filestat_set_size.lnot()
  }
  if !can_read {
    rights = rights & right_fd_read.lnot()
    rights = rights & right_fd_readdir.lnot()
  }
  if !can_write {
    rights = rights & right_fd_write.lnot()
  }
  rights
}

///|
fn fd_access_mode_from_native(
  native_fd : Int,
  file_type : FileType,
) -> (Bool, Bool) {
  if file_type is Directory {
    return (true, true)
  }
  let flags = native_fcntl_getfl(native_fd)
  match flags {
    Some(native_flags) => {
      let rdonly = native_o_rdonly()
      let wronly = native_o_wronly()
      let rdwr = native_o_rdwr()
      let acc_mode = native_flags & (rdonly | wronly | rdwr)
      if acc_mode == wronly {
        (false, true)
      } else if acc_mode == rdwr {
        (true, true)
      } else {
        (true, false)
      }
    }
    None => (true, true)
  }
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
  if !check_mem_range(mem, fdstat_ptr, 24) {
    return Errno::Fault.to_i32()
  }
  // Determine file type
  let (file_type, flags, rights_base, rights_inheriting) : (
    Int,
    Int,
    Int64,
    Int64,
  ) = if stdio_slot_for_fd(ctx, fd) is Some(slot) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    (
      stdio_filetype(ctx, fd),
      0,
      fd_rights_for_stdio_slot(slot),
      fd_rights_for_stdio_slot(slot),
    )
  } else {
    // Check preopen directories first: wasmtime reports a special base/inheriting set.
    for preopen in ctx.preopens {
      let (preopen_fd, _, _) = preopen
      if preopen_fd.to_int() == fd && ctx.open_files.contains(fd) {
        let rights_base = fd_rights_for_preopen_directory_base()
        let rights_inheriting = fd_rights_for_preopen_directory_inheriting()
        return {
          mem.write_byte(fdstat_ptr, b'\x03') // fs_filetype = directory (3)
          mem.write_byte(fdstat_ptr + 1, b'\x00') // padding
          mem.write_byte(fdstat_ptr + 2, b'\x00') // fs_flags low byte
          mem.write_byte(fdstat_ptr + 3, b'\x00') // fs_flags high byte
          mem.write_i32(fdstat_ptr + 4, 0) // padding
          mem.write_i64(fdstat_ptr + 8, rights_base)
          mem.write_i64(fdstat_ptr + 16, rights_inheriting)
          Errno::Success.to_i32()
        }
      }
    }
    match ctx.get_file(fd) {
      Some(file) => {
        let ft = match file.file_type {
          RegularFile => 4 // regular_file
          Directory => 3 // directory
          CharacterDevice => 2 // character_device
          SocketStream => 6 // socket_stream
        }
        let (can_read, can_write) = fd_access_mode_from_native(
          file.native_fd,
          file.file_type,
        )
        let rights = fd_rights_for_descriptor(
          file.file_type,
          can_read,
          can_write,
        )
        (ft, file.flags & 0x1F, rights, rights)
      }
      None => return Errno::Badf.to_i32()
    }
  }
  // Write fdstat struct
  mem.write_byte(fdstat_ptr, file_type.to_byte()) // fs_filetype
  mem.write_byte(fdstat_ptr + 1, b'\x00') // padding
  mem.write_byte(fdstat_ptr + 2, (flags & 0xFF).to_byte()) // fs_flags low byte
  mem.write_byte(fdstat_ptr + 3, ((flags >> 8) & 0xFF).to_byte()) // fs_flags high byte
  mem.write_i32(fdstat_ptr + 4, 0) // padding
  mem.write_i64(fdstat_ptr + 8, rights_base)
  mem.write_i64(fdstat_ptr + 16, rights_inheriting)
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
  if !check_mem_range(mem, resolution_ptr, 8) {
    return Errno::Fault.to_i32()
  }
  let clock = ClockId::from_i32(clock_id)
  if clock is None {
    return Errno::Inval.to_i32()
  }
  let clock_value = clock.unwrap()
  match clock_value {
    Realtime =>
      match native_clock_getres_realtime() {
        Some(v) => {
          mem.write_i64(resolution_ptr, v)
          Errno::Success.to_i32()
        }
        None => native_last_errno_to_wasi()
      }
    Monotonic =>
      match native_clock_getres_monotonic() {
        Some(v) => {
          mem.write_i64(resolution_ptr, v)
          Errno::Success.to_i32()
        }
        None => native_last_errno_to_wasi()
      }
    ProcessCPUTimeId | ThreadCPUTimeId => Errno::Badf.to_i32()
  }
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
  let path = match read_path_from_memory(mem, path_ptr, path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let resolved_path = match resolve_host_path_nofollow_leaf(ctx, dir_fd, path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  if native_mkdir(resolved_path, 0o755) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
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
  if !check_mem_range(mem, buf_ptr, buf_len) ||
    !check_mem_range(mem, bufused_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  if is_stdio_descriptor(ctx, fd) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    return Errno::Badf.to_i32()
  }
  let file = ctx.get_file(fd)
  if file is None {
    return Errno::Badf.to_i32()
  }
  let f = file.unwrap()
  if f.file_type is Directory {
    readdir_impl(mem, f.native_fd, buf_ptr, buf_len, cookie, bufused_ptr)
  } else {
    Errno::Badf.to_i32()
  }
}

///|
fn write_readdir_header(
  mem : @runtime.Memory,
  ptr : Int,
  available : Int,
  d_next : Int64,
  d_ino : Int64,
  d_namlen : Int,
  d_type : Int,
) -> Int {
  let to_write = @cmp.minimum(available, 24)
  for i in 0..<to_write {
    let v = if i < 8 {
      ((d_next >> (i * 8)) & 0xFFL).to_int()
    } else if i < 16 {
      ((d_ino >> ((i - 8) * 8)) & 0xFFL).to_int()
    } else if i < 20 {
      ((d_namlen.to_int64() >> ((i - 16) * 8)) & 0xFFL).to_int()
    } else if i == 20 {
      d_type
    } else {
      0
    }
    mem.write_byte(ptr + i, v.to_byte())
  }
  to_write
}

///|
fn emit_readdir_entry(
  mem : @runtime.Memory,
  buf_ptr : Int,
  buf_len : Int,
  offset : Int,
  entry_idx : Int64,
  d_ino : Int64,
  name : String,
  is_dir : Bool,
) -> (Int, Bool) {
  if offset >= buf_len {
    return (offset, false)
  }
  let d_next = entry_idx + 1L
  let d_type = if is_dir { 3 } else { 4 }
  let header_written = write_readdir_header(
    mem,
    buf_ptr + offset,
    buf_len - offset,
    d_next,
    d_ino,
    name.length(),
    d_type,
  )
  let mut new_offset = offset + header_written
  if header_written < 24 {
    return (new_offset, false)
  }
  if new_offset >= buf_len {
    return (new_offset, false)
  }
  let name_to_write = @cmp.minimum(buf_len - new_offset, name.length())
  for i in 0..<name_to_write {
    mem.write_byte(buf_ptr + new_offset + i, name.code_unit_at(i).to_byte())
  }
  new_offset = new_offset + name_to_write
  (new_offset, name_to_write == name.length())
}

///|
/// Helper: Implement readdir
fn readdir_impl(
  mem : @runtime.Memory,
  dir_fd : Int,
  buf_ptr : Int,
  buf_len : Int,
  cookie : Int64,
  bufused_ptr : Int,
) -> Int {
  let entries = native_readdir_fd(dir_fd)
  if entries is None {
    mem.write_i32(bufused_ptr, 0)
    return native_last_errno_to_wasi()
  }
  let dir_entries = entries.unwrap()
  let mut offset = 0
  let mut entry_idx = 0L
  let mut dir_ino = 1L
  if native_fstat(dir_fd) is Some(stat) {
    dir_ino = stat.ino.reinterpret_as_int64()
  }
  let effective_cookie = if cookie < 0L { 9223372036854775807L } else { cookie }
  let mut keep_going = true
  if entry_idx >= effective_cookie {
    let (next_offset, ok) = emit_readdir_entry(
      mem, buf_ptr, buf_len, offset, entry_idx, dir_ino, ".", true,
    )
    offset = next_offset
    keep_going = ok
  }
  entry_idx = entry_idx + 1L
  if keep_going && entry_idx >= effective_cookie {
    let (next_offset, ok) = emit_readdir_entry(
      mem, buf_ptr, buf_len, offset, entry_idx, dir_ino, "..", true,
    )
    offset = next_offset
    keep_going = ok
  }
  entry_idx = entry_idx + 1L
  if !keep_going {
    mem.write_i32(bufused_ptr, offset)
    return Errno::Success.to_i32()
  }
  for entry in dir_entries {
    let (name, is_dir) = entry
    // Skip entries before cookie
    if entry_idx < effective_cookie {
      entry_idx = entry_idx + 1L
      continue
    }
    let entry_ino = match native_fstatat(dir_fd, name, 0) {
      Some(stat) => stat.ino.reinterpret_as_int64()
      None => entry_idx + 1L
    }
    let (next_offset, ok) = emit_readdir_entry(
      mem, buf_ptr, buf_len, offset, entry_idx, entry_ino, name, is_dir,
    )
    offset = next_offset
    entry_idx = entry_idx + 1L
    if !ok {
      break
    }
  }
  mem.write_i32(bufused_ptr, offset)
  Errno::Success.to_i32()
}

///|
/// Helper: UTF-8 validation for guest path bytes
fn is_utf8_continuation_byte(b : Int) -> Bool {
  b >= 0x80 && b <= 0xBF
}

///|
fn is_valid_utf8_bytes(bytes : Bytes) -> Bool {
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let b0 = bytes[i].to_int()
    if b0 < 0x80 {
      i = i + 1
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 >= len {
        return false
      }
      let b1 = bytes[i + 1].to_int()
      if !is_utf8_continuation_byte(b1) {
        return false
      }
      i = i + 2
    } else if b0 == 0xE0 {
      if i + 2 >= len {
        return false
      }
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      if b1 < 0xA0 || b1 > 0xBF || !is_utf8_continuation_byte(b2) {
        return false
      }
      i = i + 3
    } else if (b0 >= 0xE1 && b0 <= 0xEC) || (b0 >= 0xEE && b0 <= 0xEF) {
      if i + 2 >= len {
        return false
      }
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      if !is_utf8_continuation_byte(b1) || !is_utf8_continuation_byte(b2) {
        return false
      }
      i = i + 3
    } else if b0 == 0xED {
      if i + 2 >= len {
        return false
      }
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      if b1 < 0x80 || b1 > 0x9F || !is_utf8_continuation_byte(b2) {
        return false
      }
      i = i + 3
    } else if b0 == 0xF0 {
      if i + 3 >= len {
        return false
      }
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      let b3 = bytes[i + 3].to_int()
      if b1 < 0x90 ||
        b1 > 0xBF ||
        !is_utf8_continuation_byte(b2) ||
        !is_utf8_continuation_byte(b3) {
        return false
      }
      i = i + 4
    } else if b0 >= 0xF1 && b0 <= 0xF3 {
      if i + 3 >= len {
        return false
      }
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      let b3 = bytes[i + 3].to_int()
      if !is_utf8_continuation_byte(b1) ||
        !is_utf8_continuation_byte(b2) ||
        !is_utf8_continuation_byte(b3) {
        return false
      }
      i = i + 4
    } else if b0 == 0xF4 {
      if i + 3 >= len {
        return false
      }
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      let b3 = bytes[i + 3].to_int()
      if b1 < 0x80 ||
        b1 > 0x8F ||
        !is_utf8_continuation_byte(b2) ||
        !is_utf8_continuation_byte(b3) {
        return false
      }
      i = i + 4
    } else {
      return false
    }
  }
  true
}

///|
/// Helper: Read a string from WASM memory
fn read_path_from_memory(
  mem : @runtime.Memory,
  ptr : Int,
  len : Int,
) -> Result[String, Int] {
  if !check_mem_range(mem, ptr, len) {
    return Err(Errno::Fault.to_i32())
  }
  let bytes = Bytes::makei(len, fn(i) { mem.read_byte(ptr + i) })
  for b in bytes {
    if b == b'\x00' {
      return Err(Errno::Inval.to_i32())
    }
  }
  if !is_valid_utf8_bytes(bytes) {
    return Err(Errno::IlSeq.to_i32())
  }
  Ok(utf8_bytes_to_string(bytes))
}

///|
fn validate_lookupflags(flags : Int) -> Int {
  let known_mask = 0x01
  if (flags & known_mask.lnot()) != 0 {
    Errno::Inval.to_i32()
  } else {
    Errno::Success.to_i32()
  }
}

///|
fn validate_sock_accept_fdflags(flags : Int) -> Int {
  let known_mask = 0x1F
  if (flags & known_mask.lnot()) != 0 {
    Errno::Inval.to_i32()
  } else {
    Errno::Success.to_i32()
  }
}

///|
fn validate_sock_recv_riflags(ri_flags : Int) -> Int {
  let known_mask = 0x03
  if (ri_flags & known_mask.lnot()) != 0 {
    Errno::Inval.to_i32()
  } else {
    Errno::Success.to_i32()
  }
}

///|
fn validate_sock_shutdown_sdflags(how : Int) -> Int {
  let known_mask = 0x03
  if (how & known_mask.lnot()) != 0 {
    Errno::Inval.to_i32()
  } else {
    Errno::Success.to_i32()
  }
}

///|
fn validate_proc_raise_signal(signal : Int) -> Int {
  // WITX `signal` is an enum with valid tags in range [0, 30].
  if signal < 0 || signal > 30 {
    Errno::Inval.to_i32()
  } else {
    Errno::Success.to_i32()
  }
}

///|
fn resolve_host_path(
  ctx : WasiContext,
  dir_fd : Int,
  path : String,
) -> Result[String, Int] {
  if path.length() == 0 {
    return Err(Errno::NoEnt.to_i32())
  }
  match ctx.resolve_path(dir_fd, path) {
    Ok(resolved) => Ok(resolved)
    Err(BadFd) => Err(Errno::Badf.to_i32())
    Err(Perm) => Err(Errno::Perm.to_i32())
    Err(NotCapable) => Err(Errno::Perm.to_i32())
  }
}

///|
fn resolve_host_path_nofollow_leaf(
  ctx : WasiContext,
  dir_fd : Int,
  path : String,
) -> Result[String, Int] {
  if path.length() == 0 {
    return Err(Errno::NoEnt.to_i32())
  }
  match ctx.resolve_path_nofollow_leaf(dir_fd, path) {
    Ok(resolved) => Ok(resolved)
    Err(BadFd) => Err(Errno::Badf.to_i32())
    Err(Perm) => Err(Errno::Perm.to_i32())
    Err(NotCapable) => Err(Errno::Perm.to_i32())
  }
}

///|
/// Return the native fd for file-only operations (preview1 `get_file_fd`-like).
///
/// Returns `None` for stdio, directories, sockets, and invalid fds.
fn regular_file_native_fd(ctx : WasiContext, fd : Int) -> Int? {
  if is_stdio_descriptor(ctx, fd) {
    return None
  }
  match ctx.get_file(fd) {
    Some(file) =>
      if file.file_type is RegularFile {
        Some(file.native_fd)
      } else {
        None
      }
    None => None
  }
}

///|
/// Return the native fd for non-stdio descriptor operations (preview1 `get_fd`-like).
///
/// Returns `None` for stdio and invalid fds.
fn non_stdio_descriptor_native_fd(ctx : WasiContext, fd : Int) -> Int? {
  if is_stdio_descriptor(ctx, fd) {
    return None
  }
  match ctx.get_file(fd) {
    Some(file) => Some(file.native_fd)
    None => None
  }
}

///|
fn is_valid_descriptor_for_sock(ctx : WasiContext, fd : Int) -> Bool {
  ctx.is_valid_fd(fd)
}

// ============================================================================
// Phase 1: Core file operations
// ============================================================================

///|
/// fd_sync - Synchronize file to disk
pub fn fd_sync_impl(ctx : WasiContext, fd : Int) -> Int {
  let native_fd = match regular_file_native_fd(ctx, fd) {
    Some(native_fd) => native_fd
    None => return Errno::Badf.to_i32()
  }
  if native_fsync(native_fd) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
  }
}

///|
/// fd_datasync - Synchronize file data to disk
pub fn fd_datasync_impl(ctx : WasiContext, fd : Int) -> Int {
  let native_fd = match regular_file_native_fd(ctx, fd) {
    Some(native_fd) => native_fd
    None => return Errno::Badf.to_i32()
  }
  if native_fdatasync(native_fd) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
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
  let path = match read_path_from_memory(mem, path_ptr, path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let resolved_path = match resolve_host_path_nofollow_leaf(ctx, dir_fd, path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  if native_unlinkat(0, resolved_path, 0) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
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
  let path = match read_path_from_memory(mem, path_ptr, path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let resolved_path = match resolve_host_path_nofollow_leaf(ctx, dir_fd, path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  if native_unlinkat(0, resolved_path, AT_REMOVEDIR) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
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
  let old_path = match read_path_from_memory(mem, old_path_ptr, old_path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let new_path = match read_path_from_memory(mem, new_path_ptr, new_path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let old_resolved = match
    resolve_host_path_nofollow_leaf(ctx, old_fd, old_path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  let new_resolved = match
    resolve_host_path_nofollow_leaf(ctx, new_fd, new_path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  if native_renameat(0, old_resolved, 0, new_resolved) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
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
  if !check_mem_range(mem, buf_ptr, 64) {
    return Errno::Fault.to_i32()
  }
  // Handle stdio descriptors.
  if is_stdio_descriptor(ctx, fd) {
    if !is_stdio_open(ctx, fd) {
      return Errno::Badf.to_i32()
    }
    // Match wasmtime stdio modeling: unknown or character_device, nlink=0.
    mem.write_i64(buf_ptr, 0L) // dev
    mem.write_i64(buf_ptr + 8, 0L) // ino
    mem.write_byte(buf_ptr + 16, stdio_filetype(ctx, fd).to_byte())
    for i in 17..<24 {
      mem.write_byte(buf_ptr + i, b'\x00')
    }
    mem.write_i64(buf_ptr + 24, 0L) // nlink
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
        None => native_last_errno_to_wasi()
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
  if !check_mem_range(mem, buf_ptr, 64) {
    return Errno::Fault.to_i32()
  }
  let lookupflags_check = validate_lookupflags(flags)
  if lookupflags_check != Errno::Success.to_i32() {
    return lookupflags_check
  }
  let path = match read_path_from_memory(mem, path_ptr, path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let has_trailing_slash = path.length() > 0 &&
    path.code_unit_at(path.length() - 1) == '/'
  let follow_symlink = (flags & 0x01) != 0
  let resolved_path_result = if follow_symlink {
    resolve_host_path(ctx, dir_fd, path)
  } else {
    resolve_host_path_nofollow_leaf(ctx, dir_fd, path)
  }
  let resolved_path = match resolved_path_result {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  let stat_path = if has_trailing_slash {
    resolved_path + "/"
  } else {
    resolved_path
  }
  // Convert WASI flags to native flags
  let native_flags = if follow_symlink { 0 } else { AT_SYMLINK_NOFOLLOW }
  let stat = native_fstatat(0, stat_path, native_flags)
  match stat {
    Some(s) => {
      write_filestat(mem, buf_ptr, s)
      Errno::Success.to_i32()
    }
    None => {
      let errno = native_last_errno_to_wasi()
      if has_trailing_slash && errno == Errno::NotDir.to_i32() {
        Errno::NoEnt.to_i32()
      } else {
        errno
      }
    }
  }
}

///|
/// fd_filestat_set_size - Set file size (truncate)
pub fn fd_filestat_set_size_impl(
  ctx : WasiContext,
  fd : Int,
  size : Int64,
) -> Int {
  let native_fd = match regular_file_native_fd(ctx, fd) {
    Some(native_fd) => native_fd
    None => return Errno::Badf.to_i32()
  }
  if native_ftruncate(native_fd, size) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
  }
}

///|
fn validate_fst_flags_for_set_times(fst_flags : Int) -> Int {
  // Match wasmtime's systimespec validation:
  // - reject unknown bits
  // - reject conflicting ATIM/ATIM_NOW and MTIM/MTIM_NOW
  let known_mask = 0x0F
  if (fst_flags & known_mask.lnot()) != 0 {
    return Errno::Inval.to_i32()
  }
  if (fst_flags & 0x03) == 0x03 || (fst_flags & 0x0C) == 0x0C {
    return Errno::Inval.to_i32()
  }
  Errno::Success.to_i32()
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
  let fst_flags_check = validate_fst_flags_for_set_times(fst_flags)
  if fst_flags_check != Errno::Success.to_i32() {
    return fst_flags_check
  }
  let native_fd = match non_stdio_descriptor_native_fd(ctx, fd) {
    Some(native_fd) => native_fd
    None => return Errno::Badf.to_i32()
  }
  if native_futimens(native_fd, atim, mtim, fst_flags) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
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
  let lookupflags_check = validate_lookupflags(flags)
  if lookupflags_check != Errno::Success.to_i32() {
    return lookupflags_check
  }
  let fst_flags_check = validate_fst_flags_for_set_times(fst_flags)
  if fst_flags_check != Errno::Success.to_i32() {
    return fst_flags_check
  }
  let path = match read_path_from_memory(mem, path_ptr, path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let has_trailing_slash = path.length() > 0 &&
    path.code_unit_at(path.length() - 1) == '/'
  let follow_symlink = (flags & 0x01) != 0
  let resolved_path_result = if follow_symlink {
    resolve_host_path(ctx, dir_fd, path)
  } else {
    resolve_host_path_nofollow_leaf(ctx, dir_fd, path)
  }
  let resolved_path = match resolved_path_result {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  let stat_path = if has_trailing_slash {
    resolved_path + "/"
  } else {
    resolved_path
  }
  let lookup_flags = if follow_symlink { 0 } else { AT_SYMLINK_NOFOLLOW }
  if has_trailing_slash {
    match native_fstatat(0, resolved_path, lookup_flags) {
      Some(stat) => if stat.filetype != 3 { return Errno::NoEnt.to_i32() }
      None => {
        let errno = native_last_errno_to_wasi()
        if errno == Errno::NotDir.to_i32() {
          return Errno::NoEnt.to_i32()
        }
        return errno
      }
    }
  }
  if native_utimensat(0, stat_path, atim, mtim, fst_flags, lookup_flags) {
    Errno::Success.to_i32()
  } else {
    let errno = native_last_errno_to_wasi()
    if has_trailing_slash && errno == Errno::NotDir.to_i32() {
      Errno::NoEnt.to_i32()
    } else {
      errno
    }
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
  advice : Int,
) -> Int {
  if advice < 0 || advice > 5 {
    return Errno::Inval.to_i32()
  }
  if regular_file_native_fd(ctx, fd) is None {
    return Errno::Badf.to_i32()
  }
  Errno::Success.to_i32()
}

///|
/// fd_allocate - Allocate space for file
pub fn fd_allocate_impl(
  ctx : WasiContext,
  fd : Int,
  _offset : Int64,
  _len : Int64,
) -> Int {
  if regular_file_native_fd(ctx, fd) is None {
    return Errno::Badf.to_i32()
  }
  Errno::NotSup.to_i32()
}

///|
/// fd_fdstat_set_flags - Set file descriptor flags
pub fn fd_fdstat_set_flags_impl(
  ctx : WasiContext,
  fd : Int,
  flags : Int,
) -> Int {
  let known_fdflags_mask = 0x1F
  if (flags & known_fdflags_mask.lnot()) != 0 {
    return Errno::Inval.to_i32()
  }
  if is_stdio_descriptor(ctx, fd) {
    return Errno::Badf.to_i32()
  }
  let native_fd = match ctx.get_file(fd) {
    Some(file) =>
      if file.file_type is Directory {
        return Errno::Badf.to_i32()
      } else {
        file.native_fd
      }
    None => return Errno::Badf.to_i32()
  }
  // Match wasmtime behavior:
  // - unknown fdflags bits are rejected before descriptor lookup
  // - DSYNC/RSYNC/SYNC are rejected with EINVAL only for valid file descriptors
  if (flags & 0x02) != 0 || (flags & 0x08) != 0 || (flags & 0x10) != 0 {
    return Errno::Inval.to_i32()
  }
  // Convert WASI fdflags to native flags
  // WASI: 0x01 = APPEND, 0x02 = DSYNC, 0x04 = NONBLOCK, 0x08 = RSYNC, 0x10 = SYNC
  let native_flags = native_fcntl_getfl(native_fd)
  match native_flags {
    Some(current) => {
      let mut new_flags = current
      let append_mask = native_o_append()
      let nonblock_mask = native_o_nonblock()
      if (flags & 0x01) != 0 {
        new_flags = new_flags | append_mask
      } else {
        new_flags = new_flags & append_mask.lnot()
      }
      if (flags & 0x04) != 0 {
        new_flags = new_flags | nonblock_mask
      } else {
        new_flags = new_flags & nonblock_mask.lnot()
      }
      if native_fcntl_setfl(native_fd, new_flags) {
        Errno::Success.to_i32()
      } else {
        native_last_errno_to_wasi()
      }
    }
    None => native_last_errno_to_wasi()
  }
}

///|
/// fd_fdstat_set_rights - Set file descriptor rights (no-op)
pub fn fd_fdstat_set_rights_impl(
  ctx : WasiContext,
  fd : Int,
  _fs_rights_base : Int64,
  _fs_rights_inheriting : Int64,
) -> Int {
  if !ctx.is_valid_fd(fd) {
    return Errno::Badf.to_i32()
  }
  Errno::NotSup.to_i32()
}

///|
fn preopen_fd_index(ctx : WasiContext, fd : Int) -> Int? {
  if !ctx.open_files.contains(fd) {
    return None
  }
  for i in 0..<ctx.preopens.length() {
    let (preopen_fd, _, _) = ctx.preopens[i]
    if preopen_fd.to_int() == fd {
      return Some(i)
    }
  }
  None
}

///|
fn renumber_preopen_entries(ctx : WasiContext, from : Int, to : Int) -> Unit {
  let mut moved : (String, String)? = None
  let new_preopens : Array[(Fd, String, String)] = []
  for preopen in ctx.preopens {
    let (pfd, host, guest) = preopen
    let fd = pfd.to_int()
    if fd == from {
      moved = Some((host, guest))
      continue
    }
    if fd == to {
      continue
    }
    new_preopens.push(preopen)
  }
  if moved is Some(entry) {
    let (host, guest) = entry
    new_preopens.push((Fd(to), host, guest))
  }
  ctx.preopens.clear()
  for preopen in new_preopens {
    ctx.preopens.push(preopen)
  }
}

///|
/// fd_renumber - Renumber file descriptor
pub fn fd_renumber_impl(ctx : WasiContext, from : Int, to : Int) -> Int {
  if !ctx.is_valid_fd(from) || !ctx.is_valid_fd(to) {
    return Errno::Badf.to_i32()
  }
  if from == to {
    return Errno::Success.to_i32()
  }
  let from_slot = stdio_slot_for_fd(ctx, from)
  let to_slot = stdio_slot_for_fd(ctx, to)
  let from_file = if from_slot is Some(_) { None } else { ctx.get_file(from) }
  let to_file = if to_slot is Some(_) { None } else { ctx.get_file(to) }
  if from_slot is None && from_file is None {
    return Errno::Badf.to_i32()
  }
  if to_slot is None && to_file is None {
    return Errno::Badf.to_i32()
  }
  // Keep preopen fd mapping coherent with descriptor movement.
  if preopen_fd_index(ctx, from) is Some(_) ||
    preopen_fd_index(ctx, to) is Some(_) {
    renumber_preopen_entries(ctx, from, to)
  }
  // Closing the destination follows WASI renumber semantics.
  if to_slot is Some(slot) {
    clear_stdio_slot(ctx, slot)
  } else {
    let dst = to_file.unwrap()
    let same_native = match from_file {
      Some(src) => src.native_fd == dst.native_fd
      None => false
    }
    if !same_native {
      native_close(dst.native_fd) |> ignore
    }
    ctx.open_files.remove(to)
  }
  // Move source descriptor to destination.
  if from_slot is Some(slot) {
    move_stdio_slot_to_fd(ctx, slot, to)
  } else {
    let src = from_file.unwrap()
    ctx.open_files.remove(from)
    ctx.open_files.set(to, src)
  }
  Errno::Success.to_i32()
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
  let old_path = match read_path_from_memory(mem, old_path_ptr, old_path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  if old_path.has_prefix("/") {
    return Errno::Perm.to_i32()
  }
  let new_path = match read_path_from_memory(mem, new_path_ptr, new_path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let resolved_path = match
    resolve_host_path_nofollow_leaf(ctx, dir_fd, new_path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  if native_symlinkat(old_path, 0, resolved_path) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
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
  if !check_mem_range(mem, buf_ptr, buf_len) ||
    !check_mem_range(mem, bufused_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  let path = match read_path_from_memory(mem, path_ptr, path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let resolved_path = match resolve_host_path_nofollow_leaf(ctx, dir_fd, path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  let result = native_readlinkat(0, resolved_path, buf_len)
  match result {
    Some(link_target) => {
      let to_write = @cmp.minimum(link_target.length(), buf_len)
      for i in 0..<to_write {
        mem.write_byte(buf_ptr + i, link_target.code_unit_at(i).to_byte())
      }
      mem.write_i32(bufused_ptr, to_write)
      Errno::Success.to_i32()
    }
    None => native_last_errno_to_wasi()
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
  let lookupflags_check = validate_lookupflags(old_flags)
  if lookupflags_check != Errno::Success.to_i32() {
    return lookupflags_check
  }
  let old_path = match read_path_from_memory(mem, old_path_ptr, old_path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let new_path = match read_path_from_memory(mem, new_path_ptr, new_path_len) {
    Ok(path) => path
    Err(errno) => return errno
  }
  let old_resolved = match
    resolve_host_path_nofollow_leaf(ctx, old_fd, old_path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  let new_resolved = match
    resolve_host_path_nofollow_leaf(ctx, new_fd, new_path) {
    Ok(resolved) => resolved
    Err(errno) => return errno
  }
  if (old_flags & 0x01) != 0 {
    return Errno::Inval.to_i32()
  }
  let flags = 0
  if native_linkat(0, old_resolved, 0, new_resolved, flags) {
    Errno::Success.to_i32()
  } else {
    native_last_errno_to_wasi()
  }
}

// ============================================================================
// Phase 5: Poll and socket operations
// ============================================================================

///|
fn poll_clock_remaining_ns(
  clock_id : Int,
  timeout : Int64,
  flags : Int,
) -> Int64? {
  let known_subclockflags_mask = 0x01
  if (flags & known_subclockflags_mask.lnot()) != 0 {
    return None
  }
  let is_absolute = (flags & 0x01) != 0
  if is_absolute {
    match ClockId::from_i32(clock_id) {
      Some(Monotonic) => {
        let now = native_clock_gettime_monotonic()
        Some(if timeout > now { timeout - now } else { 0L })
      }
      Some(Realtime) => {
        let now = native_clock_gettime_realtime()
        Some(if timeout > now { timeout - now } else { 0L })
      }
      _ => None
    }
  } else {
    match ClockId::from_i32(clock_id) {
      Some(Monotonic | Realtime) => Some(timeout)
      _ => None
    }
  }
}

///|
fn poll_clock_is_expired(
  clock_id : Int,
  timeout : Int64,
  flags : Int,
  poll_elapsed_ns : Int64,
  now_monotonic : Int64,
  now_realtime : Int64,
) -> Bool {
  if (flags & 0x01) != 0 {
    match ClockId::from_i32(clock_id) {
      Some(Monotonic) => now_monotonic >= timeout
      Some(Realtime) => now_realtime >= timeout
      _ => false
    }
  } else {
    timeout <= poll_elapsed_ns
  }
}

///|
fn write_poll_event(
  mem : @runtime.Memory,
  event_ptr : Int,
  userdata : Int64,
  event_type : Int,
  nbytes : Int64,
  fd_flags : Int,
) -> Unit {
  mem.write_i64(event_ptr, userdata)
  mem.write_byte(event_ptr + 8, b'\x00') // error = success
  mem.write_byte(event_ptr + 9, b'\x00')
  mem.write_byte(event_ptr + 10, event_type.to_byte()) // type
  for j in 11..<16 {
    mem.write_byte(event_ptr + j, b'\x00')
  }
  mem.write_i64(event_ptr + 16, nbytes)
  mem.write_byte(event_ptr + 24, (fd_flags & 0xFF).to_byte())
  mem.write_byte(event_ptr + 25, ((fd_flags >> 8) & 0xFF).to_byte())
  for j in 26..<32 {
    mem.write_byte(event_ptr + j, b'\x00')
  }
}

///|
fn poll_fd_read_nbytes_and_flags(ctx : WasiContext, fd : Int) -> (Int64, Int) {
  if stdio_slot_for_fd(ctx, fd) is Some(slot) {
    if slot == 0 {
      // Match wasmtime p1 stdio stream behavior for read polling.
      return (1L, 0)
    }
    return (1L, 0)
  }
  let file = match ctx.get_file(fd) {
    Some(file) => file
    None => return (1L, 0)
  }
  match file.file_type {
    RegularFile => ()
    _ => return (1L, 0)
  }
  let stat = match native_fstat(file.native_fd) {
    Some(stat) => stat
    None => return (1L, 0)
  }
  let position = match native_tell(file.native_fd) {
    Some(position) => position
    None => return (1L, 0)
  }
  let position_u = position.reinterpret_as_uint64()
  // WASI eventrwflags bit 0 is FD_READWRITE_HANGUP.
  if stat.size <= position_u {
    (0L, 0x01)
  } else {
    ((stat.size - position_u).reinterpret_as_int64(), 0)
  }
}

///|
fn poll_fd_to_native_fd(ctx : WasiContext, fd : Int, tag : Int) -> Int? {
  if stdio_slot_for_fd(ctx, fd) is Some(slot) {
    if !is_stdio_open(ctx, fd) {
      return None
    }
    if slot == 0 {
      if tag == 1 {
        Some(0)
      } else {
        None
      }
    } else if tag == 2 {
      if slot == 1 {
        Some(1)
      } else {
        Some(2)
      }
    } else {
      None
    }
  } else {
    let file = match ctx.get_file(fd) {
      Some(file) => file
      None => return None
    }
    match file.file_type {
      RegularFile => Some(file.native_fd)
      _ => None
    }
  }
}

///|
fn is_clock_subscription(tag : Int) -> Bool {
  tag == 0
}

///|
fn is_fd_subscription(tag : Int) -> Bool {
  tag == 1 || tag == 2
}

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
  if nsubscriptions < 0 {
    return Errno::Inval.to_i32()
  }
  if nsubscriptions == 0 {
    return Errno::Inval.to_i32()
  }
  if !check_mem_range(mem, nevents_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  let sub_bytes = nsubscriptions * 48
  let event_bytes = nsubscriptions * 32
  if !check_mem_range(mem, in_ptr, sub_bytes) ||
    !check_mem_range(mem, out_ptr, event_bytes) {
    return Errno::Fault.to_i32()
  }

  // Match wasmtime p1: special-case single relative clock sleep and emit
  // clock event with nbytes=1.
  if nsubscriptions == 1 {
    let tag = mem.read_byte(in_ptr + 8).to_int()
    if is_clock_subscription(tag) {
      let flags = mem.read_byte(in_ptr + 40).to_int() |
        (mem.read_byte(in_ptr + 41).to_int() << 8)
      let known_subclockflags_mask = 0x01
      if (flags & known_subclockflags_mask.lnot()) != 0 {
        return Errno::Inval.to_i32()
      }
      if (flags & 0x01) == 0 {
        let timeout = mem.read_i64(in_ptr + 24)
        if timeout > 0L {
          native_nanosleep(timeout) |> ignore
        }
        write_poll_event(mem, out_ptr, mem.read_i64(in_ptr), 0, 1L, 0)
        mem.write_i32(nevents_ptr, 1)
        return Errno::Success.to_i32()
      }
    }
  }

  let ready_by_sub : Array[Bool] = []
  let ready_type_by_sub : Array[Int] = []
  let ready_nbytes_by_sub : Array[Int64] = []
  let ready_flags_by_sub : Array[Int] = []
  for _ in 0..<nsubscriptions {
    ready_by_sub.push(false)
    ready_type_by_sub.push(0)
    ready_nbytes_by_sub.push(0L)
    ready_flags_by_sub.push(0)
  }

  let mut min_timeout_ns : Int64 = -1L
  let clock_sub_indices : Array[Int] = []
  let clock_ids : Array[Int] = []
  let clock_timeouts : Array[Int64] = []
  let clock_flags : Array[Int] = []
  let fds : Array[Int] = []
  let events : Array[Int] = []
  let fd_sub_indices : Array[Int] = []
  let fd_event_types : Array[Int] = []
  let fd_wasi_fds : Array[Int] = []

  for i in 0..<nsubscriptions {
    let sub_ptr = in_ptr + i * 48
    let tag = mem.read_byte(sub_ptr + 8).to_int()
    if is_clock_subscription(tag) {
      let clock_id = mem.read_i32(sub_ptr + 16)
      let timeout = mem.read_i64(sub_ptr + 24)
      let flags = mem.read_byte(sub_ptr + 40).to_int() |
        (mem.read_byte(sub_ptr + 41).to_int() << 8)
      let timeout_ns = match poll_clock_remaining_ns(clock_id, timeout, flags) {
        Some(timeout_ns) => timeout_ns
        None => return Errno::Inval.to_i32()
      }
      if min_timeout_ns < 0L || timeout_ns < min_timeout_ns {
        min_timeout_ns = timeout_ns
      }
      clock_sub_indices.push(i)
      clock_ids.push(clock_id)
      clock_timeouts.push(timeout)
      clock_flags.push(flags)
    } else if is_fd_subscription(tag) {
      let fd = mem.read_i32(sub_ptr + 12)
      let native_fd = match poll_fd_to_native_fd(ctx, fd, tag) {
        Some(native_fd) => native_fd
        None => return Errno::Badf.to_i32()
      }
      fds.push(native_fd)
      events.push(if tag == 1 { 0x01 } else { 0x04 })
      fd_sub_indices.push(i)
      fd_event_types.push(tag)
      fd_wasi_fds.push(fd)
    } else {
      return Errno::Inval.to_i32()
    }
  }

  let mut events_written = 0
  let poll_start_monotonic = native_clock_gettime_monotonic()
  let timeout_ms = if min_timeout_ns < 0L {
    -1
  } else if min_timeout_ns == 0L {
    0
  } else {
    let timeout_ms = (min_timeout_ns / 1000000L).to_int()
    if timeout_ms == 0 {
      1
    } else {
      timeout_ms
    }
  }

  if fds.length() > 0 {
    let poll_result = native_poll(fds, events, timeout_ms)
    if poll_result is None {
      return native_last_errno_to_wasi()
    }
    let result = poll_result.unwrap()
    for i, sub_idx in fd_sub_indices {
      if result.revents[i] != 0 {
        let event_type = fd_event_types[i]
        let fd = fd_wasi_fds[i]
        ready_by_sub[sub_idx] = true
        ready_type_by_sub[sub_idx] = event_type
        if event_type == 1 {
          let (nbytes, flags) = poll_fd_read_nbytes_and_flags(ctx, fd)
          ready_nbytes_by_sub[sub_idx] = nbytes
          ready_flags_by_sub[sub_idx] = flags
        } else {
          ready_nbytes_by_sub[sub_idx] = 1L
          ready_flags_by_sub[sub_idx] = 0
        }
      }
    }
  } else if min_timeout_ns >= 0L {
    native_nanosleep(min_timeout_ns) |> ignore
  }

  let poll_end_monotonic = native_clock_gettime_monotonic()
  let poll_elapsed_ns = if poll_end_monotonic > poll_start_monotonic {
    poll_end_monotonic - poll_start_monotonic
  } else {
    0L
  }

  let now_monotonic = poll_end_monotonic
  let now_realtime = native_clock_gettime_realtime()
  for i, sub_idx in clock_sub_indices {
    let clock_id = clock_ids[i]
    let timeout = clock_timeouts[i]
    let flags = clock_flags[i]
    if poll_clock_is_expired(
        clock_id, timeout, flags, poll_elapsed_ns, now_monotonic, now_realtime,
      ) {
      ready_by_sub[sub_idx] = true
      ready_type_by_sub[sub_idx] = 0
      ready_nbytes_by_sub[sub_idx] = 0L
      ready_flags_by_sub[sub_idx] = 0
    }
  }

  for i in 0..<nsubscriptions {
    if ready_by_sub[i] && events_written < nsubscriptions {
      let sub_ptr = in_ptr + i * 48
      let event_ptr = out_ptr + events_written * 32
      let userdata = mem.read_i64(sub_ptr)
      write_poll_event(
        mem,
        event_ptr,
        userdata,
        ready_type_by_sub[i],
        ready_nbytes_by_sub[i],
        ready_flags_by_sub[i],
      )
      events_written = events_written + 1
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
  if !check_mem_range(mem, ro_datalen_ptr, 4) ||
    !check_mem_range(mem, ro_flags_ptr, 2) {
    return Errno::Fault.to_i32()
  }
  if !check_iovecs_mem_range(mem, ri_data_ptr, ri_data_len) {
    return Errno::Fault.to_i32()
  }
  let riflags_check = validate_sock_recv_riflags(ri_flags)
  if riflags_check != Errno::Success.to_i32() {
    return riflags_check
  }
  if is_valid_descriptor_for_sock(ctx, fd) {
    Errno::NotSock.to_i32()
  } else {
    Errno::Badf.to_i32()
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
  if !check_mem_range(mem, so_datalen_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  if !check_iovecs_mem_range(mem, si_data_ptr, si_data_len) {
    return Errno::Fault.to_i32()
  }
  if is_valid_descriptor_for_sock(ctx, fd) {
    Errno::NotSock.to_i32()
  } else {
    Errno::Badf.to_i32()
  }
}

///|
/// sock_shutdown - Shutdown socket
pub fn sock_shutdown_impl(ctx : WasiContext, fd : Int, how : Int) -> Int {
  let sdflags_check = validate_sock_shutdown_sdflags(how)
  if sdflags_check != Errno::Success.to_i32() {
    return sdflags_check
  }
  if is_valid_descriptor_for_sock(ctx, fd) {
    Errno::NotSock.to_i32()
  } else {
    Errno::Badf.to_i32()
  }
}

///|
/// sock_accept - Accept a connection on a socket
pub fn sock_accept_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  fd : Int,
  flags : Int,
  result_fd_ptr : Int,
) -> Int {
  if !check_mem_range(mem, result_fd_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  let fdflags_check = validate_sock_accept_fdflags(flags)
  if fdflags_check != Errno::Success.to_i32() {
    return fdflags_check
  }
  if is_valid_descriptor_for_sock(ctx, fd) {
    Errno::NotSock.to_i32()
  } else {
    Errno::Badf.to_i32()
  }
}

///|
/// proc_raise - Send a signal to the process
pub fn proc_raise_impl(signal : Int) -> Int {
  let signal_check = validate_proc_raise_signal(signal)
  if signal_check != Errno::Success.to_i32() {
    return signal_check
  }
  Errno::NotSup.to_i32()
}
