///|
extern "c" fn c_cpu_clock(thread : Bool, resolution : Bool) -> Int64 = "wasmoon_wasi_cpu_clock"

///|
extern "c" fn c_yield() -> Int = "wasmoon_wasi_yield"

///|
extern "c" fn c_raise_signal(signal : Int) -> Int = "wasmoon_wasi_raise_signal"

///|
/// Deliver a P1 signal to the hosting process. This can terminate the entire
/// embedder. Only call from an explicitly authorized host signal policy.
/// Unsupported native signals return NOTSUP; signal zero has no effect.
pub fn raise_host_signal(signal : Int) -> Int {
  if c_raise_signal(signal) == 0 {
    0
  } else {
    native_last_errno_to_wasi()
  }
}

///|
/// Install an explicit host policy. The handler receives a valid P1 signal tag
/// and returns a WASI errno. It may deny a signal, emulate it, or explicitly
/// invoke raise_host_signal. The default context has no signal handler.
pub fn WasiContextBuilder::signal_handler(
  self : WasiContextBuilder,
  handler : (Int) -> Int,
) -> WasiContextBuilder {
  self.signal_handler = Some(handler)
  self
}
