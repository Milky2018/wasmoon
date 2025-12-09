///|
fn main {
  // Define choices for debug options
  let debug_choices = @hashset.HashSet::from_array([
    "verbose", "print-ir", "print-vcode", "print-regalloc", "trace-exec",
  ])

  // Define choices for config action
  let config_action_choices = @hashset.HashSet::from_array([
    "show", "path", "init",
  ])
  let parser = @clap.Parser::new(
    prog="wasmoon",
    description="WebAssembly Runtime in MoonBit",
    subcmds={
      "run": @clap.SubCommand::new(help="Run a WebAssembly module", args={
        "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
        "invoke": @clap.Arg::named(nargs=AtMost(1), help="Function to invoke"),
        "arg": @clap.Arg::named(
          nargs=@clap.Nargs::Any,
          help="Arguments to pass to the function (can be repeated)",
        ),
        "preload": @clap.Arg::named(
          nargs=@clap.Nargs::Any,
          help="Preload module as NAME=PATH (can be repeated)",
        ),
        "dir": @clap.Arg::named(
          nargs=@clap.Nargs::Any,
          help="Grant access to directory (HOST_DIR or HOST_DIR::GUEST_DIR)",
        ),
        "env": @clap.Arg::named(
          nargs=@clap.Nargs::Any,
          help="Pass environment variable to WASM module (NAME=VALUE)",
        ),
        "wasi": @clap.Arg::named(
          short='S',
          nargs=@clap.Nargs::Any,
          help="WASI option (e.g., inherit-env, inherit-stdin)",
        ),
        "debug": @clap.Arg::named(
          short='D',
          nargs=@clap.Nargs::Any,
          choices=debug_choices,
          help="Debug option (verbose, print-ir, print-vcode, print-regalloc, trace-exec)",
        ),
        "wasm-opt": @clap.Arg::named(
          short='W',
          nargs=@clap.Nargs::Any,
          help="WASM semantic option (e.g., max-memory=100, simd=true)",
        ),
        "no-jit": @clap.Arg::flag(
          help="Disable JIT compilation (use interpreter)",
        ),
      }),
      "compile": @clap.SubCommand::new(
        help="Compile WASM to precompiled format",
        args={
          "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
          "output": @clap.Arg::named(
            nargs=@clap.Nargs::AtMost(1),
            help="Output path (default: input.cwasm)",
          ),
          "emit-ir": @clap.Arg::named(
            nargs=@clap.Nargs::AtMost(1),
            help="Emit IR to specified path",
          ),
          "O": @clap.Arg::named(
            nargs=@clap.Nargs::AtMost(1),
            help="Optimization level (0-3, default: 2)",
          ),
          "opt": @clap.Arg::named(
            nargs=@clap.Nargs::Any,
            help="Specific optimization flag (e.g., licm=true, dce=false)",
          ),
        },
      ),
      "test": @clap.SubCommand::new(
        help="Run WebAssembly test script (.wast format)",
        args={
          "file": @clap.Arg::positional(help="Path to WAST file"),
          "no-jit": @clap.Arg::flag(
            help="Disable JIT compilation (use interpreter)",
          ),
        },
      ),
      "disasm": @clap.SubCommand::new(
        help="Disassemble WASM file to text format",
        args={ "file": @clap.Arg::positional(help="Path to WASM file") },
      ),
      "wat": @clap.SubCommand::new(help="Parse WAT file and display as text", args={
        "file": @clap.Arg::positional(help="Path to WAT file"),
      }),
      "explore": @clap.SubCommand::new(
        help="Explore WASM compilation process (WASM -> IR -> VCode)",
        args={
          "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
          "func": @clap.Arg::named(
            nargs=@clap.Nargs::AtMost(1),
            help="Function index to explore (default: 0)",
          ),
          "O": @clap.Arg::named(
            nargs=@clap.Nargs::AtMost(1),
            help="Optimization level (0-3, default: 2)",
          ),
          "html": @clap.Arg::named(
            nargs=@clap.Nargs::AtMost(1),
            help="Output HTML report to specified path",
          ),
        },
      ),
      "objdump": @clap.SubCommand::new(help="Inspect precompiled .cwasm file", args={
        "file": @clap.Arg::positional(help="Path to .cwasm file"),
      }),
      "settings": @clap.SubCommand::new(
        help="Display available compiler settings",
      ),
      "config": @clap.SubCommand::new(help="Manage configuration", args={
        "action": @clap.Arg::positional(
          choices=config_action_choices,
          help="Action: show, path, init",
        ),
      }),
      "help": @clap.SubCommand::new(help="Display help message"),
    },
  )
  let help_msg = parser.gen_help_message(["wasmoon"], {})
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(help_msg)
    return
  }
  let value = @clap.SimpleValue::new("wasmoon")
  let cli_args : Array[String] = []
  for i in 1..<args.length() {
    cli_args.push(args[i])
  }
  let subcmd_help = parser.parse(value, cli_args[:]) catch {
    e => {
      println(e)
      println(help_msg)
      return
    }
  }
  match subcmd_help {
    Some(msg) => println(msg)
    None =>
      match value.subcmd {
        Some(sub) =>
          match sub.name {
            "run" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let file_path = positional[0]
                let invoke_opt : String? = match sub.args.get("invoke") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(arr[0])
                    } else {
                      None
                    }
                  None => None
                }
                // Get function arguments from --arg option
                let func_args : Array[String] = match sub.args.get("arg") {
                  Some(arr) => arr
                  None => []
                }
                // Get debug options from -D flag
                let debug_config = DebugConfig::new()
                if sub.args.get("debug") is Some(flags) {
                  for flag in flags {
                    debug_config.apply_flag(flag)
                  }
                }
                // Check if it's a .cwasm file
                if file_path.has_suffix(".cwasm") {
                  run_cwasm(file_path, invoke_opt, func_args, debug_config)
                } else {
                  // Get preload modules from --preload option
                  let preloads : Array[String] = match sub.args.get("preload") {
                    Some(arr) => arr
                    None => []
                  }
                  // Get directory mappings from --dir option
                  let dirs : Array[String] = match sub.args.get("dir") {
                    Some(arr) => arr
                    None => []
                  }
                  // Get environment variables from --env option
                  let envs : Array[String] = match sub.args.get("env") {
                    Some(arr) => arr
                    None => []
                  }
                  // Get WASI options from -S flag
                  let wasi_options : Array[String] = match
                    sub.args.get("wasi") {
                    Some(arr) => arr
                    None => []
                  }
                  // Get WASM semantic options from -W flag
                  let wasm_config = WasmConfig::default()
                  if sub.args.get("wasm-opt") is Some(flags) {
                    for flag in flags {
                      wasm_config.apply_flag(flag)
                    }
                  }
                  // Check if JIT is disabled (default: enabled)
                  let use_jit = match sub.flags.get("no-jit") {
                    Some(true) => false
                    _ => true
                  }
                  run_wasm(
                    file_path, invoke_opt, func_args, preloads, dirs, envs, wasi_options,
                    debug_config, wasm_config, use_jit,
                  )
                }
              } else {
                println("Error: missing file argument")
              }
            }
            "compile" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let output_opt : String? = match sub.args.get("output") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(arr[0])
                    } else {
                      None
                    }
                  None => None
                }
                let emit_ir_opt : String? = match sub.args.get("emit-ir") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(arr[0])
                    } else {
                      None
                    }
                  None => None
                }
                let opt_level : Int = match sub.args.get("O") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      @strconv.parse_int(arr[0]) catch {
                        _ => 2
                      }
                    } else {
                      2
                    }
                  None => 2
                }
                let config = CompilerConfig::from_level(opt_level)
                // Apply specific optimization flags
                match sub.args.get("opt") {
                  Some(flags) =>
                    for flag in flags {
                      config.apply_flag(flag)
                    }
                  None => ()
                }
                run_compile(positional[0], output_opt, emit_ir_opt, config)
              } else {
                println("Error: missing file argument")
              }
            }
            "test" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let use_jit = match sub.flags.get("no-jit") {
                  Some(true) => false
                  _ => true
                }
                run_testsuite(positional[0], use_jit)
              } else {
                println("Error: missing file argument")
              }
            }
            "disasm" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_disasm(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "wat" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_wat(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "explore" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let func_idx : Int? = match sub.args.get("func") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(@strconv.parse_int(arr[0])) catch {
                        _ => None
                      }
                    } else {
                      None
                    }
                  None => None
                }
                let opt_level : Int = match sub.args.get("O") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      @strconv.parse_int(arr[0]) catch {
                        _ => 2
                      }
                    } else {
                      2
                    }
                  None => 2
                }
                let html_output : String? = match sub.args.get("html") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(arr[0])
                    } else {
                      None
                    }
                  None => None
                }
                run_explore(positional[0], func_idx, opt_level, html_output)
              } else {
                println("Error: missing file argument")
              }
            }
            "objdump" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_objdump(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "settings" => run_settings()
            "config" => {
              let positional = sub.positional_args
              let action = if positional.length() > 0 {
                positional[0]
              } else {
                "show"
              }
              run_config(action)
            }
            "help" => println(help_msg)
            name => println("Unknown command: \{name}")
          }
        None => println("Error: no command")
      }
  }
}
