///|
pub extend CanonSuspend with Debug::{to_repr}

///|
pub extend CanonSuspend with Eq::{not_equal, equal}

///|
pub extend ComponentInstanceEntryState with Debug::{to_repr}

///|
pub extend ComponentRuntimeError with Debug::{to_repr}

///|
pub extend ComponentRuntimeError with Eq::{not_equal, equal}

///|
pub extend ComponentRuntimeError with Show::{to_string, output}

///|
pub extend CoreBackendPolicy with Debug::{to_repr}

///|
pub extend CoreBackendPolicy with Eq::{not_equal, equal}

///|
pub extend CoreCallStyle with Debug::{to_repr}

///|
pub extend CoreCallStyle with Eq::{not_equal, equal}

///|
pub extend CoreContinuation with Debug::{to_repr}

///|
pub extend CoreExecutionEngine with Debug::{to_repr}

///|
pub extend CoreExecutionOutcome with Debug::{to_repr}

///|
pub extend CoreExecutionRequest with Debug::{to_repr}

///|
pub extend CoreExecutionRequest with Eq::{not_equal, equal}

///|
pub extend CoreFuncRef with Debug::{to_repr}

///|
pub extend CoreSuspension with Debug::{to_repr}

///|
pub extend CoreSuspension with Eq::{not_equal, equal}

///|
pub extend CoreSuspensionPolicy with Debug::{to_repr}

///|
pub extend CoreSuspensionPolicy with Eq::{not_equal, equal}
