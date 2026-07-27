///|
/// Capability and process state supplied to a WASI component.
///
/// The context contains no ambient filesystem or network authority. Those
/// capabilities are added explicitly by later builder methods.
struct WasiComponentCtx {
  args : Array[String]
  environment : Array[(String, String)]
  initial_cwd : String?
  exit_status : Ref[Int?]
  insecure_state : Ref[Int64]
  insecure_seed : (Int64, Int64)
  resources : Map[Int, WasiHostResource]
  next_resource_rep : Ref[Int]
  async_deadlines : Map[Int, Int64]
  next_async_operation : Ref[Int]
  stdin_rep : Int
  stdout_rep : Int
  stderr_rep : Int
}

///|
struct WasiComponentCtxBuilder {
  mut args : Array[String]
  environment : Array[(String, String)]
  mut initial_cwd : String?
  mut insecure_seed : (Int64, Int64)
  mut stdin : Bytes
  mut inherit_stdin : Bool
  mut stdout : (Bytes) -> Unit
  mut stderr : (Bytes) -> Unit
}

///|
pub fn WasiComponentCtxBuilder::WasiComponentCtxBuilder() -> WasiComponentCtxBuilder {
  {
    args: [],
    environment: [],
    initial_cwd: None,
    insecure_seed: (0x4d595df4d0f33173L, 0x123456789abcdefL),
    stdin: b"",
    inherit_stdin: false,
    stdout: fn(_bytes) { () },
    stderr: fn(_bytes) { () },
  }
}

///|
pub fn WasiComponentCtxBuilder::args(
  self : WasiComponentCtxBuilder,
  args : Array[String],
) -> WasiComponentCtxBuilder {
  self.args = args.copy()
  self
}

///|
pub fn WasiComponentCtxBuilder::env(
  self : WasiComponentCtxBuilder,
  key : String,
  value : String,
) -> WasiComponentCtxBuilder {
  self.environment.push((key, value))
  self
}

///|
pub fn WasiComponentCtxBuilder::initial_cwd(
  self : WasiComponentCtxBuilder,
  path : String,
) -> WasiComponentCtxBuilder {
  self.initial_cwd = Some(path)
  self
}

///|
/// Configure the deterministic generator used only by `wasi:random/insecure`
/// and `wasi:random/insecure-seed`.
pub fn WasiComponentCtxBuilder::insecure_seed(
  self : WasiComponentCtxBuilder,
  low : Int64,
  high : Int64,
) -> WasiComponentCtxBuilder {
  self.insecure_seed = (low, high)
  self
}

///|
pub fn WasiComponentCtxBuilder::stdin(
  self : WasiComponentCtxBuilder,
  bytes : Bytes,
) -> WasiComponentCtxBuilder {
  self.stdin = bytes
  self.inherit_stdin = false
  self
}

///|
pub fn WasiComponentCtxBuilder::stdout(
  self : WasiComponentCtxBuilder,
  write : (Bytes) -> Unit,
) -> WasiComponentCtxBuilder {
  self.stdout = write
  self
}

///|
pub fn WasiComponentCtxBuilder::stderr(
  self : WasiComponentCtxBuilder,
  write : (Bytes) -> Unit,
) -> WasiComponentCtxBuilder {
  self.stderr = write
  self
}

///|
pub fn WasiComponentCtxBuilder::inherit_stdin(
  self : WasiComponentCtxBuilder,
) -> WasiComponentCtxBuilder {
  self.inherit_stdin = true
  self
}

///|
pub fn WasiComponentCtxBuilder::inherit_stdout(
  self : WasiComponentCtxBuilder,
) -> WasiComponentCtxBuilder {
  self.stdout = fn(bytes) {
    if bytes.length() > 0 {
      let buffer = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
      @wasi.native_write(1, buffer, buffer.length()) |> ignore
    }
  }
  self
}

///|
pub fn WasiComponentCtxBuilder::inherit_stderr(
  self : WasiComponentCtxBuilder,
) -> WasiComponentCtxBuilder {
  self.stderr = fn(bytes) {
    if bytes.length() > 0 {
      let buffer = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
      @wasi.native_write(2, buffer, buffer.length()) |> ignore
    }
  }
  self
}

///|
pub fn WasiComponentCtxBuilder::inherit_stdio(
  self : WasiComponentCtxBuilder,
) -> WasiComponentCtxBuilder {
  self.inherit_stdin().inherit_stdout().inherit_stderr()
}

