///|
/// Write a line to standard error.
///
/// Non-native backends have no stderr channel of their own, so diagnostics
/// fall back to stdout there. The CLI only ships as a native binary, so the
/// stream separation that matters in a pipeline is not affected.
fn write_stderr_line(msg : String) -> Unit {
  println(msg)
}

///|
// Imports are shared with the native file, which encodes stderr as UTF-8.
let _native_encoding_import : Unit = ignore((text : String) => {
  @utf8.encode(text)
})
