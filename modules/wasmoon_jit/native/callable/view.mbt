///|
/// Opaque native view retaining MoonBit arrays for direct JIT helper access.
pub type NativeCallableView

///|
extern "c" fn new_view() -> NativeCallableView = "wasmoon_callable_view_new"

///|
#borrow(view, parents, addresses, identities)
extern "c" fn publish(
  view : NativeCallableView,
  parents : FixedArray[Int],
  type_count : Int,
  addresses : FixedArray[Int64],
  identities : FixedArray[Int],
  entry_count : Int,
) -> Unit = "wasmoon_callable_view_publish"
