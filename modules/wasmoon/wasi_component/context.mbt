///|
priv struct WasiAsyncOperation {
  registration : @async_native.NativeRegistration
}

///|
/// Capability and process state supplied to a WASI component.
///
/// The context contains no ambient filesystem or network authority. Those
/// capabilities are added explicitly by later builder methods.
struct WasiComponentCtx {
  args : Array[String]
  environment : Array[(String, String)]
  initial_cwd : String?
  exit_status : Ref[Int32?]
  insecure_state : Ref[Int64]
  insecure_seed : (Int64, Int64)
  resources : Map[Int32, WasiHostResourceEntry]
  next_resource_rep : Ref[Int32]
  native_reactor : @async_native.NativeReactor?
  stdin_rep : Int32
  stdout_rep : Int32
  stderr_rep : Int32
  network_rep : Int32
  preopens : Array[PreopenState]
  runtime_owner_claimed : Ref[Bool]
  closed : Ref[Bool]
}

///|
/// Exclusive authority to close a context owned by an embedding runtime.
///
/// This capability is produced only by a successful runtime-owner claim.
struct WasiComponentCtxRuntimeOwner {
  ctx : WasiComponentCtx
}

///|
pub(all) enum WasiNetworkPolicy {
  DenyAll
  LoopbackOnly
  AllowAll
} derive(Eq)

///|
struct WasiComponentCtxBuilder {
  mut args : Array[String]
  environment : Array[(String, String)]
  mut initial_cwd : String?
  mut insecure_seed : (Int64, Int64)
  mut stdin : Bytes
  mut inherit_stdin : Bool
  mut stdout : (Bytes) -> Bool
  mut stderr : (Bytes) -> Bool
  mut stdout_fd : Int32?
  mut stderr_fd : Int32?
  mut network_policy : WasiNetworkPolicy
  preopens : Array[PreopenState]
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
    stdout: fn(_bytes) { true },
    stderr: fn(_bytes) { true },
    stdout_fd: None,
    stderr_fd: None,
    network_policy: DenyAll,
    preopens: [],
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
  self.stdout = fn(bytes) {
    write(bytes)
    true
  }
  self.stdout_fd = None
  self
}

///|
pub fn WasiComponentCtxBuilder::stderr(
  self : WasiComponentCtxBuilder,
  write : (Bytes) -> Unit,
) -> WasiComponentCtxBuilder {
  self.stderr = fn(bytes) {
    write(bytes)
    true
  }
  self.stderr_fd = None
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
  self.stdout_fd = Some(1)
  self
}

///|
pub fn WasiComponentCtxBuilder::inherit_stderr(
  self : WasiComponentCtxBuilder,
) -> WasiComponentCtxBuilder {
  self.stderr_fd = Some(2)
  self
}

///|
pub fn WasiComponentCtxBuilder::inherit_stdio(
  self : WasiComponentCtxBuilder,
) -> WasiComponentCtxBuilder {
  self.inherit_stdin().inherit_stdout().inherit_stderr()
}

///|
/// Set the explicit network capability granted to this component.
///
/// The default is `DenyAll`. `LoopbackOnly` permits bind, connect, and name
/// lookup only for loopback addresses and `localhost`.
pub fn WasiComponentCtxBuilder::network_policy(
  self : WasiComponentCtxBuilder,
  policy : WasiNetworkPolicy,
) -> WasiComponentCtxBuilder {
  self.network_policy = policy
  self
}

