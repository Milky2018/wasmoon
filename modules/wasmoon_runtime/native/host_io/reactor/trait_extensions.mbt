///|
pub extend NativeReactor with Debug::{to_repr}

///|
pub extend NativeReactorError with Debug::{to_repr}

///|
pub extend NativeReactorError with Eq::{not_equal, equal}

///|
pub extend NativeReactorError with Show::{to_string, output}
