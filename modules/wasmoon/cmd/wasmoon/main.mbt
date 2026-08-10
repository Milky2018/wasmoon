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
/// `@argparse` has no equivalent of the `choices` constraint the previous
/// parser carried, so the check is done here after parsing. Keeping it in
/// one place is also what stops the old behavior from coming back, where
/// the rejection text printed the raw container:
/// `choices=@hashset.from_array([regalloc, opt-milkir, ...])`.
fn require_choice(
  label : String,
  value : String,
  allowed : Array[String],
) -> Unit {
  if !allowed.contains(value) {
    usage_error(
      "invalid value for \{label}: '\{value}' (expected one of: \{allowed.join(", ")})",
    )
  }
}

///|
/// Every value collected for a repeatable option, or empty when absent.
fn values_of(matches : @argparse.Matches, name : String) -> Array[String] {
  matches.values.get(name).unwrap_or([])
}

///|
/// The single value of an option, or `None` when it was not given.
fn value_of(matches : @argparse.Matches, name : String) -> String? {
  if matches.values.get(name) is Some(values) && values.length() > 0 {
    Some(values[0])
  } else {
    None
  }
}

///|
/// Whether a flag was set.
fn flag_of(matches : @argparse.Matches, name : String) -> Bool {
  matches.flags.get(name) is Some(true)
}

///|
/// The required leading positional, or a usage error naming what is missing.
fn required_file(matches : @argparse.Matches) -> String {
  match value_of(matches, "file") {
    Some(path) => path
    None => {
      usage_error("missing file argument")
      ""
    }
  }
}

