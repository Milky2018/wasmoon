///|
pub extend JITCoreCallError with Debug::{to_repr}

///|
pub extend JITCoreCallError with Eq::{not_equal, equal}

///|
pub extend JITCoreCallError with Show::{to_string, output}

///|
pub extend WastRunnerError with Show::{to_string, output}
