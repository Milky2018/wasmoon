///|
/// Public WAT parser API compatibility layer.
///
/// Implementation lives in `Milky2018/wasmoon/wat/parser_impl`.

///|
pub using @parser_impl {
  type WatError,
  type SourceLoc,
  type WastCommand,
  type WastModuleSource,
  type WastAction,
  type WastValue,
  type WastLaneValue,
  type WastScript,
}

///|
pub fn parse(input : String) -> @types.Module raise WatError {
  @parser_impl.parse(input)
}

///|
pub fn parse_wast(input : String) -> WastScript raise WatError {
  @parser_impl.parse_wast(input)
}

///|
pub fn format_wat_error(err : WatError, source : String) -> String {
  @parser_impl.format_wat_error(err, source)
}
