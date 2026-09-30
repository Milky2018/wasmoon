///|
// Private to the command implementation: these boundaries describe run_wasm,
// not the reusable compiler's stage model. Collection never changes cache policy.
priv struct RunMetrics {
  path : String
  origin : @perf.PerfTick
  mut last_us : Int64
  phases : Map[String, Int64]
}

///|
fn begin_run_metrics() -> RunMetrics? {
  @env.get_env_var("WASMOON_RUN_METRICS_FILE").map(path => {
    path,
    origin: @perf.tick_now(),
    last_us: 0L,
    phases: {},
  })
}

///|
fn record_run_phase(metrics : RunMetrics?, name : String) -> Unit {
  if metrics is Some(m) {
    let now = @perf.elapsed_us(m.origin)
    m.phases[name] = now - m.last_us
    m.last_us = now
  }
}

///|
fn finish_run_metrics(metrics : RunMetrics?) -> Unit {
  if metrics is Some(m) {
    record_run_phase(metrics, "finish_or_early_return")
    let report : Json = {
      "schema_version": 1,
      "command_us": m.last_us.to_json(),
      "phases_us": m.phases.to_json(),
    }
    @fs.write_string_to_file(m.path, report.stringify()) catch {
      IOError(message) =>
        @logger.warn("Failed to write run metrics: \{message}")
    }
  }
}
