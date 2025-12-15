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
    stdout_callback: fn(bytes) { print_bytes(bytes) },
    stderr_callback: fn(bytes) { print_bytes(bytes) },
    stdin_callback: fn() { b"" },
  }
}

///|
fn print_bytes(bytes : Bytes) -> Unit {
  // Convert bytes to string and print
  let buf = StringBuilder::new()
  for i in 0..<bytes.length() {
    let c = bytes[i].to_int()
    if c >= 32 && c < 127 {
      buf.write_char(c.unsafe_to_char())
    } else if c == 10 {
      buf.write_char('\n')
    } else if c == 13 {
      buf.write_char('\r')
    } else if c == 9 {
      buf.write_char('\t')
    } else {
      buf.write_char('?')
    }
  }
  print_string(buf.to_string())
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
  self
}

///|
/// Set stderr callback
pub fn WasiContextBuilder::stderr(
  self : WasiContextBuilder,
  callback : (Bytes) -> Unit,
) -> WasiContextBuilder {
  self.stderr_callback = Some(callback)
  self
}

///|
/// Set stdin callback
pub fn WasiContextBuilder::stdin(
  self : WasiContextBuilder,
  callback : () -> Bytes,
) -> WasiContextBuilder {
  self.stdin_callback = Some(callback)
  self
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
    stdout_callback: self.stdout_callback.unwrap_or(fn(bytes) {
      print_bytes(bytes)
    }),
    stderr_callback: self.stderr_callback.unwrap_or(fn(bytes) {
      print_bytes(bytes)
    }),
    stdin_callback: self.stdin_callback.unwrap_or(fn() { b"" }),
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
/// Resolve a path relative to a directory fd
pub fn WasiContext::resolve_path(
  self : WasiContext,
  dir_fd : Int,
  path : String,
) -> String? {
  // If dir_fd is a preopen directory, resolve relative to it
  if self.get_preopen_host_path(dir_fd) is Some(host_path) {
    if path.length() == 0 {
      Some(host_path)
    } else if path.has_prefix("/") {
      // Absolute path - should be restricted, but for simplicity we just use host_path as root
      Some(host_path + path)
    } else {
      Some(host_path + "/" + path)
    }
  } else {
    // Check if it's a regular open directory
    match self.get_file(dir_fd) {
      Some(file) =>
        if file.file_type is Directory {
          if path.length() == 0 {
            Some(file.host_path)
          } else if path.has_prefix("/") {
            Some(file.host_path + path)
          } else {
            Some(file.host_path + "/" + path)
          }
        } else {
          None
        }
      None => None
    }
  }
}
