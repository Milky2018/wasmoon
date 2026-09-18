///|
/// Preserve the WAT facade while the parser owns parsing and script types.
pub using @parser {
  type SourceLoc,
  type WatError,
  type WastAction,
  type WastCommand,
  type WastLaneValue,
  type WastModuleSource,
  type WastScript,
  type WastValue,
  format_wat_error,
  parse,
  parse_wast,
}
