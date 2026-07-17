///|
pub struct LoweringContext {
  priv internal_abi : InternalAbi
}

///|
pub fn LoweringContext::new(internal_abi : InternalAbi) -> LoweringContext {
  { internal_abi: internal_abi.copy() }
}
