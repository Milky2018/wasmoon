///|
pub extend X64AllocationError with Debug::{to_repr}

///|
pub extend X64AllocationError with Show::{to_string, output}

///|
pub extend X64CompileError with Debug::{to_repr}

///|
pub extend X64CompileError with Show::{to_string, output}

///|
pub extend X64Conversion with Debug::{to_repr}

///|
pub extend X64Conversion with Eq::{not_equal, equal}

///|
pub extend X64EmitError with Debug::{to_repr}

///|
pub extend X64EmitError with Show::{to_string, output}

///|
pub extend X64FrameError with Debug::{to_repr}

///|
pub extend X64FrameError with Show::{to_string, output}

///|
pub extend X64Inst with Debug::{to_repr}

///|
pub extend X64Inst with Eq::{not_equal, equal}

///|
pub extend X64IntBinary with Debug::{to_repr}

///|
pub extend X64IntBinary with Eq::{not_equal, equal}

///|
pub extend X64LinkError with Debug::{to_repr}

///|
pub extend X64LinkError with Eq::{not_equal, equal}

///|
pub extend X64LinkError with Show::{to_string, output}

///|
pub extend X64LinkPlan with Debug::{to_repr}

///|
pub extend X64LowerError with Debug::{to_repr}

///|
pub extend X64LowerError with Show::{to_string, output}
