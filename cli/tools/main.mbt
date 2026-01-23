///|
fn main {
  let args = @sys.get_cli_args()
  let parser = @clap.Parser::new(
    prog="wasmoon-tools",
    description="WebAssembly Utility Tools",
    subcmds={
      "validate": @clap.SubCommand::new(help="Validate a WebAssembly module", args={
        "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
      }),
      "wit": @clap.SubCommand::new(
        help="Parse WIT packages and print as normalized text/JSON",
        args={
          "input": @clap.Arg::positional(
            nargs=@clap.Nargs::AtMost(1),
            help="Input .wit file or a directory containing .wit files",
          ),
          "output": @clap.Arg::named(
            short='o',
            nargs=@clap.Nargs::AtMost(1),
            help="Output file (default: stdout)",
          ),
          "json": @clap.Arg::flag(
            short='j',
            help="Emit JSON AST instead of WIT",
          ),
        },
      ),
      "wasm2wat": @clap.SubCommand::new(
        help="Convert WASM binary to WAT text format",
        args={
          "file": @clap.Arg::positional(help="Path to WASM file"),
          "output": @clap.Arg::named(
            short='o',
            nargs=@clap.Nargs::AtMost(1),
            help="Output file (default: stdout)",
          ),
        },
      ),
      "wat2wasm": @clap.SubCommand::new(
        help="Convert WAT text to WASM binary format",
        args={
          "file": @clap.Arg::positional(help="Path to WAT file"),
          "output": @clap.Arg::named(
            short='o',
            nargs=@clap.Nargs::AtMost(1),
            help="Output file (default: input.wasm)",
          ),
        },
      ),
      "help": @clap.SubCommand::new(help="Display help message"),
    },
  )
  let help_msg = parser.gen_help_message(["wasmoon-tools"], {})
  if args.length() < 2 {
    println(help_msg)
    return
  }
  let value = @clap.SimpleValue::new("wasmoon-tools")
  let cli_args : Array[String] = normalize_cli_args(args)
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
        Some(sub) => {
          let positional = sub.positional_args
          match sub.name {
            "validate" =>
              if positional.length() > 0 {
                cmd_validate(positional[0])
              } else {
                exit_error("missing file argument")
              }
            "wit" => {
              let input_opt : String? = if positional.length() > 0 {
                Some(positional[0])
              } else {
                None
              }
              let output_opt : String? = match sub.args.get("output") {
                Some(arr) => if arr.length() > 0 { Some(arr[0]) } else { None }
                None => None
              }
              let as_json = sub.flags.get("json") is Some(true)
              cmd_wit(input_opt, output_opt, as_json)
            }
            "wasm2wat" =>
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
                cmd_wasm2wat(positional[0], output_opt)
              } else {
                exit_error("missing file argument")
              }
            "wat2wasm" =>
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
                cmd_wat2wasm(positional[0], output_opt)
              } else {
                exit_error("missing file argument")
              }
            "help" => println(help_msg)
            _ => println(help_msg)
          }
        }
        None => println(help_msg)
      }
  }
}

///|
/// Support `wasmoon-tools component wit ...` as an alias for `wasmoon-tools wit ...`.
fn normalize_cli_args(args : Array[String]) -> Array[String] {
  if args.length() >= 3 && args[1] == "component" && args[2] == "wit" {
    let out : Array[String] = ["wit"]
    for i in 3..<args.length() {
      out.push(args[i])
    }
    out
  } else {
    let out : Array[String] = []
    for i in 1..<args.length() {
      out.push(args[i])
    }
    out
  }
}

///|
/// Native exit function with correct void return type
/// (moonbitlang/x/sys declares exit as returning int32, which causes a warning)
extern "c" fn native_exit(code : Int) = "exit"

///|
fn exit_error(msg : String) -> Unit {
  println("error: \{msg}")
  native_exit(1)
}

///|
fn read_file(path : String) -> Bytes {
  @fs.read_file_to_bytes(path) catch {
    e => {
      exit_error("reading file '\{path}': \{e}")
      panic() // unreachable
    }
  }
}

///|
fn write_text_file(path : String, content : String) -> Unit {
  @fs.write_string_to_file(path, content) catch {
    e => exit_error("writing file '\{path}': \{e}")
  }
}

///|
fn write_binary_file(path : String, data : Array[Int]) -> Unit {
  let byte_arr : Array[Byte] = []
  for b in data {
    byte_arr.push(b.to_byte())
  }
  let bytes = Bytes::from_array(byte_arr)
  @fs.write_bytes_to_file(path, bytes) catch {
    e => exit_error("writing file '\{path}': \{e}")
  }
}

///|
fn read_text_file(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    e => {
      exit_error("reading file '\{path}': \{e}")
      panic()
    }
  }
}

///|
fn parse_module(path : String) -> @types.Module {
  // Check if it's WAT (text) or WASM (binary)
  if path.has_suffix(".wat") || path.has_suffix(".wast") {
    let text = read_text_file(path)
    @wat.parse(text) catch {
      e => {
        exit_error("parsing WAT: \{e}")
        panic() // unreachable
      }
    }
  } else {
    let content = read_file(path)
    @parser.parse_module(content) catch {
      e => {
        exit_error("parsing WASM: \{e}")
        panic() // unreachable
      }
    }
  }
}

///|
fn cmd_wit(input_opt : String?, output_opt : String?, as_json : Bool) -> Unit {
  let input = match input_opt {
    Some(p) => p
    None => {
      exit_error("missing input (.wit file or directory)")
      panic()
    }
  }
  let pkg = if is_dir(input) {
    read_wit_dir(input)
  } else {
    let src = read_text_file(input)
    @wit.parse_package(src) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
  }
  let out = if as_json {
    @wit.package_to_json(pkg)
  } else {
    @wit.format_package(pkg)
  }
  match output_opt {
    Some(path) => write_text_file(path, out)
    None => println(out)
  }
}

///|
fn is_dir(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
fn read_wit_dir(path : String) -> @wit.Package {
  let entries = @fs.read_dir(path) catch {
    e => {
      exit_error(e.to_string())
      panic()
    }
  }
  let wit_files : Array[String] = []
  for e in entries {
    if e.has_suffix(".wit") {
      wit_files.push(e)
    }
  }
  wit_files.sort()
  if wit_files.length() == 0 {
    exit_error("no .wit files found in directory '\{path}'")
    panic()
  }
  let mut merged : @wit.Package? = None
  for f in wit_files {
    let full = if path.has_suffix("/") { path + f } else { path + "/" + f }
    let src = read_text_file(full)
    let pkg = @wit.parse_package(src) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
    merged = Some(merge_wit_packages(merged, pkg))
  }
  merged.unwrap_or({ name: None, version: None, items: [] })
}

///|
fn merge_wit_packages(acc : @wit.Package?, pkg : @wit.Package) -> @wit.Package {
  match acc {
    None => pkg
    Some(a) => {
      let name = match (a.name, pkg.name) {
        (Some(x), Some(y)) =>
          if x == y {
            Some(x)
          } else {
            exit_error("conflicting package names")
            panic()
          }
        (Some(x), None) => Some(x)
        (None, Some(y)) => Some(y)
        (None, None) => None
      }
      let version = match (a.version, pkg.version) {
        (Some(x), Some(y)) =>
          if x == y {
            Some(x)
          } else {
            exit_error("conflicting package versions")
            panic()
          }
        (Some(x), None) => Some(x)
        (None, Some(y)) => Some(y)
        (None, None) => None
      }
      let items = a.items + pkg.items
      { name, version, items }
    }
  }
}
