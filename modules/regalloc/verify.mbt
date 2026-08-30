///|
pub suberror VerifyError {
  Unassigned(vreg~ : VirtualReg)
  FixedConstraintViolation(
    vreg~ : VirtualReg,
    required~ : PhysicalReg,
    actual~ : Location
  )
  InvalidPreference(vreg~ : VirtualReg, preferred~ : PhysicalReg)
  IncorrectValue(vreg~ : VirtualReg, location~ : Location)
  ScratchRegisterUnavailable(message~ : String)
  InvalidPlan(message~ : String)
} derive(Debug)

///|
fn location_key(location : Location) -> (Int, Int) {
  match location.register() {
    Some(reg) => physical_reg_key(reg)
    None => (3, location.spill_index().unwrap())
  }
}