///|
pub fn WasiComponentCtxBuilder::build(
  self : WasiComponentCtxBuilder,
) -> WasiComponentCtx {
  let (low, high) = self.insecure_seed
  let initial_state = if low == 0L && high == 0L {
    0x4d595df4d0f33173L
  } else {
    low ^ high
  }
  let resources : Map[Int, WasiHostResource] = Map([])
  let stdin_rep = 1
  let stdout_rep = 2
  let stderr_rep = 3
  resources.set(
    stdin_rep,
    InputStream({
      bytes: Ref(self.stdin),
      offset: Ref(0),
      native_fd: if self.inherit_stdin {
        Some(0)
      } else {
        None
      },
      closed: Ref(false),
    }),
  )
  resources.set(
    stdout_rep,
    OutputStream({ write: self.stdout, permit: Ref(0L), closed: Ref(false) }),
  )
  resources.set(
    stderr_rep,
    OutputStream({ write: self.stderr, permit: Ref(0L), closed: Ref(false) }),
  )
  {
    args: self.args.copy(),
    environment: self.environment.copy(),
    initial_cwd: self.initial_cwd,
    exit_status: Ref(None),
    insecure_state: Ref(initial_state),
    insecure_seed: self.insecure_seed,
    resources,
    next_resource_rep: Ref(4),
    async_deadlines: Map([]),
    next_async_operation: Ref(1),
    stdin_rep,
    stdout_rep,
    stderr_rep,
  }
}

///|
pub fn WasiComponentCtx::arguments(self : WasiComponentCtx) -> Array[String] {
  self.args.copy()
}

///|
pub fn WasiComponentCtx::environment(
  self : WasiComponentCtx,
) -> Array[(String, String)] {
  self.environment.copy()
}

///|
pub fn WasiComponentCtx::initial_cwd(self : WasiComponentCtx) -> String? {
  self.initial_cwd
}

///|
pub fn WasiComponentCtx::exit_status(self : WasiComponentCtx) -> Int? {
  self.exit_status.val
}

///|
fn WasiComponentCtx::request_exit(
  self : WasiComponentCtx,
  status : Int,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  self.exit_status.val = Some(status)
  raise HostExit(status)
}

///|
fn WasiComponentCtx::next_insecure_u64(self : WasiComponentCtx) -> Int64 {
  let mut value = self.insecure_state.val
  value = value ^ (value << 13)
  value = value ^ (value >> 7)
  value = value ^ (value << 17)
  self.insecure_state.val = value
  value
}

///|
priv struct InputStreamState {
  bytes : Ref[Bytes]
  offset : Ref[Int]
  native_fd : Int?
  closed : Ref[Bool]
}

///|
priv struct OutputStreamState {
  write : (Bytes) -> Unit
  permit : Ref[Int64]
  closed : Ref[Bool]
}

///|
priv enum PollSource {
  Deadline(Int64)
  Input(Int)
  Output(Int)
}

///|
priv enum WasiHostResource {
  IoError(String)
  InputStream(InputStreamState)
  OutputStream(OutputStreamState)
  Pollable(PollSource)
}

///|
fn WasiComponentCtx::insert_resource(
  self : WasiComponentCtx,
  resource : WasiHostResource,
) -> Int {
  let rep = self.next_resource_rep.val
  self.next_resource_rep.val = rep + 1
  self.resources.set(rep, resource)
  rep
}

///|
fn WasiComponentCtx::get_resource(
  self : WasiComponentCtx,
  rep : Int,
) -> WasiHostResource? {
  self.resources.get(rep)
}

///|
fn WasiComponentCtx::register_deadline(
  self : WasiComponentCtx,
  deadline : Int64,
) -> Int {
  let id = self.next_async_operation.val
  self.next_async_operation.val = id + 1
  self.async_deadlines.set(id, deadline)
  id
}

///|
fn WasiComponentCtx::deadline_ready(self : WasiComponentCtx, id : Int) -> Bool {
  match self.async_deadlines.get(id) {
    Some(deadline) => {
      let now = @wasi.native_clock_gettime_monotonic()
      if now >= 0L && now >= deadline {
        self.async_deadlines.remove(id)
        true
      } else {
        false
      }
    }
    None => true
  }
}

///|
fn WasiComponentCtx::cancel_deadline(self : WasiComponentCtx, id : Int) -> Unit {
  self.async_deadlines.remove(id)
}

///|
fn WasiComponentCtx::wait_for_async_event(
  self : WasiComponentCtx,
) -> Bool raise @runtime_impl.ComponentRuntimeError {
  let mut nearest : Int64? = None
  for entry in self.async_deadlines.iter() {
    let (_id, deadline) = entry
    match nearest {
      Some(current) if current <= deadline => ()
      _ => nearest = Some(deadline)
    }
  }
  match nearest {
    None => false
    Some(deadline) => {
      let now = @wasi.native_clock_gettime_monotonic()
      if now < 0L {
        raise HostCallError("monotonic clock is unavailable")
      }
      if deadline > now {
        @wasi.native_nanosleep(deadline - now) |> ignore
      }
      true
    }
  }
}
