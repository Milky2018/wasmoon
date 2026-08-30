///|
/// The point within an instruction where an allocation operand is read or
/// written.
pub(all) enum OperandTiming {
  Early
  Late
} derive(Eq, Debug)

///|
pub extend OperandTiming with Debug::{to_repr}

///|
pub extend OperandTiming with Eq::{not_equal, equal}
