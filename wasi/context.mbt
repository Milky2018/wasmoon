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
  println(buf.to_string())
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
  let mut fd = 3
  for preopen in self.preopens {
    let (host, guest) = preopen
    preopens.push((Fd(fd), host, guest))
    fd = fd + 1
  }
  {
    args: self.args,
    env: self.env,
    exit_code: None,
    preopens,
    next_fd: fd,
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
