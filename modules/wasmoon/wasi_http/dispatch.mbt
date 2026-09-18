///|
fn HttpHost::add_dispatch(
  self : HttpHost,
  interface : String,
  function : String,
  dispatch : (Array[@runtime_impl.ComponentValue], @runtime_impl.ResourceTable) -> @runtime_impl.HostFuture raise @runtime_impl.ComponentRuntimeError,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let contract = "wasi:http@0.3.0/" + interface
  let name = "wasi:http/" + interface + "@0.3.0"
  let builder = self.linker.host_instance_builder(name, self.runtime)
  builder.set_type_space(self.types)
  for entry in wasi_http_exported_types(contract) {
    builder.add_type(entry.0, entry.1)
  }
  builder.add_async_func(
    function,
    wasi_http_func_type(contract, function).unwrap(),
    dispatch,
  )
  self.linker.add_instance(name, builder.finish())
}

///|
/// Install outgoing request dispatch. The same request/response resources are
/// shared with `handler`, allowing direct middleware composition.
pub fn HttpHost::add_client(
  self : HttpHost,
  dispatch : (Array[@runtime_impl.ComponentValue], @runtime_impl.ResourceTable) -> @runtime_impl.HostFuture raise @runtime_impl.ComponentRuntimeError,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  self.add_dispatch("client", "send", dispatch)
}

///|
/// Install the downstream handler imported by the middleware world.
pub fn HttpHost::add_handler(
  self : HttpHost,
  dispatch : (Array[@runtime_impl.ComponentValue], @runtime_impl.ResourceTable) -> @runtime_impl.HostFuture raise @runtime_impl.ComponentRuntimeError,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  self.add_dispatch("handler", "handle", dispatch)
}

///|
/// Link the next component in a middleware chain in the same linker. Instantiate
/// the downstream service first, then register each middleware from inside out.
pub fn HttpHost::add_downstream(
  self : HttpHost,
  instance : @runtime_impl.ComponentInstance,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  guard instance.exports.get("wasi:http/handler@0.3.0")
    is Some(Instance(handler)) else {
    raise HostCallError("downstream does not export wasi:http/handler@0.3.0")
  }
  self.linker.add_instance("wasi:http/handler@0.3.0", handler)
}
