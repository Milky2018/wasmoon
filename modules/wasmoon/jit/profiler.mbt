/// JIT profiler compatibility aliases.
///
/// The implementation lives in `Milky2018/wasmoon_jit`; this package keeps the
/// historical `Milky2018/wasmoon/jit` API while Wasmoon call sites migrate.

///|
pub type CallCounter = @wasmoon_jit.CallCounter

///|
pub type HotThreshold = @wasmoon_jit.HotThreshold

///|
pub type FunctionTemperature = @wasmoon_jit.FunctionTemperature

///|
pub type Profiler = @wasmoon_jit.Profiler

///|
pub fn get_temperature(
  count : Int,
  threshold : HotThreshold,
) -> FunctionTemperature {
  @wasmoon_jit.get_temperature(count, threshold)
}
