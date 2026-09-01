///|
pub extend CompileStage with Show::{output}

///|
pub extend ComponentErrorCode with Debug::{to_repr}

///|
pub extend ComponentErrorCode with Eq::{not_equal, equal}

///|
pub extend ComponentErrorCode with Show::{to_string, output}

///|
pub extend ComponentErrorFormat with Debug::{to_repr}

///|
pub extend ComponentErrorFormat with Eq::{not_equal, equal}

///|
pub extend ComponentErrorFormat with Show::{to_string, output}
