// Logger - Simple logging utility for wasmoon

///|
/// Log level enumeration
pub(all) enum LogLevel {
  Debug
  Info
  Warn
  Error
}

///|
/// Global debug flag - when false, debug messages are suppressed
let debug_enabled : Ref[Bool] = { val: false, }

///|
/// Enable debug logging
pub fn enable_debug() -> Unit {
  debug_enabled.val = true
}

///|
/// Disable debug logging
pub fn disable_debug() -> Unit {
  debug_enabled.val = false
}

///|
/// Check if debug logging is enabled
pub fn is_debug_enabled() -> Bool {
  debug_enabled.val
}

///|
/// Log a debug message (only printed if debug is enabled).
/// Diagnostics go to stderr so redirected stdout carries data only.
pub fn debug(msg : String) -> Unit {
  if debug_enabled.val {
    write_stderr_line("[DEBUG] \{msg}")
  }
}

///|
/// Log an info message.
/// This is the one level that stays on stdout: callers use it for program
/// output, not for diagnostics.
pub fn info(msg : String) -> Unit {
  println(msg)
}

///|
/// Log a warning message (stderr).
pub fn warn(msg : String) -> Unit {
  write_stderr_line("[WARN] \{msg}")
}

///|
/// Log an error message (stderr).
pub fn error(msg : String) -> Unit {
  write_stderr_line("Error: \{msg}")
}

///|
/// Write a diagnostic line to stderr with no level prefix.
/// Used for multi-line text such as usage output, where a prefix per line
/// would be noise.
pub fn plain_error(msg : String) -> Unit {
  write_stderr_line(msg)
}
