///|
priv struct WasiResourceTypes {
  all : Map[String, @component.TypeDef?]
  error : @component.TypeDef?
  pollable : @component.TypeDef?
  input_stream : @component.TypeDef?
  output_stream : @component.TypeDef?
}

///|
/// One WASI host registration scope for a component linker.
///
/// All interface instances defined through this value share resource type
/// identities and runtime state.
struct WasiComponentHost {
  linker : @runtime_impl.ComponentLinker
  runtime : @runtime_impl.HostRuntimeState
  ctx : WasiComponentCtx
  resource_types : WasiResourceTypes
}

///|
pub fn WasiComponentHost::WasiComponentHost(
  linker : @runtime_impl.ComponentLinker,
  ctx : WasiComponentCtx,
) -> WasiComponentHost {
  let runtime = linker.host_runtime_state()
  runtime.set_event_loop(() => ctx.wait_for_async_event())
  let all : Map[String, @component.TypeDef?] = Map([])
  for name in wasi_preview2_resource_names() {
    all.set(name, linker.new_host_resource_type())
  }
  for name in wasi_preview3_resource_names() {
    if all.get(name) is None {
      all.set(name, linker.new_host_resource_type())
    }
  }
  fn require_resource(name : String) -> @component.TypeDef? {
    match all.get(name) {
      Some(resource) => resource
      None => abort("generated WASI resource contract is incomplete: \{name}")
    }
  }
  {
    linker,
    runtime,
    ctx,
    resource_types: {
      all,
      error: require_resource("wasi:io@0.2.11/error.error"),
      pollable: require_resource("wasi:io@0.2.11/poll.pollable"),
      input_stream: require_resource("wasi:io@0.2.11/streams.input-stream"),
      output_stream: require_resource("wasi:io@0.2.11/streams.output-stream"),
    },
  }
}

///|
fn WasiComponentHost::resolve_resource_type(
  self : WasiComponentHost,
  name : String,
) -> @component.TypeDef? {
  match self.resource_types.all.get(name) {
    Some(resource) => resource
    None => abort("unknown generated WASI resource: \{name}")
  }
}

///|
fn require_contract_func(
  function : @component.FuncType?,
  interface : String,
  name : String,
) -> @component.FuncType raise @runtime_impl.ComponentRuntimeError {
  match function {
    Some(func_type) => func_type
    None =>
      raise HostCallError("missing generated contract for \{interface}#\{name}")
  }
}

///|
fn WasiComponentHost::prepare_preview2_interface(
  self : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
  interface : String,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  builder.set_type_space(
    wasi_preview2_type_space(name => self.resolve_resource_type(name)),
  )
  for exported in wasi_preview2_exported_types(interface) {
    let (name, index) = exported
    builder.add_type(name, index)
  }
}

///|
fn preview2_func(
  interface : String,
  name : String,
) -> @component.FuncType raise @runtime_impl.ComponentRuntimeError {
  require_contract_func(
    wasi_preview2_func_type(interface, name),
    interface,
    name,
  )
}

///|
fn WasiComponentHost::prepare_preview3_interface(
  self : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
  interface : String,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  builder.set_type_space(
    wasi_preview3_type_space(name => self.resolve_resource_type(name)),
  )
  for exported in wasi_preview3_exported_types(interface) {
    let (name, index) = exported
    builder.add_type(name, index)
  }
}

///|
fn preview3_func(
  interface : String,
  name : String,
) -> @component.FuncType raise @runtime_impl.ComponentRuntimeError {
  require_contract_func(
    wasi_preview3_func_type(interface, name),
    interface,
    name,
  )
}

///|
pub fn preview2_wit_sha256() -> String {
  wasi_preview2_wit_sha256
}

///|
pub fn preview3_wit_sha256() -> String {
  wasi_preview3_wit_sha256
}

///|
pub fn WasiComponentHost::runtime(
  self : WasiComponentHost,
) -> @runtime_impl.HostRuntimeState {
  self.runtime
}

///|
pub fn WasiComponentHost::context(self : WasiComponentHost) -> WasiComponentCtx {
  self.ctx
}

///|
pub fn WasiComponentHost::add_preview2_cli_clocks_random(
  self : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_preview2_base_interfaces(self)
  add_preview2_monotonic_clock(self)
}

///|
pub fn WasiComponentHost::add_preview3_cli_clocks_random(
  self : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_preview3_base_interfaces(self)
  add_preview3_monotonic_clock(self)
  add_preview3_stdio(self)
}
