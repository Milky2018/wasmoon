///|
test "compile metrics preserve every production phase and allocation summary" {
  let previous = @sys.get_env_var("WASMOON_PERF_METRICS")
  @sys.set_env_var("WASMOON_PERF_METRICS", "1")
  reset_module(1)
  begin_function(7, "measured", 2, 30)
  record_stage_us("optimize", 10L)
  record_stage_us("lower", 20L)
  record_stage_us("target_lower", 30L)
  record_stage_us("regalloc", 40L)
  record_stage_us("frame_plan", 50L)
  record_stage_us("emit", 60L)
  record_regalloc_stats(3, 4, 5, 6, 7)
  finish_function(18, 96)
  set_module_compile_us(240L)
  inspect(
    export_json(),
    content=(
      #|{
      #|  "schema_version": 3,
      #|  "expected_functions": 1,
      #|  "module_compile_us": "240",
      #|  "functions": [
      #|    {
      #|      "func_idx": 7,
      #|      "func_name": "measured",
      #|      "opt_level": 2,
      #|      "ir_insts_before": 30,
      #|      "ir_insts_after": 18,
      #|      "optimize_us": "10",
      #|      "lower_us": "20",
      #|      "target_lower_us": "30",
      #|      "regalloc_us": "40",
      #|      "frame_plan_us": "50",
      #|      "emit_us": "60",
      #|      "code_size": 96,
      #|      "spill_slots": 3,
      #|      "spills": 4,
      #|      "reloads": 5,
      #|      "reg_moves": 6,
      #|      "spill_to_spill": 7,
      #|      "ir_passes": [],
      #|      "regalloc_phases": []
      #|    }
      #|  ]
      #|}
      #|
    ),
  )
  match previous {
    Some(value) => @sys.set_env_var("WASMOON_PERF_METRICS", value)
    None => @sys.unset_env_var("WASMOON_PERF_METRICS")
  }
}
