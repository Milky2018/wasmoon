///|
/// The version this binary reports, kept equal to `modules/wasmoon/moon.mod`
/// by `scripts/tests/test_cli_version.py`. MoonBit gives the program no way
/// to read its own module manifest, so the manifest stays the single source
/// of truth and the test is what keeps this copy from drifting.
const WASMOON_VERSION : String = "0.11.2"

///|
/// Print usage text as a diagnostic.
///
/// Usage shown after a mistake is a diagnostic, not output: it goes to
/// stderr so a redirected stdout keeps carrying data only. An explicit
/// `help` command still prints to stdout, where the user asked for it.
fn write_usage(help_msg : String) -> Unit {
  for line in help_msg.split("\n") {
    @logger.plain_error(line.to_owned())
  }
}

///|
/// Reject a value outside a fixed set.
///
/// `@argparse` does not yet support choice constraints, so fixed vocabularies
/// are the only command-line validation left outside the command schema.
fn require_choice(
  label : String,
  value : String,
  allowed : Array[String],
) -> Unit {
  if !allowed.contains(value) {
    @logger.error(
      "invalid value for \{label}: '\{value}' (expected one of: \{allowed.join(", ")})",
    )
    write_usage(build_command().render_help())
    @sys.exit(2)
  }
}

///|
/// Values accepted by `explore --stage`.
let stage_choices : Array[String] = [
  "source", "ir", "opt-ir", "machv", "vcode", "allocated-vcode", "regalloc", "code-object",
  "mc", "milkir", "opt-milkir", "machv-mc",
]

///|
let target_choices : Array[String] = ["host", "x64", "aarch64"]

///|
let config_action_choices : Array[String] = ["show", "path", "init"]

///|
let error_format_choices : Array[String] = ["text", "json"]

