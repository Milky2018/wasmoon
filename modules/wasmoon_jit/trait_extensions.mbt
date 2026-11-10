///|
pub extend GCSetupError with Debug::{to_repr}

///|
pub extend GCSetupError with Show::{to_string, output}

///|
pub extend HostcallImportTrampolineError with Debug::{to_repr}

///|
pub extend HostcallImportTrampolineError with Eq::{not_equal, equal}

///|
pub extend HostcallImportTrampolineError with Show::{to_string, output}

///|
pub extend ImportFunctionResolution with Debug::{to_repr}

///|
pub extend ImportFunctionResolution with Eq::{not_equal, equal}

///|
pub extend JitPipelineDiagnostics with Debug::{to_repr}

///|
pub extend JitPipelineError with Debug::{to_repr}

///|
pub extend JitPipelineError with Show::{to_string, output}

///|
pub extend NativeFiber with Debug::{to_repr}

///|
pub extend NativeFiberError with Debug::{to_repr}

///|
pub extend NativeFiberError with Eq::{not_equal, equal}

///|
pub extend NativeFiberError with Show::{to_string, output}

///|
pub extend NativeFiberEvent with Debug::{to_repr}

///|
pub extend NativeFiberEvent with Eq::{not_equal, equal}

///|
pub extend NativeFiberPhase with Debug::{to_repr}

///|
pub extend NativeFiberPhase with Eq::{not_equal, equal}

///|
pub extend NativeHostcallOutcome with Debug::{to_repr}

///|
pub extend NativeHostcallOutcome with Eq::{not_equal, equal}

///|
pub extend NativeJITContinuationEvent with Debug::{to_repr}

///|
pub extend NativeJITContinuationEvent with Eq::{not_equal, equal}

///|
pub extend NativeTarget with Debug::{to_repr}

///|
pub extend NativeTarget with Eq::{not_equal, equal}

///|
pub extend RuntimeSymbol with Debug::{to_repr}

///|
pub extend RuntimeSymbol with Eq::{not_equal, equal}

///|
pub extend RuntimeSymbolResolver with Debug::{to_repr}
