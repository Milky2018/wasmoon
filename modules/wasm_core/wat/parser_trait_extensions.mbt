///|
pub extend SourceLoc with Show::{output}

///|
pub extend WastAction with Debug::{to_repr}

///|
pub extend WastCommand with Debug::{to_repr}

///|
pub extend WastLaneValue with Debug::{to_repr}

///|
pub extend WastModuleSource with Debug::{to_repr}

///|
pub extend WastValue with Debug::{to_repr}

///|
pub extend WastValue with Show::{to_string, output}

///|
pub extend WatError with Show::{output}
