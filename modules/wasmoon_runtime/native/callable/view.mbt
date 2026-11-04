///|
/// Opaque native view retaining MoonBit arrays for direct JIT helper access.
pub type NativeCallableView

///|
extern "c" fn new_view() -> NativeCallableView = "wasmoon_callable_view_new"

///|
#borrow(view, parents, addresses, identities, store_positions)
extern "c" fn publish(
  view : NativeCallableView,
  parents : FixedArray[Int32],
  type_count : Int32,
  addresses : FixedArray[Int64],
  identities : FixedArray[Int32],
  entry_count : Int32,
  store_origin : Int32,
  store_positions : FixedArray[Int32],
) -> Unit = "wasmoon_callable_view_publish"

///|
#borrow(view, stores, pointers, references, reference_stores, store_positions)
extern "c" fn publish_functions(
  view : NativeCallableView,
  stores : FixedArray[Int32],
  pointers : FixedArray[Int64],
  count : Int32,
  references : FixedArray[Int64],
  reference_stores : FixedArray[Int32],
  reference_count : Int32,
  store_origin : Int32,
  store_positions : FixedArray[Int32],
) -> Unit = "wasmoon_callable_view_publish_functions"
