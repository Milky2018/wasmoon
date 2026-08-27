///|
pub extend EClassId with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend EClassId with Debug::{to_repr}

///|
pub extend EClassId with Eq::{not_equal, equal}

///|
pub extend EClassId with Hash::{hash, hash_combine}

///|
pub extend EClassId with Show::{to_string, output}

///|
pub extend ENode with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend ENode with Debug::{to_repr}

///|
pub extend ENode with Eq::{not_equal, equal}

///|
pub extend ENode with Hash::{hash, hash_combine}

///|
pub extend EOpcode with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend EOpcode with Debug::{to_repr}

///|
pub extend EOpcode with Eq::{not_equal, equal}

///|
pub extend EOpcode with Hash::{hash, hash_combine}

///|
pub extend EOpcode with Show::{to_string, output}

///|
pub extend EOpcodeTag with Debug::{to_repr}

///|
pub extend EOpcodeTag with Eq::{not_equal, equal}

///|
pub extend EOpcodeTag with Hash::{hash, hash_combine}

///|
pub extend SaturationLimits with Debug::{to_repr}
