/// DWARF/JIT debug-info compatibility aliases.
///
/// The implementation lives in `Milky2018/wasmoon_jit`; this package keeps the
/// historical `Milky2018/wasmoon/jit` API while Wasmoon call sites migrate.

///|
pub type DWARFBuilder = @wasmoon_jit.DWARFBuilder

///|
pub type FunctionInfo = @wasmoon_jit.FunctionInfo

///|
pub type BacktraceFrame = @wasmoon_jit.BacktraceFrame
