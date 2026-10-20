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
pub extern "c" fn NativeTableHandle::size(self : NativeTableHandle) -> Int32 = "wasmoon_native_table_size"

///|
pub impl Debug for NativeTableHandle with fn to_repr(_self) {
  Repr::literal("NativeTableHandle")
}

///|
pub extend NativeTableHandle with Debug::{to_repr}

///|
#borrow(self, reservation)
pub extern "c" fn NativeTableHandle::bind_reservation(
  self : NativeTableHandle,
  reservation : Reservation,
) -> Bool = "wasmoon_table_bind_reservation"

///|
#borrow(self)
pub extern "c" fn NativeTableHandle::grow(
  self : NativeTableHandle,
  delta : Int64,
) -> Int64 = "wasmoon_table_grow_owned"

///|
/// Mutation revision of the shared descriptor, including guest writes and growth.
#borrow(self)
pub extern "c" fn NativeTableHandle::revision(
  self : NativeTableHandle,
) -> Int64 = "wasmoon_native_table_revision"
