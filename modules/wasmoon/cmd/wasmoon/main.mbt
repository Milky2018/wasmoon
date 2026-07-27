///|
fn clap_parser(
  prog~ : String,
  description~ : String,
  subcmds~ : Map[String, @clap.SubCommand],
) -> @clap.Parser {
  { prog, args: Map([]), subcmds, description }
}

///|
fn clap_subcommand(
  help~ : String,
  args? : Map[String, @clap.Arg] = Map([]),
  subcmds? : Map[String, @clap.SubCommand] = Map([]),
) -> @clap.SubCommand {
  { args, subcmds, help }
}

///|
fn clap_simple_value(name : String) -> @clap.SimpleValue {
  {
    name,
    args: HashMap([]),
    flags: HashMap([]),
    positional_args: [],
    subcmd: None,
  }
}

///|
fn main {
  // Define choices for explore stages
  let stage_choices = @hashset.HashSet::from_array([
    "source", "ir", "opt-ir", "machv", "vcode", "allocated-vcode", "regalloc", "code-object",
    "mc", "milkir", "opt-milkir", "machv-mc",
  ])

  // Define choices for config action
  let config_action_choices = @hashset.HashSet::from_array([
    "show", "path", "init",
  ])
  let error_format_choices = @hashset.HashSet::from_array(["text", "json"])
  let parser = clap_parser(
    prog="wasmoon",
    description="WebAssembly Runtime in MoonBit",
    subcmds={
      "run": clap_subcommand(help="Run a WebAssembly module", args={
        "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
        "invoke": @clap.Arg::named(nargs=AtMost(1), help="Function to invoke"),
        "arg": @clap.Arg::named(
          nargs=Any,
          help="Arguments to pass to the function (can be repeated)",
        ),
        "preload": @clap.Arg::named(
          nargs=Any,
          help="Preload module as NAME=PATH (can be repeated)",
        ),
        "dir": @clap.Arg::named(
          nargs=Any,
          help="Grant access to directory (HOST_DIR or HOST_DIR::GUEST_DIR)",
        ),
        "env": @clap.Arg::named(
          nargs=Any,
          help="Pass environment variable to WASM module (NAME=VALUE)",
        ),
        "wasi": @clap.Arg::named(
          short='S',
          nargs=Any,
          help="WASI option (e.g., inherit-env, inherit-stdin)",
        ),
        "debug": @clap.Arg::flag(short='D', help="Enable debug output"),
        "dump-on-trap": @clap.Arg::flag(
          help="On JIT trap, dump IR/MachV/MC for the failing function",
        ),
        "dwarf": @clap.Arg::flag(
          short='W',
          help="Generate DWARF debug info for JIT code (enables LLDB stack traces)",
        ),
        "no-jit": @clap.Arg::flag(
          help="Disable JIT compilation (use interpreter)",
        ),
      }),
      "test": clap_subcommand(
        help="Run WebAssembly test script (.wast format)",
        args={
          "file": @clap.Arg::positional(help="Path to WAST file"),
          "no-jit": @clap.Arg::flag(
            help="Disable JIT compilation (use interpreter)",
          ),
          "show-success": @clap.Arg::flag(
            help="Print successful assertions (default: only print failures)",
          ),
        },
      ),
      "disasm": clap_subcommand(help="Disassemble WASM file to text format", args={
        "file": @clap.Arg::positional(help="Path to WASM file"),
      }),
      "component": clap_subcommand(
        help="Parse a WebAssembly component and print a summary",
        args={
          "file": @clap.Arg::positional(help="Path to component file"),
          "dump": @clap.Arg::flag(help="Print the parsed component structure"),
          "validate": @clap.Arg::flag(
            help="Validate the component after parsing",
          ),
          "run": @clap.Arg::flag(
            help="Run a pinned WASI Preview 2 or Preview 3 command component",
          ),
          "arg": @clap.Arg::named(
            nargs=Any,
            help="Command arguments passed after the component path",
          ),
          "env": @clap.Arg::named(
            nargs=Any,
            help="Command environment entry in NAME=VALUE form",
          ),
          "dir": @clap.Arg::named(
            nargs=Any,
            help="Preopen HOST_DIR or HOST_DIR::GUEST_DIR",
          ),
          "network": @clap.Arg::named(
            nargs=AtMost(1),
            choices=@hashset.HashSet::from_array(["deny", "loopback", "all"]),
            help="Network capability: deny (default), loopback, or all",
          ),
          "no-wit-names": @clap.Arg::flag(
            help="Disable wasm-tools/WIT name validation (kebab-case/package-name checks)",
          ),
          "error-format": @clap.Arg::named(
            nargs=AtMost(1),
            choices=error_format_choices,
            help="Component command output format: text (default) or json",
          ),
        },
      ),
      "component-test": clap_subcommand(
        help="Run component-model test script (JSON)",
        args={
          "file": @clap.Arg::positional(help="Path to component test script"),
          "error-format": @clap.Arg::named(
            nargs=AtMost(1),
            choices=error_format_choices,
            help="component-test output format: text (default) or json",
          ),
        },
      ),
      "wat": clap_subcommand(help="Parse WAT file and display as text", args={
        "file": @clap.Arg::positional(help="Path to WAT file"),
      }),
      "explore": clap_subcommand(help="Explore WASM compilation process", args={
        "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
        "func": @clap.Arg::named(
          nargs=AtMost(1),
          help="Function index to explore (default: 0)",
        ),
        "stage": @clap.Arg::named(
          short='s',
          nargs=Any,
          choices=stage_choices,
          help="Stages to show: source, milkir, opt-milkir, machv, vcode, allocated-vcode, code-object, mc (default all; ir, opt-ir, regalloc, and machv-mc are aliases)",
        ),
        "html": @clap.Arg::flag(help="Output HTML report"),
        "debug": @clap.Arg::flag(short='D', help="Enable debug output"),
      }),
      "settings": clap_subcommand(help="Display available compiler settings"),
      "config": clap_subcommand(help="Manage configuration", args={
        "action": @clap.Arg::positional(
          choices=config_action_choices,
          help="Action: show, path, init",
        ),
      }),
      "help": clap_subcommand(help="Display help message"),
    },
  )
  let help_msg = parser.gen_help_message(["wasmoon"], Map([]))
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(help_msg)
    return
  }
  let value = clap_simple_value("wasmoon")
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
                // Extract WASI program args (all positional args after the file)
                let wasm_args : Array[String] = if positional.length() > 1 {
                  let mut result = []
                  for i in 1..<positional.length() {
                    result = result + [positional[i]]
                  }
                  result
                } else {
                  []
                }
                let invoke_opt : String? = match sub.args.get("invoke") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(arr[0])
                    } else {
                      None
                    }
                  None => None
                }
                // CLI `run` uses balanced optimization for better steady-state runtime.
                let opt_level = 2
                // Get function arguments from --arg option (for invoked function)
                let func_args : Array[String] = match sub.args.get("arg") {
                  Some(arr) => arr
                  None => []
                }
                // Get debug flag
                let debug = sub.flags.get("debug") is Some(true)
                let dump_on_trap = sub.flags.get("dump-on-trap") is Some(true)
                let enable_dwarf = sub.flags.get("dwarf") is Some(true)
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
                // Get preload modules from --preload option
                let preloads : Array[String] = match sub.args.get("preload") {
                  Some(arr) => arr
                  None => []
                }
                // Get WASI options from -S flag
                let wasi_options : Array[String] = match sub.args.get("wasi") {
                  Some(arr) => arr
                  None => []
                }
                // Check if JIT is disabled (default: enabled)
                let use_jit = match sub.flags.get("no-jit") {
                  Some(true) => false
                  _ => true
                }
                @commands.run_wasm(
                  file_path, invoke_opt, func_args, wasm_args, preloads, dirs, envs,
                  wasi_options, debug, dump_on_trap, use_jit, opt_level, enable_dwarf,
                )
              } else {
                abort("missing file argument")
              }
            }
            "test" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let use_jit = match sub.flags.get("no-jit") {
                  Some(true) => false
                  _ => true
                }
                let show_success = sub.flags.get("show-success") is Some(true)
                @commands.run_testsuite(positional[0], use_jit, show_success)
              } else {
                println("Error: missing file argument")
              }
            }
            "disasm" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                @commands.run_disasm(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "component" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let dump = sub.flags.get("dump") is Some(true)
                let validate = sub.flags.get("validate") is Some(true)
                let run = sub.flags.get("run") is Some(true)
                let wit_names = match sub.flags.get("no-wit-names") {
                  Some(true) => false
                  _ => true
                }
                let error_format = match sub.args.get("error-format") {
                  Some(arr) =>
                    if arr.length() > 0 && arr[0] == "json" {
                      @commands.ComponentErrorFormat::Json
                    } else {
                      Text
                    }
                  None => Text
                }
                let status = if run {
                  @commands.run_wasi_component_command(
                    positional[0],
                    match sub.args.get("arg") {
                      Some(values) => values
                      None => []
                    },
                    match sub.args.get("env") {
                      Some(values) => values
                      None => []
                    },
                    match sub.args.get("dir") {
                      Some(values) => values
                      None => []
                    },
                    match sub.args.get("network") {
                      Some([value]) => value
                      _ => "deny"
                    },
                    wit_names,
                    error_format,
                  )
                } else {
                  @commands.run_component_command(
                    positional[0],
                    dump,
                    validate,
                    wit_names,
                    error_format,
                  )
                }
                if status != 0 {
                  @sys.exit(status)
                }
              } else {
                println("Error: missing file argument")
              }
            }
            "component-test" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let error_format = match sub.args.get("error-format") {
                  Some(arr) =>
                    if arr.length() > 0 && arr[0] == "json" {
                      @commands.ComponentErrorFormat::Json
                    } else {
                      Text
                    }
                  None => Text
                }
                let status = @commands.run_component_script_cli(
                  positional[0],
                  error_format,
                )
                if status != 0 {
                  @sys.exit(status)
                }
              } else {
                println("Error: missing file argument")
              }
            }
            "wat" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                @commands.run_wat(positional[0])
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
                      Some(@string.parse_int(arr[0])) catch {
                        _ => None
                      }
                    } else {
                      None
                    }
                  None => None
                }
                let opt_level = 2
                let stages : Array[String] = match sub.args.get("stage") {
                  Some(arr) => arr
                  None => []
                }
                let html_output = sub.flags.get("html") is Some(true)
                let debug = sub.flags.get("debug") is Some(true)
                @commands.run_explore(
                  positional[0],
                  func_idx,
                  opt_level,
                  stages,
                  html_output,
                  debug,
                )
              } else {
                println("Error: missing file argument")
              }
            }
            "settings" => @commands.run_settings()
            "config" => {
              let positional = sub.positional_args
              let action = if positional.length() > 0 {
                positional[0]
              } else {
                "show"
              }
              @commands.run_config(action)
            }
            "help" => println(help_msg)
            name => println("Unknown command: \{name}")
          }
        None => println("Error: no command")
      }
  }
}