///|
/// The command tree.
///
/// `version` is what the built-in `-V`/`--version` prints, so the flag needs
/// no handling of its own: `@argparse` writes it to stdout and exits 0.
fn build_command() -> @argparse.Command {
  let required = @argparse.ValueRange::single()
  Command(
    "wasmoon",
    about="WebAssembly Runtime in MoonBit",
    version=WASMOON_VERSION,
    subcommand_required=true,
    subcommands=[
      Command(
        "run",
        about="Run a WebAssembly module",
        positionals=[
          PositionArg(
            "file",
            about="Path to WASM or WAT file",
            num_args=required,
          ),
          PositionArg(
            "args",
            about="Arguments passed through to the module",
            num_args=ValueRange(lower=0),
            allow_hyphen_values=true,
          ),
        ],
        options=[
          OptionArg("invoke", about="Function to invoke"),
          OptionArg(
            "arg",
            action=Append,
            about="Arguments to pass to the function (can be repeated)",
            allow_hyphen_values=true,
          ),
          OptionArg(
            "preload",
            action=Append,
            about="Preload module as NAME=PATH (can be repeated)",
          ),
          OptionArg(
            "dir",
            action=Append,
            about="Grant access to directory (HOST_DIR or HOST_DIR::GUEST_DIR)",
          ),
          OptionArg(
            "env",
            action=Append,
            about="Pass environment variable to WASM module (NAME=VALUE)",
          ),
          OptionArg(
            "wasi",
            short='S',
            action=Append,
            about="WASI option (e.g., inherit-env, inherit-stdin)",
          ),
        ],
        flags=[
          FlagArg("debug", short='D', about="Enable debug output"),
          FlagArg(
            "dump-on-trap",
            about="On JIT trap, dump IR/MachV/MC for the failing function",
          ),
          FlagArg(
            "dwarf",
            short='W',
            about="Generate DWARF debug info for JIT code (enables LLDB stack traces)",
          ),
          FlagArg("no-jit", about="Disable JIT compilation (use interpreter)"),
        ],
      ),
      Command(
        "test",
        about="Run WebAssembly test script (.wast format)",
        positionals=[
          PositionArg("file", about="Path to WAST file", num_args=required),
        ],
        flags=[
          FlagArg("no-jit", about="Disable JIT compilation (use interpreter)"),
          FlagArg(
            "show-success",
            about="Print successful assertions (default: only print failures)",
          ),
        ],
      ),
      Command("disasm", about="Disassemble a WASM or WAT file to text format", positionals=[
        PositionArg("file", about="Path to WASM or WAT file", num_args=required),
      ]),
      Command(
        "component",
        about="Parse a WebAssembly component and print a summary",
        positionals=[
          PositionArg("file", about="Path to component file", num_args=required),
        ],
        options=[
          OptionArg(
            "invoke",
            about="Invoke export or interface#function with typed JSON arguments",
          ),
          OptionArg(
            "arg",
            action=Append,
            about="Command strings for --run or typed JSON values for --invoke",
            allow_hyphen_values=true,
          ),
          OptionArg(
            "env",
            action=Append,
            about="Command environment entry in NAME=VALUE form",
            requires=["run"],
          ),
          OptionArg(
            "dir",
            action=Append,
            about="Preopen HOST_DIR or HOST_DIR::GUEST_DIR",
            requires=["run"],
          ),
          OptionArg(
            "network",
            about="Network capability: deny (default), loopback, or all",
            requires=["run"],
          ),
          OptionArg(
            "error-format",
            about="Component command output format: text (default) or json",
            default_values=["text"],
          ),
        ],
        flags=[
          FlagArg("dump", about="Print the parsed component structure"),
          FlagArg("validate", about="Validate the component after parsing"),
          FlagArg(
            "run",
            about="Run a pinned WASI Preview 2 or Preview 3 command component",
          ),
          FlagArg(
            "no-jit",
            about="Disable JIT compilation for synchronous component core functions",
            requires=["run"],
          ),
          FlagArg(
            "no-wit-names",
            about="Disable wasm-tools/WIT name validation (kebab-case/package-name checks)",
          ),
        ],
        groups=[
          ArgGroup("execution", multiple=false, args=["run", "invoke"], conflicts_with=[
            "dump", "validate",
          ]),
        ],
      ),
      Command(
        "component-test",
        about="Run component-model test script (JSON)",
        positionals=[
          PositionArg(
            "file",
            about="Path to component test script",
            num_args=required,
          ),
        ],
        options=[
          OptionArg(
            "error-format",
            about="component-test output format: text (default) or json",
            default_values=["text"],
          ),
        ],
        flags=[
          FlagArg(
            "no-jit",
            about="Use the core interpreter for all component test calls",
          ),
        ],
      ),
      Command(
        "explore",
        about="Explore WASM compilation process",
        positionals=[
          PositionArg(
            "file",
            about="Path to WASM or WAT file",
            num_args=required,
          ),
        ],
        options=[
          OptionArg(
            "func",
            about="Function index to explore (omit to explore all functions)",
            allow_hyphen_values=true,
          ),
          OptionArg(
            "stage",
            short='s',
            action=Append,
            about="Stages to show: source, milkir, opt-milkir, machv, vcode, allocated-vcode, code-object, mc (default all; ir, opt-ir, regalloc, and machv-mc are aliases)",
          ),
          OptionArg(
            "target",
            about="Native target to inspect: host, x64, aarch64 (default: host)",
            default_values=["host"],
          ),
        ],
        flags=[
          FlagArg("html", about="Output HTML report"),
          FlagArg("debug", short='D', about="Enable debug output"),
        ],
      ),
      Command("settings", about="Display available compiler settings"),
      Command("config", about="Manage configuration", positionals=[
        PositionArg("action", about="Action: show, path, init", default_values=[
          "show",
        ]),
      ]),
    ],
  )
}

