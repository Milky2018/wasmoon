///|
/// A native owner could not allocate its backing state.
pub(all) suberror NativeAllocationError {
  OutOfMemory
} derive(Debug)

///|
pub extend NativeAllocationError with Debug::{to_repr}

///|
pub extend NativeAllocationError with Show::{output, to_string}

///|
pub impl Show for NativeAllocationError with fn output(_self, logger) {
  logger.write_string("native allocation failed")
}
