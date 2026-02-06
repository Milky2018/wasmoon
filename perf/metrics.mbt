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
  match @sys.get_env_var("WASMOON_PERF_METRICS") {
    Some(v) => is_truthy_env(v)
    None => false
  }
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
pub struct IRPassMetric {
  name : String
  duration_us : Int64
  before_insts : Int
  after_insts : Int
  changed : Bool
  egraph_classes : Int?
  egraph_nodes : Int?
  egraph_rule_apps : Int?
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
  mut regalloc_us : Int64
  mut emit_us : Int64
  mut code_size : Int
  mut spill_slots : Int
  mut spills : Int
  mut reloads : Int
  mut reg_moves : Int
  mut spill_to_spill : Int
  ir_passes : Array[IRPassMetric]
} derive(ToJson)

///|
pub struct ModuleMetricsReport {
  schema_version : Int
  expected_functions : Int
  mut module_compile_us : Int64
  functions : Array[FunctionMetrics]
} derive(ToJson)

///|
let module_state : Ref[ModuleMetricsReport?] = { val: None }

///|
let current_function_state : Ref[FunctionMetrics?] = { val: None }

///|
fn ensure_module_state() -> ModuleMetricsReport {
  match module_state.val {
    Some(m) => m
    None => {
      let m = {
        schema_version: 1,
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
  match current_function_state.val {
    Some(m) => {
      ensure_module_state().functions.push(m)
      current_function_state.val = None
    }
    None => ()
  }
}

///|
pub fn reset_module(expected_functions : Int) -> Unit {
  guard enabled() else { return }
  module_state.val = Some({
    schema_version: 1,
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
    regalloc_us: 0L,
    emit_us: 0L,
    code_size: 0,
    spill_slots: 0,
    spills: 0,
    reloads: 0,
    reg_moves: 0,
    spill_to_spill: 0,
    ir_passes: [],
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
) -> Unit {
  guard enabled() else { return }
  match current_function_state.val {
    Some(m) =>
      m.ir_passes.push({
        name: pass_name,
        duration_us,
        before_insts,
        after_insts,
        changed,
        egraph_classes,
        egraph_nodes,
        egraph_rule_apps,
      })
    None => ()
  }
}

///|
pub fn record_stage_us(stage_name : String, duration_us : Int64) -> Unit {
  guard enabled() else { return }
  match current_function_state.val {
    Some(m) =>
      match stage_name {
        "optimize" => m.optimize_us = duration_us
        "lower" => m.lower_us = duration_us
        "regalloc" => m.regalloc_us = duration_us
        "emit" => m.emit_us = duration_us
        _ => ()
      }
    None => ()
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
  match current_function_state.val {
    Some(m) => {
      m.spill_slots = spill_slots
      m.spills = spills
      m.reloads = reloads
      m.reg_moves = reg_moves
      m.spill_to_spill = spill_to_spill
    }
    None => ()
  }
}

///|
pub fn finish_function(ir_insts_after : Int, code_size : Int) -> Unit {
  guard enabled() else { return }
  match current_function_state.val {
    Some(m) => {
      m.ir_insts_after = ir_insts_after
      m.code_size = code_size
      flush_current_function_if_any()
    }
    None => ()
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