///|
/// Grant one host directory to the component under `guest_path`.
///
/// The host path is opened immediately and all guest path operations remain
/// rooted at that directory descriptor. Set `read_only` to reject every
/// operation which mutates directory entries or file contents.
pub fn WasiComponentCtxBuilder::preopened_directory(
  self : WasiComponentCtxBuilder,
  host_path : String,
  guest_path : String,
  read_only : Bool,
) -> WasiComponentCtxBuilder raise @runtime_impl.ComponentRuntimeError {
  if guest_path == "" {
    raise HostCallError("preopen guest path must not be empty")
  }
  match @wasi.native_open(host_path, [ReadOnly, Directory], 0) {
    Some(fd) => {
      self.preopens.push({
        fd,
        guest_path,
        flags: if read_only {
          descriptor_read
        } else {
          descriptor_all
        },
        closed: Ref(false),
      })
      self
    }
    None =>
      raise HostCallError(
        "cannot preopen '\{host_path}': \{@wasi.native_get_error_message()}",
      )
  }
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
  let resources : Map[Int32, WasiHostResourceEntry] = Map([])
  let stdin_rep = 1
  let stdout_rep = 2
  let stderr_rep = 3
  let network_rep = 4
  let stdin_fd = if self.inherit_stdin {
    Some(@wasi.native_dup(0).unwrap_or(-1))
  } else {
    None
  }
  let stdout_fd = match self.stdout_fd {
    Some(fd) => Some(@wasi.native_dup(fd).unwrap_or(-1))
    None => None
  }
  let stderr_fd = match self.stderr_fd {
    Some(fd) => Some(@wasi.native_dup(fd).unwrap_or(-1))
    None => None
  }
  let native_reactor = Some(@async_native.NativeReactor::try_new()) catch {
    _ => None
  }
  resources.set(
    stdin_rep,
    new_resource_entry(
      InputStream({
        bytes: Ref(self.stdin),
        offset: Ref(0),
        native_fd: stdin_fd,
        file_position: None,
        owns_fd: stdin_fd is Some(fd) && fd >= 0,
        closed: Ref(false),
      }),
    ),
  )
  resources.set(network_rep, new_resource_entry(Network(self.network_policy)))
  resources.set(
    stdout_rep,
    new_resource_entry(
      OutputStream({
        write: self.stdout,
        native_fd: stdout_fd,
        file_position: None,
        append: false,
        owns_fd: stdout_fd is Some(fd) && fd >= 0,
        permit: Ref(0L),
        pending: Ref(None),
        failure: Ref(None),
        closed: Ref(false),
      }),
    ),
  )
  resources.set(
    stderr_rep,
    new_resource_entry(
      OutputStream({
        write: self.stderr,
        native_fd: stderr_fd,
        file_position: None,
        append: false,
        owns_fd: stderr_fd is Some(fd) && fd >= 0,
        permit: Ref(0L),
        pending: Ref(None),
        failure: Ref(None),
        closed: Ref(false),
      }),
    ),
  )
  {
    args: self.args.copy(),
    environment: self.environment.copy(),
    initial_cwd: self.initial_cwd,
    exit_status: Ref(None),
    insecure_state: Ref(initial_state),
    insecure_seed: self.insecure_seed,
    resources,
    next_resource_rep: Ref(5),
    native_reactor,
    stdin_rep,
    stdout_rep,
    stderr_rep,
    network_rep,
    preopens: self.preopens.copy(),
    runtime_owner_claimed: Ref(false),
    closed: Ref(false),
  }
}

