// WAST (WebAssembly Test Script) Parser
// Re-exports the WAST parser from the wat package

///|
pub using @wat {
  type WastScript,
  type WastCommand,
  type WastModuleSource,
  type WastAction,
  type WastValue,
  type WatError,
}

///|
pub fn parse(input : String) -> WastScript raise @wat.WatError {
  @wat.parse_wast(input)
}
