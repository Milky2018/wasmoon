///|
pub using @callable {type NativeCallableRegistry}

///|
#borrow(context, output)
extern "c" fn write_bound_entry_code(
  context : JITContext,
  target : Int64,
  output : FixedArray[Byte],
) -> Int = "wasmoon_jit_write_bound_entry_code"

///|
/// A native entry bound to the instance environment that owns its code.
/// The leaf trampoline preserves all guest arguments and tail-call stack usage.
pub struct NativeCallable {
  context : NativeJITContext
  entry : InstalledTrampoline
}

///|
pub fn NativeJITContext::bind_callable(
  self : NativeJITContext,
  target : Int64,
) -> NativeCallable raise JitInstallError {
  let bytes = FixedArray::make(40, b'\x00')
  let size = write_bound_entry_code(self.handle, target, bytes)
  if size <= 0 {
    raise TrampolineAllocationFailed(code_size=0)
  }
  let code : Array[Int] = []
  for i in 0..<size {
    code.push(bytes[i].to_int())
  }
  let entry = JitCodeInstaller::new(fn(_) { None }).install_trampoline(code)
  { context: self, entry, }
}

///|
pub fn NativeCallable::entry_address(self : NativeCallable) -> Int64 {
  self.context |> ignore
  self.entry.entry_address()
}

///|
pub fn NativeCallable::release(self : NativeCallable) -> Unit {
  self.entry.release()
}

///|
#borrow(context, registry, local_types, tags)
extern "c" fn bind_callable_registry(
  context : JITContext,
  registry : NativeCallableRegistry,
  local_types : FixedArray[Int],
  local_count : Int,
  tags : FixedArray[Int],
  tag_count : Int,
) -> Bool = "wasmoon_jit_bind_callable_registry"

///|
/// Bind shared Store identities with this instance's local type and tag maps.
pub fn NativeJITContext::bind_callable_registry(
  self : NativeJITContext,
  registry : NativeCallableRegistry,
  local_types : Array[Int],
  tags : Array[Int],
) -> Unit {
  let locals = FixedArray::make(local_types.length(), 0)
  for i, value in local_types {
    locals[i] = value
  }
  let tag_addresses = FixedArray::make(tags.length(), 0)
  for i, address in tags {
    tag_addresses[i] = address
  }
  if !bind_callable_registry(
      self.handle,
      registry,
      locals,
      locals.length(),
      tag_addresses,
      tag_addresses.length(),
    ) {
    abort("failed to allocate native callable instance mappings")
  }
}

///|
/// Install an independent callable view for a standalone context.
pub fn NativeJITContext::set_callable_types(
  self : NativeJITContext,
  local_types : Array[Int],
  parents : Array[Int],
  entries : Array[(Int64, Int)],
  tags : Array[Int],
) -> Unit {
  let registry = NativeCallableRegistry::new()
  if !registry.replace(parents, entries) {
    abort("failed to allocate native callable registry")
  }
  self.bind_callable_registry(registry, local_types, tags)
}
