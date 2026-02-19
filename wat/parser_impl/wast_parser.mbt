// ============================================================================
// WAST (WebAssembly Test Script) Parsing
// ============================================================================

///|
/// WAST command types
pub enum WastCommand {
  Module(@types.Module, String?)
  ModuleDefinition(@types.Module, String?)
  ModuleInstance(String?, String) // (instance_name, definition_name)
  ModuleQuote(Array[String])
  ModuleBinaryFailed(String)
  AssertReturn(WastAction, Array[WastValue])
  AssertTrap(WastAction, String)
  AssertException(WastAction) // Exception should be thrown
  AssertModuleTrap(WastModuleSource, String)
  AssertExhaustion(WastAction, String)
  AssertInvalid(WastModuleSource, String)
  AssertMalformed(WastModuleSource, String)
  AssertUnlinkable(WastModuleSource, String)
  Register(String, String?)
  Action(WastAction)
} derive(Show)

///|
/// Module source for assert_invalid/malformed
pub enum WastModuleSource {
  Binary(Bytes)
  Quote(Array[String])
  Inline(@types.Module)
  FailedToParse(String)
} derive(Show)

///|
/// WAST action (invoke or get)
pub enum WastAction {
  Invoke(String?, String, Array[WastValue])
  Get(String?, String)
} derive(Show)

///|
/// WAST value (typed constant)
pub enum WastValue {
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
  V128(Bytes) // SIMD 128-bit vector (16 bytes)
  F32CanonicalNan
  F32ArithmeticNan
  F64CanonicalNan
  F64ArithmeticNan
  // SIMD lane patterns for NaN matching
  V128Pattern(Array[WastLaneValue]) // For lane-by-lane comparison with NaN patterns
  RefNull(String)
  RefExtern(Int)
  RefExternAny // (ref.extern) without number - matches any non-null externref
  RefHost(Int) // (ref.host <idx>) - host reference for testing
  RefFunc
  // GC reference types
  RefArray // (ref.array) - any array reference
  RefStruct // (ref.struct) - any struct reference
  RefEq // (ref.eq) - any eq reference
  RefI31 // (ref.i31) - any i31 reference
  RefAny // (ref.any) - any reference
  // Relaxed SIMD: multiple valid results
  Either(Array[WastValue]) // (either v1 v2 ...) - any of the alternatives is valid
} derive(Show)

///|
/// Lane value for V128 pattern matching
pub enum WastLaneValue {
  F32(Float)
  F64(Double)
  F32CanonicalNan
  F32ArithmeticNan
  F64CanonicalNan
  F64ArithmeticNan
} derive(Show)

///|
/// WAST script (collection of commands with line numbers)
pub struct WastScript {
  commands : Array[(WastCommand, Int)]
}
