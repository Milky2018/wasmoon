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
#borrow(context, local_types, parents, entries, tags)
extern "c" fn set_callable_types(
  context : JITContext,
  local_types : FixedArray[Int],
  local_count : Int,
  parents : FixedArray[Int],
  type_count : Int,
  entries : FixedArray[Int64],
  entry_count : Int,
  tags : FixedArray[Int],
  tag_count : Int,
) -> Unit = "wasmoon_jit_set_callable_types"

///|
pub fn NativeJITContext::set_callable_types(
  self : NativeJITContext,
  local_types : Array[Int],
  parents : Array[Int],
  entries : Array[(Int64, Int)],
  tags : Array[Int],
) -> Unit {
  let locals = FixedArray::make(local_types.length(), 0)
  for i, value in local_types {
    locals[i] = value
  }
  let supers = FixedArray::make(parents.length(), 0)
  for i, value in parents {
    supers[i] = value
  }
  let functions = FixedArray::make(entries.length() * 2, 0L)
  for i, entry in entries {
    functions[i * 2] = entry.0
    functions[i * 2 + 1] = entry.1.to_int64()
  }
  let tag_addresses = FixedArray::make(tags.length(), 0)
  for i, address in tags {
    tag_addresses[i] = address
  }
  set_callable_types(
    self.handle,
    locals,
    locals.length(),
    supers,
    supers.length(),
    functions,
    entries.length(),
    tag_addresses,
    tag_addresses.length(),
  )
}
