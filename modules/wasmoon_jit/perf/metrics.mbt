///|
/// A lightweight, opt-in performance metrics collector for compilation stages.
///
/// Enable via environment variable:
/// - WASMOON_PERF_METRICS=1

///|
fn is_truthy_env(v : String) -> Bool {
  v == "1" ||
  v == "true" ||
  v == "TRUE" ||
  v == "yes" ||
  v == "YES" ||
  v == "on" ||
  v == "ON"
}

///|
pub fn enabled() -> Bool {
  match @env.get_env_var("WASMOON_PERF_METRICS") {
    Some(v) => is_truthy_env(v)
    None => false
  }
}

///|
/// Detailed pass/phase metrics can be very large on big modules and may
/// significantly increase memory pressure under emulation.
///
/// Default: disabled (compact mode).
/// Enable explicitly with WASMOON_PERF_METRICS_DETAIL=1/true/full.
let perf_detail_metrics_enabled : Bool = match
  @env.get_env_var("WASMOON_PERF_METRICS_DETAIL") {
  Some(v) => is_truthy_env(v) || v == "full" || v == "FULL"
  None => false
}

///|
pub fn detail_enabled() -> Bool {
  perf_detail_metrics_enabled
}

///|
pub type PerfTick = Instant

///|
pub fn tick_now() -> PerfTick {
  instant_now()
}

///|
pub fn elapsed_us(start : PerfTick) -> Int64 {
  (instant_elapsed_as_secs_f64(start) * 1000000.0).to_int64()
}

///|
/// A complete compilation stage recorded for one function.
///
/// Keep this typed at the recording boundary so adding or renaming a stage
/// cannot silently lose metrics through an unknown string.
pub(all) enum FunctionCompileStage {
  Optimize
  NativeLowering
  TargetLowering
  RegisterAllocation
  FramePlanning
  Emission
}

///|
pub struct IRPassMetric {
  name : String
  duration_us : Int64
  before_insts : Int32
  after_insts : Int32
  changed : Bool
  rewrite_attempts : Int32?
  rewrite_apps : Int32?
  rewrite_created_insts : Int32?
  work_done : Int32?
  value_lookup_probes : Int32?
  budget_exhausted : Bool?
} derive(ToJson)

///|
pub struct RegallocPhaseMetric {
  name : String
  duration_us : Int64
} derive(ToJson)

///|
pub struct CompileSubphaseMetric {
  name : String
  parent : String
  duration_us : Int64
} derive(ToJson)

///|
pub struct RegallocLoopMetric {
  queue_pops : Int32
  register_probes : Int32
  occupied_segments_scanned : Int32
  conflicts : Int32
  evictions : Int32
  bundle_splits : Int32
  second_chance_attempts : Int32
  max_queue_length : Int32
} derive(ToJson)

///|
pub struct FunctionMetrics {
  func_idx : Int32
  func_name : String
  opt_level : Int32
  ir_insts_before : Int32
  mut ir_insts_after : Int32
  mut function_compile_us : Int64
  mut optimize_us : Int64
  mut lower_us : Int64
  mut target_lower_us : Int64
  mut regalloc_us : Int64
  mut frame_plan_us : Int64
  mut emit_us : Int64
  compile_subphases : Array[CompileSubphaseMetric]
  mut code_size : Int32
  mut spill_slots : Int32
  mut spills : Int32
  mut reloads : Int32
  mut reg_moves : Int32
  mut spill_to_spill : Int32
  mut regalloc_loop : RegallocLoopMetric?
  ir_passes : Array[IRPassMetric]
  regalloc_phases : Array[RegallocPhaseMetric]
} derive(ToJson)

///|
pub struct ModuleMetricsReport {
  schema_version : Int32
  expected_functions : Int32
  mut module_compile_us : Int64
  compile_subphases : Array[CompileSubphaseMetric]
  functions : Array[FunctionMetrics]
} derive(ToJson)

///|
let module_state : Ref[ModuleMetricsReport?] = { val: None, }

///|
let current_function_state : Ref[FunctionMetrics?] = { val: None, }

///|
fn ensure_module_state() -> ModuleMetricsReport {
  match module_state.val {
    Some(m) => m
    None => {
      let m = {
        schema_version: 7,
        expected_functions: 0,
        module_compile_us: 0L,
        compile_subphases: [],
        functions: [],
      }
      module_state.val = Some(m)
      m
    }
  }
}

///|
fn flush_current_function_if_any() -> Unit {
  if current_function_state.val is Some(m) {
    ensure_module_state().functions.push(m)
    current_function_state.val = None
  }
}

