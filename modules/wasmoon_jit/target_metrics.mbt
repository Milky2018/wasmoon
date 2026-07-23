///|
fn target_metrics_tick(enabled : Bool) -> @perf.PerfTick? {
  if enabled {
    Some(@perf.tick_now())
  } else {
    None
  }
}

///|
fn record_target_stage(stage : String, tick : @perf.PerfTick?) -> Unit {
  if tick is Some(start) {
    let duration_us = @perf.elapsed_us(start)
    @perf.record_stage_us(stage, duration_us)
    if stage == "regalloc" {
      @perf.record_regalloc_phase_us("allocate_vcode", duration_us)
    }
  }
}

///|
fn record_target_allocation_stats(
  statistics : @vcode.AllocationStatistics,
) -> Unit {
  @perf.record_regalloc_stats(
    statistics.spill_slots,
    statistics.spills,
    statistics.reloads,
    statistics.reg_moves,
    statistics.spill_to_spill,
  )
}

///|
fn target_compile_metrics_observer(
  target_lower_tick : @perf.PerfTick,
) -> (@vcode.TargetCompileEvent) -> Unit {
  let phase_tick : Ref[@perf.PerfTick?] = { val: None }
  fn(event) {
    match event {
      RegallocStarted => {
        record_target_stage("target_lower", Some(target_lower_tick))
        phase_tick.val = Some(@perf.tick_now())
      }
      RegallocFinished(statistics) => {
        record_target_stage("regalloc", phase_tick.val)
        record_target_allocation_stats(statistics)
      }
      FramePlanningStarted => phase_tick.val = Some(@perf.tick_now())
      FramePlanningFinished => record_target_stage("frame_plan", phase_tick.val)
      EmissionStarted => phase_tick.val = Some(@perf.tick_now())
      EmissionFinished => record_target_stage("emit", phase_tick.val)
    }
  }
}
