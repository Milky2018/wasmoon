///|
/// Write a line to standard error.
///
/// Non-native backends have no stderr channel of their own, so diagnostics
/// fall back to stdout there. The CLI only ships as a native binary, so the
/// stream separation that matters in a pipeline is not affected.
fn write_stderr_line(msg : String) -> Unit {
  println(msg)
}
