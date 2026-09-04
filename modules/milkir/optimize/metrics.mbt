///|
/// Metrics emitted for one optimization pass.
pub struct OptimizationPassMetric {
  name : String
  duration_us : Int64
  before_insts : Int
  after_insts : Int
  changed : Bool
  rewrite_attempts : Int?
  rewrite_apps : Int?
  rewrite_created_insts : Int?
  work_done : Int?
  value_lookup_probes : Int?
  budget_exhausted : Bool?
}

///|
/// Optional embedding hook for optimization metrics.
///
/// The embedder owns the clock and recorder so MilkIR remains independent of
/// any runtime, operating system, or metrics output format.
struct OptimizationMetricsSink {
  now_us : () -> Int64
  record : (OptimizationPassMetric) -> Unit
}

///|
pub fn OptimizationMetricsSink::new(
  now_us : () -> Int64,
  record : (OptimizationPassMetric) -> Unit,
) -> OptimizationMetricsSink {
  { now_us, record, }
}

///|
let optimization_metrics_sink : Ref[OptimizationMetricsSink?] = { val: None, }

///|
pub fn install_optimization_metrics_sink(
  sink : OptimizationMetricsSink,
) -> Unit {
  optimization_metrics_sink.val = Some(sink)
}

///|
pub fn clear_optimization_metrics_sink() -> Unit {
  optimization_metrics_sink.val = None
}

///|
fn perf_enabled() -> Bool {
  optimization_metrics_sink.val is Some(_)
}

///|
fn perf_tick_now() -> Int64 {
  match optimization_metrics_sink.val {
    Some(sink) => (sink.now_us)()
    None => 0L
  }
}

///|
fn perf_elapsed_us(tick : Int64) -> Int64 {
  match optimization_metrics_sink.val {
    Some(sink) => (sink.now_us)() - tick
    None => 0L
  }
}

///|
fn perf_record_ir_pass(
  pass_name : String,
  before : Int,
  after : Int,
  changed : Bool,
  duration_us : Int64,
  rewrite_attempts? : Int? = None,
  rewrite_apps? : Int? = None,
  rewrite_created_insts? : Int? = None,
  work_done? : Int? = None,
  value_lookup_probes? : Int? = None,
  budget_exhausted? : Bool? = None,
) -> Unit {
  if optimization_metrics_sink.val is Some(sink) {
    (sink.record)({
      name: pass_name,
      duration_us,
      before_insts: before,
      after_insts: after,
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