///|
pub fn reset_module(expected_functions : Int32) -> Unit {
  guard enabled() else { return }
  module_state.val = Some({
    schema_version: 7,
    expected_functions,
    module_compile_us: 0L,
    compile_subphases: [],
    functions: [],
  })
  current_function_state.val = None
}

///|
pub fn set_module_compile_us(us : Int64) -> Unit {
  guard enabled() else { return }
  let report = ensure_module_state()
  report.module_compile_us = us
  if detail_enabled() {
    let mut attributed = 0L
    for subphase in report.compile_subphases {
      if subphase.parent == "module" {
        attributed = attributed + subphase.duration_us
      }
    }
    for function in report.functions {
      attributed = attributed + function.function_compile_us
    }
    let orchestration = us - attributed
    if orchestration > 0L {
      report.compile_subphases.push({
        name: "module_orchestration",
        parent: "module",
        duration_us: orchestration,
      })
    }
  }
}

///|
pub fn begin_function(
  func_idx : Int32,
  func_name : String,
  opt_level : Int32,
  ir_insts_before : Int32,
) -> Unit {
  guard enabled() else { return }
  flush_current_function_if_any()
  current_function_state.val = Some({
    func_idx,
    func_name,
    opt_level,
    ir_insts_before,
    ir_insts_after: ir_insts_before,
    function_compile_us: 0L,
    optimize_us: 0L,
    lower_us: 0L,
    target_lower_us: 0L,
    regalloc_us: 0L,
    frame_plan_us: 0L,
    emit_us: 0L,
    compile_subphases: [],
    code_size: 0,
    spill_slots: 0,
    spills: 0,
    reloads: 0,
    reg_moves: 0,
    spill_to_spill: 0,
    regalloc_loop: None,
    ir_passes: [],
    regalloc_phases: [],
  })
}

///|
pub fn record_ir_pass(
  pass_name : String,
  before_insts : Int32,
  after_insts : Int32,
  changed : Bool,
  duration_us : Int64,
  rewrite_attempts~ : Int32? = None,
  rewrite_apps~ : Int32? = None,
  rewrite_created_insts~ : Int32? = None,
  work_done~ : Int32? = None,
  value_lookup_probes~ : Int32? = None,
  budget_exhausted~ : Bool? = None,
) -> Unit {
  guard enabled() else { return }
  guard detail_enabled() else { return }
  if current_function_state.val is Some(m) {
    m.ir_passes.push({
      name: pass_name,
      duration_us,
      before_insts,
      after_insts,
      changed,
      rewrite_attempts,
      rewrite_apps,
      rewrite_created_insts,
      work_done,
      value_lookup_probes,
      budget_exhausted,
    })
  }
}

///|
let milkir_metrics_clock_origin : Ref[PerfTick?] = { val: None, }

///|
fn milkir_metrics_now_us() -> Int64 {
  let origin = match milkir_metrics_clock_origin.val {
    Some(origin) => origin
    None => {
      let origin = tick_now()
      milkir_metrics_clock_origin.val = Some(origin)
      origin
    }
  }
  elapsed_us(origin)
}

///|
pub fn install_milkir_metrics_sink() -> Unit {
  if enabled() && detail_enabled() {
    @optimize.install_optimization_metrics_sink(
      @optimize.OptimizationMetricsSink::new(milkir_metrics_now_us, fn(metric) {
        record_ir_pass(
          metric.name,
          metric.before_insts,
          metric.after_insts,
          metric.changed,
          metric.duration_us,
          rewrite_attempts=metric.rewrite_attempts,
          rewrite_apps=metric.rewrite_apps,
          rewrite_created_insts=metric.rewrite_created_insts,
          work_done=metric.work_done,
          value_lookup_probes=metric.value_lookup_probes,
          budget_exhausted=metric.budget_exhausted,
        )
      }),
    )
  } else {
    @optimize.clear_optimization_metrics_sink()
  }
}

///|
pub fn clear_milkir_metrics_sink() -> Unit {
  @optimize.clear_optimization_metrics_sink()
}

