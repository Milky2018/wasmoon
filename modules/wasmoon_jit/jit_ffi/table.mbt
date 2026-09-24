///|
/// Managed shared table identity. Native context bindings retain this object.
pub type NativeTableHandle

///|
pub extern "c" fn NativeTableHandle::null() -> NativeTableHandle = "wasmoon_native_table_empty"

///|
#borrow(self)
pub extern "c" fn NativeTableHandle::is_null(self : NativeTableHandle) -> Bool = "wasmoon_native_table_is_empty"

///|
#borrow(self)
pub extern "c" fn NativeTableHandle::size(self : NativeTableHandle) -> Int = "wasmoon_native_table_size"

///|
pub impl Debug for NativeTableHandle with fn to_repr(_self) {
  Repr::literal("NativeTableHandle")
}

///|
pub extend NativeTableHandle with Debug::{to_repr}