///|
/// Claim this context for one embedding runtime.
///
/// The claim is terminal and shared by every alias of this context. Embedding
/// adapters must acquire it before installing host functions that capture the
/// context.
pub fn WasiComponentCtx::try_claim_runtime_owner(
  self : WasiComponentCtx,
) -> WasiComponentCtxRuntimeOwner? {
  if self.closed.val || self.runtime_owner_claimed.val {
    None
  } else {
    self.runtime_owner_claimed.val = true
    Some({ ctx: self, })
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
pub fn WasiComponentCtx::exit_status(self : WasiComponentCtx) -> Int32? {
  self.exit_status.val
}

///|
/// Release every host resource owned by this unclaimed context.
///
/// Call this after component execution has ended. Pending native operations
/// are cancelled before their source descriptors close. Repeated calls are
/// harmless, and the context is terminal after the first call. Once an
/// embedding runtime claims this context, only its runtime-owner capability
/// can close it; calls through ordinary context aliases have no effect.
pub fn WasiComponentCtx::close(self : WasiComponentCtx) -> Unit {
  if self.runtime_owner_claimed.val {
    return
  }
  self.close_resources()
}

///|
/// Close the claimed context through its exclusive runtime-owner capability.
///
/// Repeated calls through capability aliases are harmless.
pub fn WasiComponentCtxRuntimeOwner::close(
  self : WasiComponentCtxRuntimeOwner,
) -> Unit {
  self.ctx.close_resources()
}

///|
fn WasiComponentCtx::close_resources(self : WasiComponentCtx) -> Unit {
  if self.closed.val {
    return
  }
  self.closed.val = true
  match self.native_reactor {
    Some(reactor) => reactor.close()
    None => ()
  }
  for entry in self.resources.to_array() {
    let (rep, _resource) = entry
    self.drop_resource(rep)
  }
  for preopen in self.preopens {
    if !preopen.closed.val {
      preopen.closed.val = true
      @wasi.native_close(preopen.fd) |> ignore
    }
  }
}

///|
fn WasiComponentCtx::request_exit(
  self : WasiComponentCtx,
  status : Int32,
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
  offset : Ref[Int32]
  native_fd : Int32?
  file_position : Ref[Int64]?
  owns_fd : Bool
  closed : Ref[Bool]
}

///|
priv struct OutputStreamState {
  write : (Bytes) -> Bool
  native_fd : Int32?
  file_position : Ref[Int64]?
  append : Bool
  owns_fd : Bool
  permit : Ref[Int64]
  pending : Ref[(Bytes, Int32)?]
  failure : Ref[String?]
  closed : Ref[Bool]
}

///|
priv enum PollSource {
  Deadline(Int64)
  Input(Int32)
  Output(Int32)
  Socket(Int32, Int32)
  OwnedSocket(Int32, Int32)
}

///|
priv enum TcpSocketPhase {
  Unbound
  BindStarted
  Bound
  ConnectStarted
  Connected
  ListenStarted
  Listening
  Closed
} derive(Eq)

///|
priv struct TcpSocketState {
  fd : Int32
  family : Int32
  phase : Ref[TcpSocketPhase]
  backlog : Ref[Int32]
  send_taken : Ref[Bool]
  receive_taken : Ref[Bool]
  closed : Ref[Bool]
}

///|
priv enum UdpSocketPhase {
  UdpUnbound
  UdpBindStarted
  UdpBound
  UdpClosed
} derive(Eq)

///|
priv struct UdpSocketState {
  fd : Int32
  family : Int32
  phase : Ref[UdpSocketPhase]
  generation : Ref[Int32]
  remote : Ref[@wasi.NativeSocketAddress?]
  policy : Ref[WasiNetworkPolicy]
  closed : Ref[Bool]
}

///|
priv struct IncomingDatagramStreamState {
  fd : Int32
  generation : Ref[Int32]
  expected_generation : Int32
  closed : Ref[Bool]
}

///|
priv struct OutgoingDatagramStreamState {
  fd : Int32
  family : Int32
  generation : Ref[Int32]
  expected_generation : Int32
  remote : @wasi.NativeSocketAddress?
  permit : Ref[Int64]
  closed : Ref[Bool]
}

///|
priv struct ResolveAddressStreamState {
  resolver : @wasi.NativeResolverHandle
  poll_fd : Int32
  policy : WasiNetworkPolicy
  closed : Ref[Bool]
}

///|
let descriptor_read : Int32 = 0x01

///|
let descriptor_write : Int32 = 0x02

///|
let descriptor_mutate_directory : Int32 = 0x20

///|
let descriptor_all : Int32 = descriptor_read |
  descriptor_write |
  descriptor_mutate_directory

///|
priv struct PreopenState {
  fd : Int32
  guest_path : String
  flags : Int32
  closed : Ref[Bool]
}

///|
priv struct DescriptorState {
  fd : Int32
  flags : Int32
  file_type : Int32
  closed : Ref[Bool]
}

///|
priv struct DirectoryEntryState {
  name : String
  file_type : Int32
}

///|
priv struct DirectoryEntryStreamState {
  entries : Array[DirectoryEntryState]
  index : Ref[Int32]
}

///|
priv enum WasiHostResource {
  IoError(String, Int32?)
  InputStream(InputStreamState)
  OutputStream(OutputStreamState)
  Pollable(PollSource)
  Descriptor(DescriptorState)
  DirectoryEntryStream(DirectoryEntryStreamState)
  Network(WasiNetworkPolicy)
  TcpSocket(TcpSocketState)
  UdpSocket(UdpSocketState)
  IncomingDatagramStream(IncomingDatagramStreamState)
  OutgoingDatagramStream(OutgoingDatagramStreamState)
  ResolveAddressStream(ResolveAddressStreamState)
}

///|
priv struct WasiHostResourceEntry {
  resource : WasiHostResource
  references : Ref[Int32]
}

///|
fn new_resource_entry(resource : WasiHostResource) -> WasiHostResourceEntry {
  { resource, references: Ref(1), }
}

///|
fn WasiComponentCtx::insert_resource(
  self : WasiComponentCtx,
  resource : WasiHostResource,
) -> Int32 {
  let rep = self.next_resource_rep.val
  self.next_resource_rep.val = rep + 1
  self.resources.set(rep, new_resource_entry(resource))
  rep
}

///|
fn WasiComponentCtx::get_resource(
  self : WasiComponentCtx,
  rep : Int32,
) -> WasiHostResource? {
  match self.resources.get(rep) {
    Some(entry) => Some(entry.resource)
    None => None
  }
}

///|
fn WasiComponentCtx::clone_resource(
  self : WasiComponentCtx,
  rep : Int32,
) -> Int32 raise @runtime_impl.ComponentRuntimeError {
  match self.resources.get(rep) {
    Some(entry) => {
      entry.references.val = entry.references.val + 1
      let cloned_rep = self.next_resource_rep.val
      self.next_resource_rep.val = cloned_rep + 1
      self.resources.set(cloned_rep, entry)
      cloned_rep
    }
    None => raise HostCallError("WASI host resource is not live")
  }
}

///|
fn WasiComponentCtx::drop_resource(
  self : WasiComponentCtx,
  rep : Int32,
) -> Unit {
  guard self.resources.get(rep) is Some(entry) else { return }
  self.resources.remove(rep)
  entry.references.val = entry.references.val - 1
  if entry.references.val > 0 {
    return
  }
  match entry.resource {
    InputStream(state) =>
      if !state.closed.val {
        state.closed.val = true
        if state.owns_fd {
          match state.native_fd {
            Some(fd) => @wasi.native_close(fd) |> ignore
            None => ()
          }
        }
      }
    OutputStream(state) =>
      if !state.closed.val {
        state.closed.val = true
        state.pending.val = None
        if state.owns_fd {
          match state.native_fd {
            Some(fd) => @wasi.native_close(fd) |> ignore
            None => ()
          }
        }
      }
    Descriptor(state) =>
      if !state.closed.val {
        state.closed.val = true
        @wasi.native_close(state.fd) |> ignore
      }
    TcpSocket(state) =>
      if !state.closed.val {
        state.closed.val = true
        state.phase.val = Closed
        @wasi.native_close(state.fd) |> ignore
      }
    UdpSocket(state) =>
      if !state.closed.val {
        state.closed.val = true
        state.phase.val = UdpClosed
        state.generation.val = state.generation.val + 1
        @wasi.native_close(state.fd) |> ignore
      }
    IncomingDatagramStream(state) =>
      if !state.closed.val {
        state.closed.val = true
        @wasi.native_close(state.fd) |> ignore
      }
    OutgoingDatagramStream(state) =>
      if !state.closed.val {
        state.closed.val = true
        @wasi.native_close(state.fd) |> ignore
      }
    ResolveAddressStream(state) =>
      if !state.closed.val {
        state.closed.val = true
        @wasi.native_resolver_drop(state.resolver)
      }
    Pollable(OwnedSocket(fd, _events)) => @wasi.native_close(fd) |> ignore
    _ => ()
  }
}

///|
fn WasiComponentCtx::register_deadline(
  self : WasiComponentCtx,
  deadline : Int64,
) -> WasiAsyncOperation raise @runtime_impl.ComponentRuntimeError {
  if self.closed.val {
    raise HostCallError("WASI component context is closed")
  }
  guard self.native_reactor is Some(reactor) else {
    raise HostCallError("native async reactor is unavailable")
  }
  let now = @wasi.native_clock_gettime_monotonic()
  if now < 0L {
    raise HostCallError("monotonic clock is unavailable")
  }
  let registration = reactor.register_timer(
    if deadline <= now {
      1L
    } else {
      deadline - now
    },
  ) catch {
    error => raise HostCallError("cannot register native timer: \{error}")
  }
  { registration, }
}

///|
fn WasiComponentCtx::async_operation_ready(
  _self : WasiComponentCtx,
  operation : WasiAsyncOperation,
) -> Bool {
  operation.registration.is_ready()
}

///|
fn WasiComponentCtx::cancel_async_operation(
  _self : WasiComponentCtx,
  operation : WasiAsyncOperation,
) -> Unit {
  operation.registration.cancel()
}

///|
fn WasiComponentCtx::register_async_fd(
  self : WasiComponentCtx,
  fd : Int32,
  events : Int32,
) -> WasiAsyncOperation raise @runtime_impl.ComponentRuntimeError {
  if self.closed.val {
    raise HostCallError("WASI component context is closed")
  }
  guard self.native_reactor is Some(reactor) else {
    raise HostCallError("native async reactor is unavailable")
  }
  let writable = if (events & 0x01) != 0 {
    false
  } else if (events & 0x04) != 0 {
    true
  } else {
    raise HostCallError("unsupported native descriptor event mask")
  }
  let registration = try {
    if writable {
      reactor.register_write(fd)
    } else {
      reactor.register_read(fd)
    }
  } catch {
    error => raise HostCallError("cannot register native descriptor: \{error}")
  }
  { registration, }
}

///|
fn WasiComponentCtx::wait_for_async_event(
  self : WasiComponentCtx,
) -> Bool raise @runtime_impl.ComponentRuntimeError {
  if self.closed.val {
    return false
  }
  guard self.native_reactor is Some(reactor) else {
    raise HostCallError("native async reactor is unavailable")
  }
  while reactor.has_pending() {
    let completed = reactor.wait(None) catch {
      error => raise HostCallError("native async reactor wait failed: \{error}")
    }
    if completed > 0 {
      return true
    }
  }
  false
}

///|
fn WasiComponentCtx::poll_async_event(
  self : WasiComponentCtx,
) -> Bool raise @runtime_impl.ComponentRuntimeError {
  if self.closed.val {
    return false
  }
  guard self.native_reactor is Some(reactor) else {
    raise HostCallError("native async reactor is unavailable")
  }
  let completed = reactor.wait(Some(0L)) catch {
    error => raise HostCallError("native async reactor poll failed: \{error}")
  }
  completed > 0
}
