///|
pub extend WitBindingError with Debug::{to_repr}

///|
pub extend WitBindingError with Eq::{not_equal, equal}

///|
pub extend WitBindingError with Show::{to_string, output}

///|
pub extend WitError with Show::{output}
