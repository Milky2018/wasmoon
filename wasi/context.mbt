///|
/// File type for open file descriptors
pub(all) enum FileType {
  /// Regular file
  RegularFile
  /// Directory
  Directory
  /// Stdin/Stdout/Stderr (character device)
  CharacterDevice
}

///|
/// Open file entry
pub(all) struct OpenFile {
  /// Native file descriptor
  native_fd : Int
  /// File type
  file_type : FileType
  /// Host path (for debugging)
  host_path : String
  /// Current position (tracked separately for virtual files)
  mut position : Int64
  /// File access flags
  flags : Int
}

///|
/// WASI execution context
/// Maintains state for WASI function calls
pub(all) struct WasiContext {
  /// Command line arguments
  args : Array[String]
  /// Environment variables (key=value pairs)
  env : Array[String]
  /// Exit code (set by proc_exit)
  mut exit_code : Int?
  /// Preopen directories: (fd, host_path, guest_path)
  preopens : Array[(Fd, String, String)]
  /// Next available file descriptor
  mut next_fd : Int
  /// Open files: wasi_fd -> OpenFile
  open_files : @hashmap.HashMap[Int, OpenFile]
  /// Output callback for stdout
  stdout_callback : (Bytes) -> Unit
  /// Output callback for stderr
  stderr_callback : (Bytes) -> Unit
  /// Input callback for stdin (returns available bytes)
  stdin_callback : () -> Bytes
  /// Whether stdout should use native file descriptor
  stdout_is_native : Bool
  /// Whether stderr should use native file descriptor
  stderr_is_native : Bool
  /// Whether stdin should use native file descriptor
  stdin_is_native : Bool
}

///|
/// Create a new WASI context with default settings
pub fn WasiContext::new() -> WasiContext {
  {
    args: [],
    env: [],
    exit_code: None,
    preopens: [],
    next_fd: 3, // 0=stdin, 1=stdout, 2=stderr
    open_files: @hashmap.new(),
    stdout_callback: write_native_stdout,
    stderr_callback: write_native_stderr,
    stdin_callback: fn() { b"" },
    stdout_is_native: true,
    stderr_is_native: true,
    stdin_is_native: false,
  }
}

///|
/// Builder for WasiContext
pub(all) struct WasiContextBuilder {
  mut args : Array[String]
  env : Array[String]
  preopens : Array[(String, String)]
  mut stdout_callback : ((Bytes) -> Unit)?
  mut stderr_callback : ((Bytes) -> Unit)?
  mut stdin_callback : (() -> Bytes)?
  mut stdout_is_native : Bool
  mut stderr_is_native : Bool
  mut stdin_is_native : Bool
}

///|
pub fn WasiContextBuilder::new() -> WasiContextBuilder {
  {
    args: [],
    env: [],
    preopens: [],
    stdout_callback: None,
    stderr_callback: None,
    stdin_callback: None,
    stdout_is_native: true,
    stderr_is_native: true,
    stdin_is_native: false,
  }
}

///|
/// Set program arguments (argv)
pub fn WasiContextBuilder::args(
  self : WasiContextBuilder,
  args : Array[String],
) -> WasiContextBuilder {
  self.args = args
  self
}

///|
/// Add an environment variable
pub fn WasiContextBuilder::env(
  self : WasiContextBuilder,
  key : String,
  value : String,
) -> WasiContextBuilder {
  self.env.push("\{key}=\{value}")
  self
}

///|
/// Add a preopen directory
pub fn WasiContextBuilder::preopen_dir(
  self : WasiContextBuilder,
  host_path : String,
  guest_path : String,
) -> WasiContextBuilder {
  self.preopens.push((host_path, guest_path))
  self
}

///|
/// Set stdout callback
pub fn WasiContextBuilder::stdout(
  self : WasiContextBuilder,
  callback : (Bytes) -> Unit,
) -> WasiContextBuilder {
  self.stdout_callback = Some(callback)
  self.stdout_is_native = false
  self
}

///|
/// Set stderr callback
pub fn WasiContextBuilder::stderr(
  self : WasiContextBuilder,
  callback : (Bytes) -> Unit,
) -> WasiContextBuilder {
  self.stderr_callback = Some(callback)
  self.stderr_is_native = false
  self
}

///|
/// Set stdin callback
pub fn WasiContextBuilder::stdin(
  self : WasiContextBuilder,
  callback : () -> Bytes,
) -> WasiContextBuilder {
  self.stdin_callback = Some(callback)
  self.stdin_is_native = false
  self
}

///|
/// Inherit stdin from host process
pub fn WasiContextBuilder::inherit_stdin(
  self : WasiContextBuilder,
) -> WasiContextBuilder {
  self.stdin_callback = Some(read_native_stdin)
  self.stdin_is_native = true
  self
}

///|
/// Inherit stdout from host process
pub fn WasiContextBuilder::inherit_stdout(
  self : WasiContextBuilder,
) -> WasiContextBuilder {
  self.stdout_callback = Some(write_native_stdout)
  self.stdout_is_native = true
  self
}

///|
/// Inherit stderr from host process
pub fn WasiContextBuilder::inherit_stderr(
  self : WasiContextBuilder,
) -> WasiContextBuilder {
  self.stderr_callback = Some(write_native_stderr)
  self.stderr_is_native = true
  self
}

///|
/// Inherit all stdio (stdin, stdout, stderr) from host process
pub fn WasiContextBuilder::inherit_stdio(
  self : WasiContextBuilder,
) -> WasiContextBuilder {
  self.inherit_stdin().inherit_stdout().inherit_stderr()
}

