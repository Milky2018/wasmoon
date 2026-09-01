///|
pub extend RuntimeSymbols with Debug::{to_repr}

///|
pub extend RuntimeSymbols with Eq::{not_equal, equal}

///|
pub extend WasmDefinedTypeContract with Debug::{to_repr}

///|
pub extend WasmDefinedTypeContract with Eq::{not_equal, equal}

///|
pub extend WasmFieldContract with Debug::{to_repr}

///|
pub extend WasmFieldContract with Eq::{not_equal, equal}

///|
pub extend WasmFunctionContract with Debug::{to_repr}

///|
pub extend WasmFunctionContract with Eq::{not_equal, equal}

///|
pub extend WasmOpcode with Debug::{to_repr}

///|
pub extend WasmOpcode with Eq::{not_equal, equal}

///|
pub extend WasmOpcode with Hash::{hash, hash_combine}

///|
pub extend WasmRuntimeHelper with Debug::{to_repr}

///|
pub extend WasmRuntimeHelper with Eq::{not_equal, equal}

///|
pub extend WasmStorageContract with Debug::{to_repr}

///|
pub extend WasmStorageContract with Eq::{not_equal, equal}

///|
pub extend WasmTableContract with Debug::{to_repr}

///|
pub extend WasmTableContract with Eq::{not_equal, equal}
