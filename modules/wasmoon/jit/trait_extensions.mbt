///|
pub extend AddressRange with Debug::{to_repr}

///|
pub extend JITCallResult with Debug::{to_repr}

///|
pub extend JITModuleLoadError with Debug::{to_repr}

///|
pub extend JITModuleLoadError with Show::{to_string, output}

///|
pub extend JITTrap with Debug::{to_repr}

///|
pub extend JITTrap with Show::{to_string, output}
