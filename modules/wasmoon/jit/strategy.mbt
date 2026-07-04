/// JIT strategy compatibility aliases.
///
/// The implementation lives in `Milky2018/wasmoon_jit`; this package keeps the
/// historical `Milky2018/wasmoon/jit` API while Wasmoon call sites migrate.

///|
pub type CompilationMode = @wasmoon_jit.CompilationMode

///|
pub type CompilationRequest = @wasmoon_jit.CompilationRequest

///|
pub type CompilationQueue = @wasmoon_jit.CompilationQueue

///|
pub type TieredConfig = @wasmoon_jit.TieredConfig

///|
pub type CompilationDecision = @wasmoon_jit.CompilationDecision

///|
pub type CompilationStrategy = @wasmoon_jit.CompilationStrategy
