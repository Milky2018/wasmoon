///|
/// Shared Store-local callable identities. Owns metadata, never executable code.
pub type NativeCallableRegistry

///|
#deprecated
pub extend NativeCallableRegistry with Debug::{to_repr}

///|
pub impl Debug for NativeCallableRegistry with fn to_repr(_self) {
  Repr::literal("NativeCallableRegistry")
}

///|
pub extern "c" fn NativeCallableRegistry::new() -> NativeCallableRegistry = "wasmoon_callable_registry_new"

///|
#borrow(self)
pub extern "c" fn NativeCallableRegistry::clear(
  self : NativeCallableRegistry,
) -> Unit = "wasmoon_callable_registry_clear"

///|
#borrow(registry, parents, entries)
extern "c" fn replace_native(
  registry : NativeCallableRegistry,
  parents : FixedArray[Int],
  type_count : Int,
  entries : FixedArray[Int64],
  entry_count : Int,
) -> Bool = "wasmoon_callable_registry_replace"

///|
/// Replace the shared view atomically with respect to allocation failure.
/// Call on the Store's execution thread, outside concurrent guest execution.
/// Returns false on native allocation failure, preserving the previous view.
pub fn NativeCallableRegistry::replace(
  self : NativeCallableRegistry,
  parents : Array[Int],
  entries : Array[(Int64, Int)],
) -> Bool {
  let supers = FixedArray::make(parents.length(), 0)
  for i, value in parents {
    supers[i] = value
  }
  let functions = FixedArray::make(entries.length() * 2, 0L)
  for i, entry in entries {
    functions[i * 2] = entry.0
    functions[i * 2 + 1] = entry.1.to_int64()
  }
  replace_native(self, supers, supers.length(), functions, entries.length())
}
