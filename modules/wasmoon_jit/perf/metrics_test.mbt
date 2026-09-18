///|
test "compile metrics preserve every production phase and allocation summary" {
  guard !@perf.detail_enabled() else { return }
  let previous = @env.get_env_var("WASMOON_PERF_METRICS")
  @env.set_env_var("WASMOON_PERF_METRICS", "1")
  @perf.reset_module(1)
  @perf.begin_function(7, "measured", 2, 30)
  @perf.record_stage_us(Optimize, 10L)
  @perf.record_stage_us(NativeLowering, 20L)
  @perf.record_stage_us(TargetLowering, 30L)
  @perf.record_stage_us(RegisterAllocation, 40L)
  @perf.record_stage_us(FramePlanning, 50L)
  @perf.record_stage_us(Emission, 60L)
  @perf.record_regalloc_stats(3, 4, 5, 6, 7)
  @perf.record_regalloc_loop(8, 9, 10, 11, 12, 13, 14, 15)
  @perf.finish_function(18, 96)
  @perf.set_module_compile_us(240L)
  inspect(
    @perf.export_json(),
    content=(
      #|{
      #|  "schema_version": 7,
      #|  "expected_functions": 1,
      #|  "module_compile_us": "240",
      #|  "compile_subphases": [],
      #|  "functions": [
      #|    {
      #|      "func_idx": 7,
      #|      "func_name": "measured",
      #|      "opt_level": 2,
      #|      "ir_insts_before": 30,
      #|      "ir_insts_after": 18,
      #|      "function_compile_us": "0",
      #|      "optimize_us": "10",
      #|      "lower_us": "20",
      #|      "target_lower_us": "30",
      #|      "regalloc_us": "40",
      #|      "frame_plan_us": "50",
      #|      "emit_us": "60",
      #|      "compile_subphases": [],
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

///|
test "detailed compile subphases reconcile their declared parent" {
  guard @perf.detail_enabled() else { return }
  let previous = @env.get_env_var("WASMOON_PERF_METRICS")
  @env.set_env_var("WASMOON_PERF_METRICS", "1")
  @perf.reset_module(1)
  @perf.begin_function(7, "measured", 2, 30)
  @perf.record_stage_us(Optimize, 10L)
  @perf.record_compile_subphase_us("frontend_translation", 5L)
  @perf.record_compile_subphase_us(
    "native_validation",
    7L,
    parent="native_lowering",
  )
  @perf.record_stage_us(NativeLowering, 9L)
  @perf.record_function_compile_us(30L)
  @perf.finish_function(18, 96)
  @perf.record_module_subphase_us("module_preparation", 3L)
  @perf.set_module_compile_us(40L)
  let report = @perf.export_json()
  inspect(
    report.contains(
      (
        #|"name": "function_orchestration",
        #|          "parent": "function",
        #|          "duration_us": "6"
      ),
    ),
    content="true",
  )
  inspect(
    report.contains(
      (
        #|"name": "native_validation",
        #|          "parent": "native_lowering",
        #|          "duration_us": "7"
      ),
    ),
    content="true",
  )
  inspect(
    report.contains(
      (
        #|"name": "native_orchestration",
        #|          "parent": "native_lowering",
        #|          "duration_us": "2"
      ),
    ),
    content="true",
  )
  inspect(
    report.contains(
      (
        #|"name": "module_orchestration",
        #|      "parent": "module",
        #|      "duration_us": "7"
      ),
    ),
    content="true",
  )
  match previous {
    Some(value) => @env.set_env_var("WASMOON_PERF_METRICS", value)
    None => @env.unset_env_var("WASMOON_PERF_METRICS")
  }
}
