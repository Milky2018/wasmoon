///|
fn target_settings(settings : @abi.ABISettings) -> @x64_target.TargetSettings {
  { enable_pinned_reg: settings.enable_pinned_reg }
}

///|
fn machine_env_data_from_target(
  data : @x64_target.MachineEnvData,
) -> @spec.MachineEnvData {
  {
    preferred_int: data.preferred_int,
    nonpreferred_int: data.nonpreferred_int,
    preferred_float: data.preferred_float,
    nonpreferred_float: data.nonpreferred_float,
    preferred_vector: data.preferred_vector,
    nonpreferred_vector: data.nonpreferred_vector,
    callee_saved_int: data.callee_saved_int,
    callee_saved_float: data.callee_saved_float,
    scratch_int: data.scratch_int,
    scratch_float: data.scratch_float,
  }
}

///|
pub fn build_machine_env(
  settings : @abi.ABISettings,
  reserve_mem0_desc : Bool,
  reserve_func_table : Bool,
  reserve_extra_results_ptr : Bool,
) -> @spec.MachineEnvData {
  machine_env_data_from_target(
    @x64_target.build_machine_env(
      settings=target_settings(settings),
      reserve_mem0_desc~,
      reserve_func_table~,
      reserve_extra_results_ptr~,
    ),
  )
}