///|
fn main {
  let matches = build_command().parse(argv=@env.args()[1:]) catch {
    err => {
      write_usage(err.to_string())
      @sys.exit(2)
      return
    }
  }
  let status = match matches.subcommand {
    Some(("run", sub)) =>
      @commands.run_wasm(
        sub.values["file"][0],
        sub.values.get("invoke").map(values => values[0]),
        sub.values.get("arg").unwrap_or([]),
        sub.values.get("args").unwrap_or([]),
        sub.values.get("preload").unwrap_or([]),
        sub.values.get("dir").unwrap_or([]),
        sub.values.get("env").unwrap_or([]),
        sub.values.get("wasi").unwrap_or([]),
        sub.flags.get("debug") is Some(true),
        sub.flags.get("dump-on-trap") is Some(true),
        !(sub.flags.get("no-jit") is Some(true)),
        2,
        sub.flags.get("dwarf") is Some(true),
      )
    Some(("test", sub)) =>
      @commands.run_testsuite(
        sub.values["file"][0],
        !(sub.flags.get("no-jit") is Some(true)),
        sub.flags.get("show-success") is Some(true),
      )
    Some(("disasm", sub)) => @commands.run_disasm(sub.values["file"][0])
    Some(("component", sub)) => {
      let file_path = sub.values["file"][0]
      let error_format_name = sub.values["error-format"][0]
      require_choice("--error-format", error_format_name, error_format_choices)
      let error_format : @commands.ComponentErrorFormat = if error_format_name ==
        "json" {
        Json
      } else {
        Text
      }
      let component_args = sub.values.get("arg").unwrap_or([])
      let wit_names = !(sub.flags.get("no-wit-names") is Some(true))
      if sub.values.get("invoke") is Some([export_path]) {
        @commands.run_component_invoke_command(
          file_path, export_path, component_args, wit_names, error_format,
        )
      } else if sub.flags.get("run") is Some(true) {
        let network = match sub.values.get("network") {
          Some([value]) => value
          None => "deny"
          _ => abort("argparse returned multiple values for network")
        }
        require_choice("--network", network, ["deny", "loopback", "all"])
        @commands.run_wasi_component_command(
          file_path,
          component_args,
          sub.values.get("env").unwrap_or([]),
          sub.values.get("dir").unwrap_or([]),
          network,
          wit_names,
          error_format,
          use_jit=!(sub.flags.get("no-jit") is Some(true)),
        )
      } else {
        @commands.run_component_command(
          file_path,
          sub.flags.get("dump") is Some(true),
          sub.flags.get("validate") is Some(true),
          wit_names,
          error_format,
        )
      }
    }
    Some(("component-test", sub)) => {
      let error_format_name = sub.values["error-format"][0]
      require_choice("--error-format", error_format_name, error_format_choices)
      @commands.run_component_script_cli(
        sub.values["file"][0],
        if error_format_name == "json" {
          Json
        } else {
          Text
        },
        use_jit=!(sub.flags.get("no-jit") is Some(true)),
      )
    }
    Some(("explore", sub)) => {
      let func_idx : Int? = match sub.values.get("func") {
        Some([text]) =>
          Some(@string.parse_int(text)) catch {
            _ => {
              @logger.error(
                "invalid value for --func: '\{text}' (expected an integer)",
              )
              @sys.exit(2)
              None
            }
          }
        None => None
        _ => abort("argparse returned multiple values for func")
      }
      let stages = sub.values.get("stage").unwrap_or([])
      for stage in stages {
        require_choice("--stage", stage, stage_choices)
      }
      let target_name = sub.values["target"][0]
      require_choice("--target", target_name, target_choices)
      @commands.run_explore(
        sub.values["file"][0],
        func_idx,
        2,
        stages,
        sub.flags.get("html") is Some(true),
        sub.flags.get("debug") is Some(true),
        target_name~,
      )
    }
    Some(("settings", _)) => @commands.run_settings()
    Some(("config", sub)) => {
      let action = sub.values["action"][0]
      require_choice("action", action, config_action_choices)
      @commands.run_config(action)
    }
    Some((name, _)) => abort("invalid argparse matches for \{name}")
    None => abort("argparse omitted the required subcommand")
  }
  if status != 0 {
    @sys.exit(status)
  }
}
