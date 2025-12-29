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
let debug_enabled : Ref[Bool] = { val: false }

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
/// Log a debug message (only printed if debug is enabled)
pub fn debug(msg : String) -> Unit {
  if debug_enabled.val {
    println("[DEBUG] \{msg}")
  }
}

///|
/// Log an info message
pub fn info(msg : String) -> Unit {
  println(msg)
}

///|
/// Log a warning message
pub fn warn(msg : String) -> Unit {
  println("[WARN] \{msg}")
}

///|
/// Log an error message
pub fn error(msg : String) -> Unit {
  println("Error: \{msg}")
}
