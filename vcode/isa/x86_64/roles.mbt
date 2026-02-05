///|
/// x86_64 role mapping stub.
///
/// Step 2: not implemented; `ISA::current()` never selects x86_64 today.

///|
pub fn int_reg_index(_role : @spec.IntRegRole) -> Int {
  abort("x86_64 JIT backend not implemented yet")
}
