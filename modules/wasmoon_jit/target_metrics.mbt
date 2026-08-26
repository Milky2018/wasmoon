///|
fn target_metrics_tick(enabled : Bool) -> @perf.PerfTick? {
  if enabled {
    Some(@perf.tick_now())
  } else {
    None
  }
}

///|
fn record_target_stage(
  stage : @perf.FunctionCompileStage,
  tick : @perf.PerfTick?,
) -> Int64? {
  match tick {
    Some(start) => {
      let duration_us = @perf.elapsed_us(start)
      @perf.record_stage_us(stage, duration_us)
      Some(duration_us)
    }
    None => None
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
  let phase_tick : Ref[@perf.PerfTick?] = { val: None, }
  // The allocator reports each internal phase as it begins; the previous one
  // ends at that instant, and RegallocFinished closes the last (ISS-371).
  let regalloc_phase : Ref[(String, @perf.PerfTick)?] = { val: None, }
  fn close_regalloc_phase() -> Unit {
    if regalloc_phase.val is Some((name, tick)) {
      @perf.record_regalloc_phase_us(name, @perf.elapsed_us(tick))
      regalloc_phase.val = None
    }
  }

  fn(event) {
    match event {
      RegallocStarted => {
        record_target_stage(TargetLowering, Some(target_lower_tick)) |> ignore
        phase_tick.val = Some(@perf.tick_now())
      }
      RegallocPhaseStarted(name) => {
        close_regalloc_phase()
        regalloc_phase.val = Some((name, @perf.tick_now()))
      }
      RegallocPhasesFinished => {
        close_regalloc_phase()
        // Everything from here to RegallocFinished is plan translation and
        // target-level checking, not allocator work. Naming it keeps the
        // phases summing to the measured regalloc stage.
        regalloc_phase.val = Some(("plan_translation", @perf.tick_now()))
      }
      RegallocFinished(statistics) => {
        close_regalloc_phase()
        if record_target_stage(RegisterAllocation, phase_tick.val)
          is Some(duration_us) {
          @perf.record_regalloc_phase_us("allocate_vcode", duration_us)
        }
        record_target_allocation_stats(statistics)
      }
      FramePlanningStarted => phase_tick.val = Some(@perf.tick_now())
      FramePlanningFinished =>
        record_target_stage(FramePlanning, phase_tick.val) |> ignore
      EmissionStarted => phase_tick.val = Some(@perf.tick_now())
      EmissionFinished =>
        record_target_stage(Emission, phase_tick.val) |> ignore
    }
  }
}
