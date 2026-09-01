///|
pub extend ArrayInstance with Debug::{to_repr}

///|
pub extend ArrayInstance with Show::{to_string, output}

///|
pub extend Caller with Debug::{to_repr}

///|
pub extend ExnInstance with Debug::{to_repr}

///|
pub extend Frame with Debug::{to_repr}

///|
pub extend FuncInst with Debug::{to_repr}

///|
pub extend FuncInst with Show::{to_string, output}

///|
pub extend FuncOwner with Debug::{to_repr}

///|
pub extend FuncOwner with Eq::{not_equal, equal}

///|
pub extend GCObject with Debug::{to_repr}

///|
pub extend GCObject with Show::{to_string, output}

///|
pub extend GCStats with Debug::{to_repr}

///|
pub extend GcStats with Debug::{to_repr}

///|
pub extend GlobalInstance with Debug::{to_repr}

///|
pub extend MarkSweepHeap with Debug::{to_repr}

///|
pub extend MarkSweepHeap with GcManager::{write_barrier}

///|
pub extend MarkSweepHeap with GcRuntime::{
  write_barrier_pre,
  read_barrier,
  force_collect,
  collection_count,
  write_barrier_post,
}

///|
pub extend Memory with Debug::{to_repr}

///|
pub extend ModuleInstance with Debug::{to_repr}

///|
pub extend ModuleInstance with Show::{to_string, output}

///|
pub extend RuntimeError with Show::{to_string, output}

///|
pub extend RuntimeErrorContext with Show::{to_string, output}

///|
pub extend Stack with Debug::{to_repr}

///|
pub extend Store with Debug::{to_repr}

///|
pub extend StoreFuncrefEntry with Debug::{to_repr}

///|
pub extend StoreFuncrefEntry with Eq::{not_equal, equal}

///|
pub extend StructInstance with Debug::{to_repr}

///|
pub extend StructInstance with Show::{to_string, output}

///|
pub extend Table with Debug::{to_repr}
