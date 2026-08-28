///|
test "compile metrics preserve every production phase and allocation summary" {
  let previous = @env.get_env_var("WASMOON_PERF_METRICS")
  @env.set_env_var("WASMOON_PERF_METRICS", "1")
  reset_module(1)
  begin_function(7, "measured", 2, 30)
  record_stage_us(Optimize, 10L)
  record_stage_us(SemanticLowering, 20L)
  record_stage_us(TargetLowering, 30L)
  record_stage_us(RegisterAllocation, 40L)
  record_stage_us(FramePlanning, 50L)
  record_stage_us(Emission, 60L)
  record_regalloc_stats(3, 4, 5, 6, 7)
  record_regalloc_loop(8, 9, 10, 11, 12, 13, 14, 15)
  finish_function(18, 96)
  set_module_compile_us(240L)
  inspect(
    export_json(),
    content=(
      #|{
      #|  "schema_version": 4,
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
      #|      "regalloc_loop": {
      #|        "queue_pops": 8,
      #|        "register_probes": 9,
      #|        "occupied_segments_scanned": 10,
      #|        "conflicts": 11,
      #|        "evictions": 12,
      #|        "bundle_splits": 13,
      #|        "second_chance_attempts": 14,
      #|        "max_queue_length": 15
      #|      },
      #|      "ir_passes": [],
      #|      "regalloc_phases": []
      #|    }
      #|  ]
      #|}
      #|
    ),
  )
  match previous {
    Some(value) => @env.set_env_var("WASMOON_PERF_METRICS", value)
    None => @env.unset_env_var("WASMOON_PERF_METRICS")
  }
}
