///|
/// Return the decoded module if Core-valid, or None for validation rejection.
/// Syntax failures and unsupported validation mechanisms raise instead.
pub fn validate_module_source(
  source : @wat.WastModuleSource,
  bulk_memory~ : Bool,
  stack_switching~ : Bool,
) -> @types.Module? raise WastRunnerError {
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
    _ => None
  } noraise {
    _ => Some(module_)
  }
}