///|
/// Report a command-line mistake and exit non-zero.
///
/// Exit code 2 is the conventional "wrong usage" status, distinct from 1,
/// which commands use for a failure while doing the work.
fn usage_error(msg : String) -> Unit {
  @logger.error(msg)
  @sys.exit(2)
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
/// The `--error-format` value shared by the two component commands.
fn component_error_format(
  matches : @argparse.Matches,
) -> @commands.ComponentErrorFormat {
  match value_of(matches, "error-format") {
    Some(value) => {
      require_choice("--error-format", value, error_format_choices)
      if value == "json" {
        Json
      } else {
        Text
      }
    }
    None => Text
  }
}

///|
/// The command tree.
///
/// `version` is what the built-in `-V`/`--version` prints, so the flag needs
/// no handling of its own: `@argparse` writes it to stdout and exits 0.
fn build_command() -> @argparse.Command {
  Command(
    "wasmoon",
    about="WebAssembly Runtime in MoonBit",
    version=WASMOON_VERSION,
    disable_help_subcommand=true,
    arg_required_else_help=true,
    subcommand_required=true,
    subcommands=[
      Command(
        "run",
        about="Run a WebAssembly module",
        positionals=[
          PositionArg("file", about="Path to WASM or WAT file"),
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
        positionals=[PositionArg("file", about="Path to WAST file")],
        flags=[
          FlagArg("no-jit", about="Disable JIT compilation (use interpreter)"),
          FlagArg(
            "show-success",
            about="Print successful assertions (default: only print failures)",
          ),
        ],
      ),
      Command("disasm", about="Disassemble a WASM or WAT file to text format", positionals=[
        PositionArg("file", about="Path to WASM or WAT file"),
      ]),
      Command(
        "component",
        about="Parse a WebAssembly component and print a summary",
        positionals=[PositionArg("file", about="Path to component file")],
        options=[
          OptionArg(
            "invoke",
            about="Invoke export or interface#function with typed JSON arguments",
          ),
          OptionArg(
            "arg",
            action=Append,
            about="Command strings for --run or typed JSON values for --invoke",
          ),
          OptionArg(
            "env",
            action=Append,
            about="Command environment entry in NAME=VALUE form",
          ),
          OptionArg(
            "dir",
            action=Append,
            about="Preopen HOST_DIR or HOST_DIR::GUEST_DIR",
          ),
          OptionArg(
            "network",
            about="Network capability: deny (default), loopback, or all",
          ),
          OptionArg(
            "error-format",
            about="Component command output format: text (default) or json",
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
          ),
          FlagArg(
            "no-wit-names",
            about="Disable wasm-tools/WIT name validation (kebab-case/package-name checks)",
          ),
        ],
      ),
      Command(
        "component-test",
        about="Run component-model test script (JSON)",
        positionals=[PositionArg("file", about="Path to component test script")],
        options=[
          OptionArg(
            "error-format",
            about="component-test output format: text (default) or json",
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
        positionals=[PositionArg("file", about="Path to WASM or WAT file")],
        options=[
          OptionArg("func", about="Function index to explore (default: 0)"),
          OptionArg(
            "stage",
            short='s',
            action=Append,
            about="Stages to show: source, milkir, opt-milkir, machv, vcode, allocated-vcode, code-object, mc (default all; ir, opt-ir, regalloc, and machv-mc are aliases)",
          ),
          OptionArg(
            "target",
            about="Native target to inspect: host, x64, aarch64 (default: host)",
          ),
        ],
        flags=[
          FlagArg("html", about="Output HTML report"),
          FlagArg("debug", short='D', about="Enable debug output"),
        ],
      ),
      Command("settings", about="Display available compiler settings"),
      Command("config", about="Manage configuration", positionals=[
        PositionArg("action", about="Action: show, path, init"),
      ]),
      Command("help", about="Display help message"),
    ],
  )
}

///|
fn main {
  let command = build_command()
  let matches = command.parse(argv=@env.args()[1:]) catch {
    err => {
      write_usage(err.to_string())
      @sys.exit(2)
      return
    }
  }
  guard matches.subcommand is Some((name, sub)) else {
    usage_error("no command given")
    return
  }
  match name {
    "run" => {
      let file_path = required_file(sub)
      // CLI `run` uses balanced optimization for better steady-state runtime.
      let opt_level = 2
      @commands.run_wasm(
        file_path,
        value_of(sub, "invoke"),
        values_of(sub, "arg"),
        values_of(sub, "args"),
        values_of(sub, "preload"),
        values_of(sub, "dir"),
        values_of(sub, "env"),
        values_of(sub, "wasi"),
        flag_of(sub, "debug"),
        flag_of(sub, "dump-on-trap"),
        !flag_of(sub, "no-jit"),
        opt_level,
        flag_of(sub, "dwarf"),
      )
    }
    "test" =>
      @commands.run_testsuite(
        required_file(sub),
        !flag_of(sub, "no-jit"),
        flag_of(sub, "show-success"),
      )
    "disasm" => @commands.run_disasm(required_file(sub))
    "component" => {
      let file_path = required_file(sub)
      let error_format = component_error_format(sub)
      let invoke = value_of(sub, "invoke")
      let run = flag_of(sub, "run")
      let wit_names = !flag_of(sub, "no-wit-names")
      let component_args = values_of(sub, "arg")
      let status = if run && invoke is Some(_) {
        @commands.report_component_option_error(
          error_format, "--run and --invoke are mutually exclusive",
        )
      } else if invoke is Some(export_path) {
        @commands.run_component_invoke_command(
          file_path, export_path, component_args, wit_names, error_format,
        )
      } else if run {
        let network = match value_of(sub, "network") {
          Some(value) => {
            require_choice("--network", value, ["deny", "loopback", "all"])
            value
          }
          None => "deny"
        }
        @commands.run_wasi_component_command(
          file_path,
          component_args,
          values_of(sub, "env"),
          values_of(sub, "dir"),
          network,
          wit_names,
          error_format,
          use_jit=!flag_of(sub, "no-jit"),
        )
      } else {
        @commands.run_component_command(
          file_path,
          flag_of(sub, "dump"),
          flag_of(sub, "validate"),
          wit_names,
          error_format,
        )
      }
      if status != 0 {
        @sys.exit(status)
      }
    }
    "component-test" => {
      let status = @commands.run_component_script_cli(
        required_file(sub),
        component_error_format(sub),
        use_jit=!flag_of(sub, "no-jit"),
      )
      if status != 0 {
        @sys.exit(status)
      }
    }
    "explore" => {
      let file_path = required_file(sub)
      let func_idx : Int? = match value_of(sub, "func") {
        Some(text) => Some(@string.parse_int(text)) catch { _ => None }
        None => None
      }
      let stages = values_of(sub, "stage")
      for stage in stages {
        require_choice("--stage", stage, stage_choices)
      }
      let target_name = match value_of(sub, "target") {
        Some(value) => {
          require_choice("--target", value, target_choices)
          value
        }
        None => "host"
      }
      let opt_level = 2
      @commands.run_explore(
        file_path,
        func_idx,
        opt_level,
        stages,
        flag_of(sub, "html"),
        flag_of(sub, "debug"),
        target_name~,
      )
    }
    "settings" => @commands.run_settings()
    "config" => {
      let action = value_of(sub, "action").unwrap_or("show")
      require_choice("action", action, config_action_choices)
      @commands.run_config(action)
    }
    "help" => println(command.render_help())
    other => usage_error("unknown command: \{other}")
  }
}