///|
pub fn record_stage_us(
  stage : FunctionCompileStage,
  duration_us : Int64,
) -> Unit {
  guard enabled() else { return }
  if current_function_state.val is Some(m) {
    match stage {
      Optimize => m.optimize_us = duration_us
      NativeLowering => m.lower_us = duration_us
      TargetLowering => m.target_lower_us = duration_us
      RegisterAllocation => m.regalloc_us = duration_us
      FramePlanning => m.frame_plan_us = duration_us
      Emission => m.emit_us = duration_us
    }
    if detail_enabled() {
      let parent_and_residual_name = match stage {
        NativeLowering => Some(("native_lowering", "native_orchestration"))
        TargetLowering => Some(("target_lowering", "target_orchestration"))
        _ => None
      }
      if parent_and_residual_name is Some((parent, residual_name)) {
        let mut attributed = 0L
        for subphase in m.compile_subphases {
          if subphase.parent == parent {
            attributed = attributed + subphase.duration_us
          }
        }
        let orchestration = duration_us - attributed
        if orchestration > 0L {
          m.compile_subphases.push({
            name: residual_name,
            parent,
            duration_us: orchestration,
          })
        }
      }
      match stage {
        RegisterAllocation => {
          let mut attributed = 0L
          for phase in m.regalloc_phases {
            attributed = attributed + phase.duration_us
          }
          let orchestration = duration_us - attributed
          if orchestration > 0L {
            m.regalloc_phases.push({
              name: "regalloc_orchestration",
              duration_us: orchestration,
            })
          }
        }
        _ => ()
      }
    }
  }
}

///|
pub fn record_function_compile_us(duration_us : Int64) -> Unit {
  guard enabled() && detail_enabled() else { return }
  if current_function_state.val is Some(m) {
    m.function_compile_us = duration_us
    let mut attributed = m.optimize_us +
      m.lower_us +
      m.target_lower_us +
      m.regalloc_us +
      m.frame_plan_us +
      m.emit_us
    for subphase in m.compile_subphases {
      if subphase.parent == "function" {
        attributed = attributed + subphase.duration_us
      }
    }
    let orchestration = duration_us - attributed
    if orchestration > 0L {
      m.compile_subphases.push({
        name: "function_orchestration",
        parent: "function",
        duration_us: orchestration,
      })
    }
  }
}

///|
pub fn record_regalloc_phase_us(
  phase_name : String,
  duration_us : Int64,
) -> Unit {
  guard enabled() else { return }
  guard detail_enabled() else { return }
  if current_function_state.val is Some(m) {
    m.regalloc_phases.push({ name: phase_name, duration_us, })
  }
}

///|
pub fn record_compile_subphase_us(
  phase_name : String,
  duration_us : Int64,
  parent~ : String = "function",
) -> Unit {
  guard enabled() && detail_enabled() else { return }
  if current_function_state.val is Some(m) {
    m.compile_subphases.push({ name: phase_name, parent, duration_us, })
  }
}

///|
pub fn record_module_subphase_us(
  phase_name : String,
  duration_us : Int64,
) -> Unit {
  guard enabled() && detail_enabled() else { return }
  ensure_module_state().compile_subphases.push({
    name: phase_name,
    parent: "module",
    duration_us,
  })
}

///|
pub fn record_regalloc_stats(
  spill_slots : Int32,
  spills : Int32,
  reloads : Int32,
  reg_moves : Int32,
  spill_to_spill : Int32,
) -> Unit {
  guard enabled() else { return }
  if current_function_state.val is Some(m) {
    m.spill_slots = spill_slots
    m.spills = spills
    m.reloads = reloads
    m.reg_moves = reg_moves
    m.spill_to_spill = spill_to_spill
  }
}

///|
pub fn record_regalloc_loop(
  queue_pops : Int32,
  register_probes : Int32,
  occupied_segments_scanned : Int32,
  conflicts : Int32,
  evictions : Int32,
  bundle_splits : Int32,
  second_chance_attempts : Int32,
  max_queue_length : Int32,
) -> Unit {
  guard enabled() else { return }
  if current_function_state.val is Some(m) {
    m.regalloc_loop = Some({
      queue_pops,
      register_probes,
      occupied_segments_scanned,
      conflicts,
      evictions,
      bundle_splits,
      second_chance_attempts,
      max_queue_length,
    })
  }
}

///|
pub fn finish_function(ir_insts_after : Int32, code_size : Int32) -> Unit {
  guard enabled() else { return }
  if current_function_state.val is Some(m) {
    m.ir_insts_after = ir_insts_after
    m.code_size = code_size
    flush_current_function_if_any()
  }
}

///|
pub fn export_json() -> String {
  guard enabled() else { return "{}\n" }
  flush_current_function_if_any()
  match module_state.val {
    Some(m) => m.to_json().stringify(indent=2) + "\n"
    None => "{}\n"
  }
}
