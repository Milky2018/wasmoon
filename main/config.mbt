///|
/// Compiler configuration options
pub(all) struct CompilerConfig {
  // Optimization level (0-3)
  opt_level : Int
  // Specific optimization flags
  mut const_fold : Bool
  mut copy_prop : Bool
  mut cse : Bool
  mut dce : Bool
  mut branch_simplify : Bool
  mut unreachable_elim : Bool
  mut block_merge : Bool
  mut jump_thread : Bool
  mut licm : Bool
  mut loop_unroll : Bool
  mut strength_reduce : Bool
}

///|
fn CompilerConfig::default() -> CompilerConfig {
  // Default: O2 equivalent
  CompilerConfig::{
    opt_level: 2,
    const_fold: true,
    copy_prop: true,
    cse: true,
    dce: true,
    branch_simplify: true,
    unreachable_elim: true,
    block_merge: true,
    jump_thread: true,
    licm: false,
    loop_unroll: false,
    strength_reduce: false,
  }
}

///|
fn CompilerConfig::from_level(level : Int) -> CompilerConfig {
  match level {
    0 =>
      CompilerConfig::{
        opt_level: 0,
        const_fold: false,
        copy_prop: false,
        cse: false,
        dce: false,
        branch_simplify: false,
        unreachable_elim: false,
        block_merge: false,
        jump_thread: false,
        licm: false,
        loop_unroll: false,
        strength_reduce: false,
      }
    1 =>
      CompilerConfig::{
        opt_level: 1,
        const_fold: true,
        copy_prop: true,
        cse: true,
        dce: true,
        branch_simplify: false,
        unreachable_elim: false,
        block_merge: false,
        jump_thread: false,
        licm: false,
        loop_unroll: false,
        strength_reduce: false,
      }
    2 => CompilerConfig::default()
    _ =>
      // O3
      CompilerConfig::{
        opt_level: 3,
        const_fold: true,
        copy_prop: true,
        cse: true,
        dce: true,
        branch_simplify: true,
        unreachable_elim: true,
        block_merge: true,
        jump_thread: true,
        licm: true,
        loop_unroll: true,
        strength_reduce: true,
      }
  }
}

///|
/// Parse optimization flags from KEY=VAL format
/// Examples: "const-fold=false", "licm=true"
fn CompilerConfig::apply_flag(self : CompilerConfig, flag : String) -> Unit {
  let parts = flag.split("=").collect()
  if parts.length() != 2 {
    return
  }
  let key = parts[0]
  let value = parts[1] == "true" || parts[1] == "1"
  match key {
    "const-fold" => self.const_fold = value
    "copy-prop" => self.copy_prop = value
    "cse" => self.cse = value
    "dce" => self.dce = value
    "branch-simplify" => self.branch_simplify = value
    "unreachable-elim" => self.unreachable_elim = value
    "block-merge" => self.block_merge = value
    "jump-thread" => self.jump_thread = value
    "licm" => self.licm = value
    "loop-unroll" => self.loop_unroll = value
    "strength-reduce" => self.strength_reduce = value
    _ => ()
  }
}

///|
/// Debug configuration options
pub(all) struct DebugConfig {
  mut verbose : Bool
  mut print_ir : Bool
  mut print_vcode : Bool
  mut print_regalloc : Bool
  mut trace_exec : Bool
}

///|
fn DebugConfig::new() -> DebugConfig {
  DebugConfig::{
    verbose: false,
    print_ir: false,
    print_vcode: false,
    print_regalloc: false,
    trace_exec: false,
  }
}

///|
fn DebugConfig::apply_flag(self : DebugConfig, flag : String) -> Unit {
  let parts = flag.split("=").collect()
  if parts.length() != 2 {
    // Check for bare flags (e.g., "verbose" means "verbose=true")
    match flag {
      "verbose" => self.verbose = true
      "print-ir" => self.print_ir = true
      "print-vcode" => self.print_vcode = true
      "print-regalloc" => self.print_regalloc = true
      "trace-exec" => self.trace_exec = true
      _ => ()
    }
    return
  }
  let key = parts[0]
  let value = parts[1] == "true" || parts[1] == "1"
  match key {
    "verbose" => self.verbose = value
    "print-ir" => self.print_ir = value
    "print-vcode" => self.print_vcode = value
    "print-regalloc" => self.print_regalloc = value
    "trace-exec" => self.trace_exec = value
    _ => ()
  }
}

///|
/// WASM semantic configuration options
pub(all) struct WasmConfig {
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
fn CompilerConfig::to_string(self : CompilerConfig) -> String {
  let sb = StringBuilder::new()
  sb.write_string("CompilerConfig {\n")
  sb.write_string("  opt_level: \{self.opt_level}\n")
  sb.write_string("  const_fold: \{self.const_fold}\n")
  sb.write_string("  copy_prop: \{self.copy_prop}\n")
  sb.write_string("  cse: \{self.cse}\n")
  sb.write_string("  dce: \{self.dce}\n")
  sb.write_string("  branch_simplify: \{self.branch_simplify}\n")
  sb.write_string("  unreachable_elim: \{self.unreachable_elim}\n")
  sb.write_string("  block_merge: \{self.block_merge}\n")
  sb.write_string("  jump_thread: \{self.jump_thread}\n")
  sb.write_string("  licm: \{self.licm}\n")
  sb.write_string("  loop_unroll: \{self.loop_unroll}\n")
  sb.write_string("  strength_reduce: \{self.strength_reduce}\n")
  sb.write_string("}")
  sb.to_string()
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
      println("level = 2")
      println("const-fold = true")
      println("cse = true")
      println("dce = true")
      println("")
      println("[wasm]")
      println("max-memory = 0")
      println("max-call-depth = 1000")
      println("multi-value = true")
      println("")
      println("[debug]")
      println("verbose = false")
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
