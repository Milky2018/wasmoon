///|
pub extend CallArgumentLocation with Debug::{to_repr}

///|
pub extend CallArgumentLocation with Eq::{not_equal, equal}

///|
pub extend CallLayout with Debug::{to_repr}

///|
pub extend CallLayout with Eq::{not_equal, equal}

///|
pub extend CallResultLocation with Debug::{to_repr}

///|
pub extend CallResultLocation with Eq::{not_equal, equal}

///|
pub extend GprWidth with Debug::{to_repr}

///|
pub extend GprWidth with Eq::{not_equal, equal}

///|
pub extend InternalAbiError with Debug::{to_repr}

///|
pub extend InternalAbiError with Eq::{not_equal, equal}

///|
pub extend InternalAbiError with Show::{to_string, output}

///|
pub extend InternalCallPlan with Debug::{to_repr}

///|
pub extend InternalCallPlan with Eq::{not_equal, equal}

///|
pub extend TargetVCodeVerifyError with Debug::{to_repr}

///|
pub extend TargetVCodeVerifyError with Eq::{not_equal, equal}

///|
pub extend TargetVCodeVerifyError with Show::{to_string, output}

///|
pub extend X64Address with Debug::{to_repr}

///|
pub extend X64Address with Eq::{not_equal, equal}

///|
pub extend X64AllocationError with Debug::{to_repr}

///|
pub extend X64AllocationError with Show::{to_string, output}

///|
pub extend X64CompileError with Debug::{to_repr}

///|
pub extend X64CompileError with Show::{to_string, output}

///|
pub extend X64Condition with Debug::{to_repr}

///|
pub extend X64Condition with Eq::{not_equal, equal}

///|
pub extend X64Conversion with Debug::{to_repr}

///|
pub extend X64Conversion with Eq::{not_equal, equal}

///|
pub extend X64EmitError with Debug::{to_repr}

///|
pub extend X64EmitError with Show::{to_string, output}

///|
pub extend X64FloatBinary with Debug::{to_repr}

///|
pub extend X64FloatBinary with Eq::{not_equal, equal}

///|
pub extend X64FloatCondition with Debug::{to_repr}

///|
pub extend X64FloatCondition with Eq::{not_equal, equal}

///|
pub extend X64FloatTernary with Debug::{to_repr}

///|
pub extend X64FloatTernary with Eq::{not_equal, equal}

///|
pub extend X64FloatTrapCondition with Debug::{to_repr}

///|
pub extend X64FloatTrapCondition with Eq::{not_equal, equal}

///|
pub extend X64FloatUnary with Debug::{to_repr}

///|
pub extend X64FloatUnary with Eq::{not_equal, equal}

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
pub extend X64IntUnary with Debug::{to_repr}

///|
pub extend X64IntUnary with Eq::{not_equal, equal}

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

///|
pub extend X64StackObject with Debug::{to_repr}

///|
pub extend X64StackObject with Eq::{not_equal, equal}

///|
pub extend X64VectorConversion with Debug::{to_repr}

///|
pub extend X64VectorConversion with Eq::{not_equal, equal}

///|
pub extend X64VectorIntBinary with Debug::{to_repr}

///|
pub extend X64VectorIntBinary with Eq::{not_equal, equal}

///|
pub extend X64VectorIntUnary with Debug::{to_repr}

///|
pub extend X64VectorIntUnary with Eq::{not_equal, equal}

///|
pub extend X64VectorPredicate with Debug::{to_repr}

///|
pub extend X64VectorPredicate with Eq::{not_equal, equal}
