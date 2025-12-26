///|
/// Compiler configuration options
/// Only optimization level (0-3) is configurable
priv struct CompilerConfig {
  opt_level : Int // 0=none, 1=basic, 2=default, 3=aggressive
}

///|
fn CompilerConfig::default() -> CompilerConfig {
  CompilerConfig::{ opt_level: 2 }
}

///|
fn CompilerConfig::from_level(level : Int) -> CompilerConfig {
  // Clamp to valid range 0-3
  let clamped = if level < 0 { 0 } else if level > 3 { 3 } else { level }
  CompilerConfig::{ opt_level: clamped }
}

///|
/// WASM semantic configuration options
priv struct WasmConfig {
  // Memory limits
  mut max_memory_pages : Int // Maximum memory pages (64KB each), 0 = no limit
  mut max_table_size : Int // Maximum table size, 0 = no limit
  // Stack limits
  mut max_call_depth : Int // Maximum call stack depth
  // Proposal features
  mut multi_value : Bool // Multi-value returns (WASM 1.0+)
  mut bulk_memory : Bool // Bulk memory operations
  mut reference_types : Bool // Reference types
  mut simd : Bool // SIMD (v128)
  mut tail_call : Bool // Tail call optimization
}

///|
fn WasmConfig::default() -> WasmConfig {
  WasmConfig::{
    max_memory_pages: 0, // No limit
    max_table_size: 0, // No limit
    max_call_depth: 1000,
    multi_value: true,
    bulk_memory: true,
    reference_types: true,
    simd: false,
    tail_call: false,
  }
}

///|
fn WasmConfig::apply_flag(self : WasmConfig, flag : String) -> Unit {
  let parts = flag.split("=").collect()
  if parts.length() != 2 {
    return
  }
  let key = parts[0]
  let value = parts[1]
  match key {
    "max-memory" =>
      self.max_memory_pages = @strconv.parse_int(value) catch { _ => 0 }
    "max-table" =>
      self.max_table_size = @strconv.parse_int(value) catch { _ => 0 }
    "max-call-depth" =>
      self.max_call_depth = @strconv.parse_int(value) catch { _ => 1000 }
    "multi-value" => self.multi_value = value == "true" || value == "1"
    "bulk-memory" => self.bulk_memory = value == "true" || value == "1"
    "reference-types" => self.reference_types = value == "true" || value == "1"
    "simd" => self.simd = value == "true" || value == "1"
    "tail-call" => self.tail_call = value == "true" || value == "1"
    _ => ()
  }
}

///|
/// Config file path
fn get_config_path() -> String {
  // Use XDG_CONFIG_HOME or default to ~/.config
  // For simplicity, we use a fixed path
  ".wasmoon/config"
}

///|
/// Run config command
fn run_config(action : String) -> Unit {
  match action {
    "show" => {
      println("Wasmoon Configuration")
      println("=".repeat(50))
      println("")
      println("Config file path: \{get_config_path()}")
      println("")
      println("Default settings:")
      println("  optimization_level = 2")
      println("  target = \"aarch64\"")
      println("")
      println("Use 'wasmoon config init' to create a config file.")
    }
    "path" => println(get_config_path())
    "init" => {
      println("Config file would be created at: \{get_config_path()}")
      println("")
      println("Example config file format:")
      println("")
      println("# Wasmoon configuration file")
      println("[optimization]")
      println("level = 2  # 0=none, 1=basic, 2=default, 3=aggressive")
      println("")
      println("Note: Config file support is currently read-only.")
      println("Use command-line flags for full control.")
    }
    _ => {
      println("Unknown config action: \{action}")
      println("Available actions: show, path, init")
    }
  }
}
