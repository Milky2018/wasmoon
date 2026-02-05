///|
/// x86_64 machine environment stub.
///
/// Step 1: not implemented; `ISA::current()` never selects x86_64.

///|
pub fn build_machine_env(
  _settings : @abi.ABISettings,
  _reserve_mem0_desc : Bool,
  _reserve_func_table : Bool,
  _reserve_extra_results_ptr : Bool,
) -> @spec.MachineEnvData {
  abort("x86_64 JIT backend not implemented yet")
}
