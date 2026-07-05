///|
fn perf_enabled() -> Bool {
  false
}

///|
fn perf_tick_now() -> Int64 {
  0L
}

///|
fn perf_elapsed_us(_tick : Int64) -> Int64 {
  0L
}

///|
fn perf_record_ir_pass(
  _pass_name : String,
  _before : Int,
  _after : Int,
  _changed : Bool,
  _duration_us : Int64,
  egraph_classes? : Int? = None,
  egraph_nodes? : Int? = None,
  egraph_rule_apps? : Int? = None,
) -> Unit {
  ignore(egraph_classes)
  ignore(egraph_nodes)
  ignore(egraph_rule_apps)
}
