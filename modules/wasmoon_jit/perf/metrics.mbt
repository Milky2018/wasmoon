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
fn detail_enabled() -> Bool {
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
  SemanticLowering
  TargetLowering
  RegisterAllocation
  FramePlanning
  Emission
}

///|
pub struct IRPassMetric {
  name : String
  duration_us : Int64
  before_insts : Int
  after_insts : Int
  changed : Bool
  egraph_classes : Int?
  egraph_nodes : Int?
  egraph_rule_apps : Int?
  work_done : Int?
  budget_exhausted : Bool?
} derive(ToJson)

///|
pub struct RegallocPhaseMetric {
  name : String
  duration_us : Int64
} derive(ToJson)

///|
pub struct FunctionMetrics {
  func_idx : Int
  func_name : String
  opt_level : Int
  ir_insts_before : Int
  mut ir_insts_after : Int
  mut optimize_us : Int64
  mut lower_us : Int64
  mut target_lower_us : Int64
  mut regalloc_us : Int64
  mut frame_plan_us : Int64
  mut emit_us : Int64
  mut code_size : Int
  mut spill_slots : Int
  mut spills : Int
  mut reloads : Int
  mut reg_moves : Int
  mut spill_to_spill : Int
  ir_passes : Array[IRPassMetric]
  regalloc_phases : Array[RegallocPhaseMetric]
} derive(ToJson)

///|
pub struct ModuleMetricsReport {
  schema_version : Int
  expected_functions : Int
  mut module_compile_us : Int64
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
        schema_version: 3,
        expected_functions: 0,
        module_compile_us: 0L,
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
pub fn reset_module(expected_functions : Int) -> Unit {
  guard enabled() else { return }
  module_state.val = Some({
    schema_version: 3,
    expected_functions,
    module_compile_us: 0L,
    functions: [],
  })
  current_function_state.val = None
}

///|
pub fn set_module_compile_us(us : Int64) -> Unit {
  guard enabled() else { return }
  ensure_module_state().module_compile_us = us
}

///|
pub fn begin_function(
  func_idx : Int,
  func_name : String,
  opt_level : Int,
  ir_insts_before : Int,
) -> Unit {
  guard enabled() else { return }
  flush_current_function_if_any()
  current_function_state.val = Some({
    func_idx,
    func_name,
    opt_level,
    ir_insts_before,
    ir_insts_after: ir_insts_before,
    optimize_us: 0L,
    lower_us: 0L,
    target_lower_us: 0L,
    regalloc_us: 0L,
    frame_plan_us: 0L,
    emit_us: 0L,
    code_size: 0,
    spill_slots: 0,
    spills: 0,
    reloads: 0,
    reg_moves: 0,
    spill_to_spill: 0,
    ir_passes: [],
    regalloc_phases: [],
  })
}

///|
pub fn record_ir_pass(
  pass_name : String,
  before_insts : Int,
  after_insts : Int,
  changed : Bool,
  duration_us : Int64,
  egraph_classes? : Int? = None,
  egraph_nodes? : Int? = None,
  egraph_rule_apps? : Int? = None,
  work_done? : Int? = None,
  budget_exhausted? : Bool? = None,
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
      egraph_classes,
      egraph_nodes,
      egraph_rule_apps,
      work_done,
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
    @milkir.install_optimization_metrics_sink(
      @milkir.OptimizationMetricsSink::new(milkir_metrics_now_us, fn(metric) {
        record_ir_pass(
          metric.name,
          metric.before_insts,
          metric.after_insts,
          metric.changed,
          metric.duration_us,
          egraph_classes=metric.egraph_classes,
          egraph_nodes=metric.egraph_nodes,
          egraph_rule_apps=metric.egraph_rule_apps,
          work_done=metric.work_done,
          budget_exhausted=metric.budget_exhausted,
        )
      }),
    )
  } else {
    @milkir.clear_optimization_metrics_sink()
  }
}

///|
pub fn clear_milkir_metrics_sink() -> Unit {
  @milkir.clear_optimization_metrics_sink()
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
      SemanticLowering => m.lower_us = duration_us
      TargetLowering => m.target_lower_us = duration_us
      RegisterAllocation => m.regalloc_us = duration_us
      FramePlanning => m.frame_plan_us = duration_us
      Emission => m.emit_us = duration_us
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
pub fn record_regalloc_stats(
  spill_slots : Int,
  spills : Int,
  reloads : Int,
  reg_moves : Int,
  spill_to_spill : Int,
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
pub fn finish_function(ir_insts_after : Int, code_size : Int) -> Unit {
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
