///|
pub using @callable {type NativeCallableRegistry}

///|
#borrow(context, output)
extern "c" fn write_bound_entry_code(
  context : JITContext,
  target : Int64,
  output : FixedArray[Byte],
) -> Int32 = "wasmoon_jit_write_bound_entry_code"

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
  let code : Array[Int32] = []
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
/// One immutable installation of leaf context bindings. Entry addresses are
/// valid only while this owner is retained and unreleased. The caller must
/// finish every invocation before release, as with a standalone NativeCallable.
pub struct NativeCallableBatch {
  priv context : NativeJITContext
  priv entry : InstalledTrampoline?
  priv offsets : FixedArray[Int32]
}

///|
/// Preserve the standalone binding ABI while publishing all entries together.
/// No executable page is shared with another batch or modified after publication.
/// Target code is borrowed and must outlive these bindings, as with bind_callable.
pub fn NativeJITContext::bind_callables(
  self : NativeJITContext,
  targets : Array[Int64],
) -> NativeCallableBatch raise JitInstallError {
  let offsets = FixedArray::make(targets.length(), -1)
  let bytes = FixedArray::make(40, b'\x00')
  let code : Array[Int32] = []
  for index, target in targets {
    if target == 0L {
      continue
    }
    let size = write_bound_entry_code(self.handle, target, bytes)
    if size <= 0 {
      raise TrampolineAllocationFailed(code_size=0)
    }
    let aligned = (code.length().to_int64() + 15L) / 16L * 16L
    if aligned + size.to_int64() > 2147483647L {
      raise TrampolineAllocationFailed(code_size=0)
    }
    while code.length().to_int64() < aligned {
      code.push(0)
    }
    offsets[index] = code.length()
    for i in 0..<size {
      code.push(bytes[i].to_int())
    }
  }
  let entry = if code.is_empty() {
    None
  } else {
    Some(JitCodeInstaller::new(fn(_) { None }).install_trampoline(code))
  }
  { context: self, entry, offsets, }
}

///|
/// Return zero for an absent/out-of-range entry or a released installation.
pub fn NativeCallableBatch::entry_address(
  self : NativeCallableBatch,
  index : Int32,
) -> Int64 {
  self.context |> ignore
  guard index >= 0 &&
    index < self.offsets.length() &&
    self.offsets[index] >= 0 &&
    self.entry is Some(entry) else {
    return 0L
  }
  let base = entry.entry_address()
  if base == 0L {
    0L
  } else {
    base + self.offsets[index].to_int64()
  }
}

///|
/// Release the complete installation once all of its callers are finished.
pub fn NativeCallableBatch::release(self : NativeCallableBatch) -> Unit {
  if self.entry is Some(entry) {
    entry.release()
  }
}

///|
/// Bind shared Store identities with this instance's local type and tag maps.
pub fn NativeJITContext::bind_callable_registry(
  self : NativeJITContext,
  registry : NativeCallableRegistry,
  local_types : Array[Int32],
  tags : Array[Int32],
  functions~ : Array[Int32] = [],
) -> Unit {
  let locals = FixedArray::make(local_types.length(), 0)
  for i, value in local_types {
    locals[i] = value
  }
  let tag_addresses = FixedArray::make(tags.length(), 0)
  for i, address in tags {
    tag_addresses[i] = address
  }
  self.handle.bind_callable_registry(
    registry,
    locals,
    tag_addresses,
    functions=FixedArray::makei(functions.length(), i => functions[i]),
  )
}

///|
/// Install an independent callable view for a standalone context.
pub fn NativeJITContext::set_callable_types(
  self : NativeJITContext,
  local_types : Array[Int32],
  parents : Array[Int32],
  entries : Array[(Int64, Int32)],
  tags : Array[Int32],
) -> Unit {
  let registry = NativeCallableRegistry::new()
  if !registry.replace(parents, entries) {
    abort("failed to allocate native callable registry")
  }
  self.bind_callable_registry(registry, local_types, tags)
}
