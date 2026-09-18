///|
pub extend NativeExecutionState with Debug::{to_repr}

///|
pub extend NativeExecutionStateError with Debug::{to_repr}

///|
pub extend NativeExecutionStateError with Eq::{not_equal, equal}

///|
pub extend NativeExecutionStateError with Show::{to_string, output}

///|
pub extend NativeInvocationHandle with Debug::{to_repr}

///|
pub extend NativeInvocationPhase with Debug::{to_repr}

///|
pub extend NativeInvocationPhase with Eq::{not_equal, equal}
