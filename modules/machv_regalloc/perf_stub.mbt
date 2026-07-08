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
fn perf_record_regalloc_phase_us(_name : String, _duration_us : Int64) -> Unit {
  ()
}
