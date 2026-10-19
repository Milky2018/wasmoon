///|
/// An invalid assertion requires a decoded module rejected by Core validation.
/// Host instantiation restrictions cannot establish WebAssembly invalidity.
pub fn module_is_invalid(
  source : @wat.WastModuleSource,
  bulk_memory~ : Bool,
  stack_switching~ : Bool,
) -> Bool raise WastRunnerError {
  let module_ = try {
    match source {
      Binary(bytes) => @parser.parse_module(bytes)
      Quote(parts) => @wat.parse(parts.join(""), implicit_module=true)
      Inline(module_) => module_
      FailedToParse(message) => raise RuntimeError(message)
    }
  } catch {
    error => raise RuntimeError("module parsing failed: \{error}")
  }
  try
    @validator.validate_module(module_, bulk_memory~, stack_switching~)
  catch {
    UnsupportedInstruction(detail) => raise UnsupportedCapability(detail)
    _ => true
  } noraise {
    _ => false
  }
}
