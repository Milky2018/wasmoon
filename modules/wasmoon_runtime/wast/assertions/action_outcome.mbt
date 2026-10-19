///|
/// Decide assertions from an action already executed by either runner.
/// Return-value comparison is supplied by the runner after resolving references.
pub fn check_action_outcome(
  command : @wat.WastCommand,
  action : @wat.WastAction,
  outcome : Result[Array[@types.Value], WastRunnerError],
  return_failure : String?,
) -> (String, String?) {
  let description = format_action(action)
  match command {
    AssertReturn(_, _) =>
      (
        "assert_return \{description}",
        match outcome {
          Ok(_) => return_failure
          Err(error) => Some("invoke failed: \{error}")
        },
      )
    AssertTrap(_, expected) =>
      (
        "assert_trap failed",
        match outcome {
          Err(GuestTrap(message)) | Err(GuestExhaustion(message)) =>
            if wast_trap_message_matches(message, expected) {
              None
            } else {
              Some("expected '\{expected}', got trap '\{message}'")
            }
          Err(error) => Some("expected trap '\{expected}', got \{error}")
          Ok(_) => Some("expected trap '\{expected}', but the action returned")
        },
      )
    AssertSuspension(_, _) =>
      (
        "assert_suspension \{description}",
        match outcome {
          Err(GuestSuspension) => None
          Err(error) => Some("expected suspension, got \{error}")
          Ok(_) => Some("expected suspension, but the action returned")
        },
      )
    AssertException(_) =>
      (
        "assert_exception \{description}",
        match outcome {
          Err(GuestException) => None
          Err(error) => Some("expected Wasm exception, got \{error}")
          Ok(values) =>
            Some(
              "expected exception but none thrown (returned \{Repr(values)})",
            )
        },
      )
    AssertExhaustion(_, expected) =>
      (
        "assert_exhaustion \{description}",
        match outcome {
          Err(GuestExhaustion(message)) =>
            if wast_trap_message_matches(message, expected) {
              None
            } else {
              Some("expected '\{expected}', got exhaustion '\{message}'")
            }
          Err(error) => Some("expected exhaustion '\{expected}', got \{error}")
          Ok(_) =>
            Some("expected exhaustion '\{expected}', but the action returned")
        },
      )
    Action(_) =>
      (
        "action \{description} failed",
        match outcome {
          Ok(_) => None
          Err(error) => Some(error.to_string())
        },
      )
    _ => abort("action completion requires an action directive")
  }
}

///|
pub fn format_action(action : @wat.WastAction) -> String {
  match action {
    Invoke(module_name, func_name, _args) =>
      match module_name {
        Some(m) => "(\{m}.\{func_name})"
        None => "(\{func_name})"
      }
    Get(module_name, global_name) =>
      match module_name {
        Some(m) => "(get \{m}.\{global_name})"
        None => "(get \{global_name})"
      }
  }
}
