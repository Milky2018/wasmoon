///|
/// Mapping from ISA-independent roles to concrete AArch64 physical registers.
///
/// This isolates AArch64-specific register choices in one place.

///|
pub fn int_reg_index(role : @spec.IntRegRole) -> Int {
  match role {
    Scratch1 => 16
    Scratch2 => 17
    FP => 29
    LR => 30
    SRet => 8
  }
}