///|
/// Read from native stdin (fd 0)
fn read_native_stdin() -> Bytes {
  let buf = FixedArray::make(4096, b'\x00')
  match native_read(0, buf, 4096) {
    Some(n) if n > 0 => {
      let result : Array[Byte] = Array::make(n, b'\x00')
      for i in 0..<n {
        result[i] = buf[i]
      }
      Bytes::from_array(result)
    }
    _ => b""
  }
}

///|
/// Write to native stdout (fd 1)
fn write_native_stdout(bytes : Bytes) -> Unit {
  if bytes.length() > 0 {
    let buf = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
    native_write(1, buf, bytes.length()) |> ignore
  }
}

///|
/// Write to native stderr (fd 2)
fn write_native_stderr(bytes : Bytes) -> Unit {
  if bytes.length() > 0 {
    let buf = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
    native_write(2, buf, bytes.length()) |> ignore
  }
}

///|
/// Build the WasiContext
pub fn WasiContextBuilder::build(self : WasiContextBuilder) -> WasiContext {
  let preopens : Array[(Fd, String, String)] = []
  let open_files : @hashmap.HashMap[Int, OpenFile] = @hashmap.new()
  let mut fd = 3
  for preopen in self.preopens {
    let (host, guest) = preopen
    preopens.push((Fd(fd), host, guest))
    // Open the preopen directory with native open
    let native_fd = native_open(host, [ReadOnly, Directory], 0)
    if native_fd is Some(nfd) {
      open_files.set(fd, {
        native_fd: nfd,
        file_type: Directory,
        host_path: host,
        position: 0L,
        flags: 0, // Read-only
      })
    }
    fd = fd + 1
  }
  {
    args: self.args,
    env: self.env,
    exit_code: None,
    preopens,
    next_fd: fd,
    open_files,
    stdout_callback: self.stdout_callback.unwrap_or(write_native_stdout),
    stderr_callback: self.stderr_callback.unwrap_or(write_native_stderr),
    stdin_callback: self.stdin_callback.unwrap_or(fn() { b"" }),
    stdout_is_native: self.stdout_is_native,
    stderr_is_native: self.stderr_is_native,
    stdin_is_native: self.stdin_is_native,
  }
}

///|
/// Check if the WASI process has exited
pub fn WasiContext::has_exited(self : WasiContext) -> Bool {
  self.exit_code is Some(_)
}

///|
/// Get the exit code (if process has exited)
pub fn WasiContext::get_exit_code(self : WasiContext) -> Int? {
  self.exit_code
}

///|
/// Allocate a new file descriptor and register an open file
pub fn WasiContext::alloc_fd(self : WasiContext, file : OpenFile) -> Int {
  let fd = self.next_fd
  self.next_fd = self.next_fd + 1
  self.open_files.set(fd, file)
  fd
}

///|
/// Get an open file by WASI file descriptor
pub fn WasiContext::get_file(self : WasiContext, fd : Int) -> OpenFile? {
  self.open_files.get(fd)
}

///|
/// Close a file descriptor and remove it from tracking
pub fn WasiContext::close_fd(self : WasiContext, fd : Int) -> Bool {
  match self.open_files.get(fd) {
    Some(file) => {
      // Close native file descriptor
      native_close(file.native_fd) |> ignore
      self.open_files.remove(fd)
      true
    }
    None => false
  }
}

///|
/// Check if a file descriptor is valid
pub fn WasiContext::is_valid_fd(self : WasiContext, fd : Int) -> Bool {
  // stdin, stdout, stderr are always valid
  fd == 0 || fd == 1 || fd == 2 || self.open_files.contains(fd)
}

///|
/// Get the host path for a preopen directory by fd
pub fn WasiContext::get_preopen_host_path(
  self : WasiContext,
  fd : Int,
) -> String? {
  for preopen in self.preopens {
    let (preopen_fd, host_path, _) = preopen
    if preopen_fd.to_int() == fd {
      return Some(host_path)
    }
  }
  None
}

///|
/// Normalize a guest path and reject escapes from the preopen root.
fn sanitize_guest_path(path : String) -> String? {
  if path.length() == 0 {
    return Some("")
  }
  if path.has_prefix("/") {
    return None
  }
  let parts : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i <= path.length() {
    if i == path.length() || path.code_unit_at(i) == '/' {
      let seg = if i == start { "" } else { try! path[start:i].to_string() }
      if seg == "" || seg == "." {
        ()
      } else if seg == ".." {
        if parts.is_empty() {
          return None
        }
        parts.pop() |> ignore
      } else {
        parts.push(seg)
      }
      start = i + 1
    }
    i = i + 1
  }
  Some(parts.join("/"))
}

///|
/// Resolve a path relative to a directory fd
pub fn WasiContext::resolve_path(
  self : WasiContext,
  dir_fd : Int,
  path : String,
) -> String? {
  let normalized = match sanitize_guest_path(path) {
    Some(p) => p
    None => return None
  }
  // If dir_fd is a preopen directory, resolve relative to it
  if self.get_preopen_host_path(dir_fd) is Some(host_path) {
    if normalized.length() == 0 {
      Some(host_path)
    } else {
      Some(host_path + "/" + normalized)
    }
  } else {
    // Check if it's a regular open directory
    match self.get_file(dir_fd) {
      Some(file) =>
        if file.file_type is Directory {
          if normalized.length() == 0 {
            Some(file.host_path)
          } else {
            Some(file.host_path + "/" + normalized)
          }
        } else {
          None
        }
      None => None
    }
  }
}
