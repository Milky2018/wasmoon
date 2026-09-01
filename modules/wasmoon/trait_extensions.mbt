///|
pub extend RuntimeAssembly with Debug::{to_repr}

///|
pub extend RuntimeAssembly with Eq::{not_equal, equal}

///|
pub extend RuntimeComponent with Debug::{to_repr}

///|
pub extend RuntimeComponent with Eq::{not_equal, equal}

///|
pub extend WasmCompilerPipelineError with Debug::{to_repr}

///|
pub extend WasmCompilerPipelineError with Eq::{not_equal, equal}

///|
pub extend WasmCompilerPipelineError with Show::{to_string, output}
