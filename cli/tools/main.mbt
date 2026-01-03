///|
fn main {
  let parser = @clap.Parser::new(
    prog="wasmoon-tools",
    description="WebAssembly Utility Tools",
    subcmds={
      "validate": @clap.SubCommand::new(help="Validate a WebAssembly module", args={
        "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
      }),
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
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(help_msg)
    return
  }
  let value = @clap.SimpleValue::new("wasmoon-tools")
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
        Some(sub) => {
          let positional = sub.positional_args
          match sub.name {
            "validate" =>
              if positional.length() > 0 {
                cmd_validate(positional[0])
              } else {
                exit_error("missing file argument")
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
/// Native exit function with correct void return type
/// (moonbitlang/x/sys declares exit as returning int32, which causes a warning)
extern "c" fn native_exit(code : Int) -> Unit = "wasmoon_exit"

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
