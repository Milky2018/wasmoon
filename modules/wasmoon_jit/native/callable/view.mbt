///|
/// Opaque native view retaining MoonBit arrays for direct JIT helper access.
pub type NativeCallableView

///|
extern "c" fn new_view() -> NativeCallableView = "wasmoon_callable_view_new"

///|
#borrow(view, parents, addresses, identities)
extern "c" fn publish(
  view : NativeCallableView,
  parents : FixedArray[Int32],
  type_count : Int32,
  addresses : FixedArray[Int64],
  identities : FixedArray[Int32],
  entry_count : Int32,
) -> Unit = "wasmoon_callable_view_publish"
