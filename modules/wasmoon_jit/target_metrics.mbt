///|
fn target_metrics_tick(enabled : Bool) -> @perf.PerfTick? {
  if enabled {
    Some(@perf.tick_now())
  } else {
    None
  }
}

///|
fn detail_metrics_tick(enabled : Bool) -> @perf.PerfTick? {
  if enabled && @perf.detail_enabled() {
    Some(@perf.tick_now())
  } else {
    None
  }
}

///|
fn record_compile_subphase(
  name : String,
  tick : @perf.PerfTick?,
  parent? : String = "function",
) -> Unit {
  if tick is Some(start) {
    @perf.record_compile_subphase_us(name, @perf.elapsed_us(start), parent~)
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
fn semantic_cleanup_phase_name(
  phase : @semantic_machv.MandatoryCleanupPhase,
) -> String {
  match phase {
    VerifyInput => "semantic_cleanup.verify_input"
    CollectAliases => "semantic_cleanup.collect_aliases"
    RewriteAliases => "semantic_cleanup.rewrite_aliases"
    RemoveDeadInstructions => "semantic_cleanup.remove_dead_instructions"
    VerifyOutput => "semantic_cleanup.verify_output"
  }
}

///|
fn semantic_lower_metrics_observer() -> (@milkir_machv.SemanticLowerEvent) -> Unit {
  let phase : Ref[(String, @perf.PerfTick)?] = { val: None, }
  fn close_phase() -> Unit {
    if phase.val is Some((name, tick)) {
      @perf.record_compile_subphase_us(
        name,
        @perf.elapsed_us(tick),
        parent="semantic_lowering",
      )
      phase.val = None
    }
  }

  fn(event) {
    match event {
      InputValidationStarted => {
        close_phase()
        phase.val = Some(("semantic_input_validation", @perf.tick_now()))
      }
      SemanticConstructionStarted => {
        close_phase()
        phase.val = Some(("semantic_construction", @perf.tick_now()))
      }
      CleanupPhaseStarted(cleanup_phase) => {
        close_phase()
        phase.val = Some(
          (semantic_cleanup_phase_name(cleanup_phase), @perf.tick_now()),
        )
      }
      SemanticLoweringFinished => close_phase()
    }
  }
}

///|
fn target_compile_metrics_observer(
  target_lower_tick : @perf.PerfTick,
) -> (@vcode.TargetCompileEvent) -> Unit {
  let detail = @perf.detail_enabled()
  let phase_tick : Ref[@perf.PerfTick?] = { val: None, }
  let target_phase : Ref[(String, @perf.PerfTick)?] = { val: None, }
  let validation_phase : Ref[(String, @perf.PerfTick)?] = { val: None, }
  // The allocator reports each internal phase as it begins; the previous one
  // ends at that instant, and RegallocFinished closes the last (ISS-371).
  let regalloc_phase : Ref[(String, @perf.PerfTick)?] = { val: None, }
  fn close_regalloc_phase() -> Unit {
    if regalloc_phase.val is Some((name, tick)) {
      @perf.record_regalloc_phase_us(name, @perf.elapsed_us(tick))
      regalloc_phase.val = None
    }
  }

  fn close_target_phase() -> Unit {
    if target_phase.val is Some((name, tick)) {
      @perf.record_compile_subphase_us(
        name,
        @perf.elapsed_us(tick),
        parent="target_lowering",
      )
      target_phase.val = None
    }
  }

  fn close_validation_phase() -> Unit {
    if validation_phase.val is Some((name, tick)) {
      @perf.record_compile_subphase_us(
        name,
        @perf.elapsed_us(tick),
        parent="target_vcode_validation",
      )
      validation_phase.val = None
    }
  }

  fn(event) {
    match event {
      TargetAnalysisStarted =>
        if detail {
          close_target_phase()
          target_phase.val = Some(("target_analysis", @perf.tick_now()))
        }
      TargetConstructionStarted =>
        if detail {
          close_target_phase()
          target_phase.val = Some(
            ("target_vcode_construction", @perf.tick_now()),
          )
        }
      TargetValidationStarted =>
        if detail {
          close_target_phase()
          target_phase.val = Some(("target_vcode_validation", @perf.tick_now()))
        }
      TargetCommonValidationStarted =>
        if detail {
          close_validation_phase()
          validation_phase.val = Some(
            ("target_common_validation", @perf.tick_now()),
          )
        }
      TargetIsaValidationStarted =>
        if detail {
          close_validation_phase()
          validation_phase.val = Some(
            ("target_isa_validation", @perf.tick_now()),
          )
        }
      TargetSealingStarted =>
        if detail {
          close_target_phase()
          target_phase.val = Some(("target_vcode_sealing", @perf.tick_now()))
        }
      TargetSelectionFinished =>
        if detail {
          close_validation_phase()
          close_target_phase()
        }
      RegallocStarted => {
        close_target_phase()
        record_target_stage(TargetLowering, Some(target_lower_tick)) |> ignore
        phase_tick.val = Some(@perf.tick_now())
      }
      RegallocPhaseStarted(name) =>
        if detail {
          close_regalloc_phase()
          regalloc_phase.val = Some((name, @perf.tick_now()))
        }
      RegallocPhasesFinished =>
        if detail {
          close_regalloc_phase()
          // Everything from here to RegallocFinished is plan translation and
          // target-level checking, not allocator work. Naming it keeps the
          // phases summing to the measured regalloc stage.
          regalloc_phase.val = Some(("plan_translation", @perf.tick_now()))
        }
      RegallocLoopMeasured(statistics) =>
        @perf.record_regalloc_loop(
          statistics.queue_pops,
          statistics.register_probes,
          statistics.occupied_segments_scanned,
          statistics.conflicts,
          statistics.evictions,
          statistics.bundle_splits,
          statistics.second_chance_attempts,
          statistics.max_queue_length,
        )
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
