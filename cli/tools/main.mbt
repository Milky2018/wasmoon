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
        help="Parse and resolve WIT packages and print as normalized text/JSON",
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
          "out-dir": @clap.Arg::named(
            nargs=@clap.Nargs::AtMost(1),
            help="Emit the resolved WIT graph to this directory (writes root + deps/*.wit)",
          ),
          "json": @clap.Arg::flag(
            short='j',
            help="Emit JSON AST instead of WIT",
          ),
          "wasm": @clap.Arg::flag(
            short='w',
            help="Emit a WebAssembly Component binary instead of WIT text",
          ),
          "wat": @clap.Arg::flag(
            short='t',
            help="Emit a WebAssembly Component text format instead of WIT text",
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
              let out_dir_opt : String? = match sub.args.get("out-dir") {
                Some(arr) => if arr.length() > 0 { Some(arr[0]) } else { None }
                None => None
              }
              let as_json = sub.flags.get("json") is Some(true)
              let as_wasm = sub.flags.get("wasm") is Some(true)
              let as_wat = sub.flags.get("wat") is Some(true)
              cmd_wit(
                input_opt, output_opt, out_dir_opt, as_json, as_wasm, as_wat,
              )
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
fn write_bytes_file(path : String, data : Bytes) -> Unit {
  @fs.write_bytes_to_file(path, data) catch {
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
fn cmd_wit(
  input_opt : String?,
  output_opt : String?,
  out_dir_opt : String?,
  as_json : Bool,
  as_wasm : Bool,
  as_wat : Bool,
) -> Unit {
  let input = match input_opt {
    Some(p) => p
    None => {
      exit_error("missing input (.wit file or directory)")
      panic()
    }
  }
  let (root, deps) = if is_dir(input) {
    let root = read_wit_dir(input)
    let deps = read_wit_deps(input)
    (root, deps)
  } else {
    let src = read_text_file(input)
    let root = @wit.parse_package(src) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
    (root, [])
  }
  let res = @wit.resolve_package(root, deps) catch {
    e => {
      exit_error(e.to_string())
      panic()
    }
  }
  let mut format_count = 0
  if as_json {
    format_count = format_count + 1
  }
  if as_wasm {
    format_count = format_count + 1
  }
  if as_wat {
    format_count = format_count + 1
  }
  if format_count > 1 {
    exit_error("at most one of --json/--wasm/--wat can be specified")
    panic()
  }
  if as_wasm || as_wat {
    if out_dir_opt is Some(_) {
      exit_error("cannot use --out-dir with --wasm/--wat")
      panic()
    }
    if as_wasm {
      let out_path = match output_opt {
        Some(p) => p
        None => {
          exit_error("--wasm requires -o/--output")
          panic()
        }
      }
      let bytes = @wit.encode_wit_component_wasm(res) catch {
        e => {
          exit_error(e.to_string())
          panic()
        }
      }
      write_bytes_file(out_path, bytes)
      return
    }
    // --wat (text)
    let text = @wit.format_wit_component_wat(res) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
    match output_opt {
      Some(path) => write_text_file(path, text)
      None => println(text)
    }
    return
  }
  if out_dir_opt is Some(out_dir) {
    if output_opt is Some(_) {
      exit_error("cannot use -o with --out-dir")
      panic()
    }
    write_wit_out_dir(out_dir, res, as_json)
    return
  }
  let pkg_for_print : @wit.Package = {
    name: res.root.name,
    version: res.root.version,
    items: res.root.items,
    nested: res.deps,
  }
  let out = if as_json {
    @wit.package_to_json(pkg_for_print)
  } else {
    @wit.format_package(pkg_for_print)
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
  let docs : Array[@wit.Package] = []
  for f in wit_files {
    let full = if path.has_suffix("/") { path + f } else { path + "/" + f }
    let src = read_text_file(full)
    let pkg = @wit.parse_package(src) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
    docs.push(pkg)
  }
  let pkg = @wit.merge_package_files(docs) catch {
    e => {
      exit_error(e.to_string())
      panic()
    }
  }
  if pkg.name is None {
    exit_error("no `package` header was found in any WIT file for this package")
    panic()
  }
  pkg
}

///|
fn read_wit_deps(root : String) -> Array[@wit.Package] {
  let deps_dir = if root.has_suffix("/") {
    root + "deps"
  } else {
    root + "/deps"
  }
  if !@fs.path_exists(deps_dir) {
    return []
  }
  if !is_dir(deps_dir) {
    return []
  }
  let entries = @fs.read_dir(deps_dir) catch {
    e => {
      exit_error(e.to_string())
      panic()
    }
  }
  entries.sort()
  let pkgs : Array[@wit.Package] = []
  for ent in entries {
    let full = if deps_dir.has_suffix("/") {
      deps_dir + ent
    } else {
      deps_dir + "/" + ent
    }
    if is_dir(full) {
      let pkg = read_wit_dir_allow_missing_package(full)
      if pkg.name is None {
        exit_error("dependency package missing `package` header: '\{full}'")
        panic()
      }
      pkgs.push(pkg)
    } else if ent.has_suffix(".wit") {
      let src = read_text_file(full)
      let pkg = @wit.parse_package(src) catch {
        e => {
          exit_error(e.to_string())
          panic()
        }
      }
      if pkg.name is None {
        exit_error(
          "dependency WIT file missing `package` declaration: '\{full}'",
        )
        panic()
      }
      pkgs.push(pkg)
    }
  }
  pkgs
}

///|
fn read_wit_dir_allow_missing_package(path : String) -> @wit.Package {
  // Like read_wit_dir(), but used for deps entries where the container name is arbitrary.
  // The WIT files themselves must still declare a `package` somewhere; this is validated later.
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
  let docs : Array[@wit.Package] = []
  for f in wit_files {
    let full = if path.has_suffix("/") { path + f } else { path + "/" + f }
    let src = read_text_file(full)
    let pkg = @wit.parse_package(src) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
    docs.push(pkg)
  }
  @wit.merge_package_files(docs) catch {
    e => {
      exit_error(e.to_string())
      panic()
    }
  }
}

///|
fn write_wit_out_dir(
  out_dir : String,
  res : @wit.ResolveResult,
  as_json : Bool,
) -> Unit {
  if @fs.path_exists(out_dir) {
    if !is_dir(out_dir) {
      exit_error("out-dir is not a directory: '\{out_dir}'")
      panic()
    }
  } else {
    @fs.create_dir(out_dir) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
  }
  let deps_dir = if out_dir.has_suffix("/") {
    out_dir + "deps"
  } else {
    out_dir + "/deps"
  }
  if @fs.path_exists(deps_dir) {
    if !is_dir(deps_dir) {
      exit_error("out-dir/deps is not a directory: '\{deps_dir}'")
      panic()
    }
  } else {
    @fs.create_dir(deps_dir) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
  }

  // wasm-tools writes deps first, then root. We'll do the same.
  let used : Map[String, Bool] = {}
  for dep in res.deps {
    let stem = unique_pkg_stem(used, dep)
    let ext = if as_json { ".json" } else { ".wit" }
    let path = deps_dir + "/" + stem + ext
    let content = if as_json {
      @wit.package_to_json(dep)
    } else {
      @wit.format_package(dep)
    }
    write_text_file(path, content)
  }
  let root_stem = unique_pkg_stem(used, res.root)
  let ext = if as_json { ".json" } else { ".wit" }
  let root_path = out_dir + "/" + root_stem + ext
  let root_content = if as_json {
    @wit.package_to_json(res.root)
  } else {
    @wit.format_package(res.root)
  }
  write_text_file(root_path, root_content)
}

///|
fn unique_pkg_stem(used : Map[String, Bool], pkg : @wit.Package) -> String {
  let base = pkg_stem(pkg)
  if used.get(base) is None {
    used.set(base, true)
    return base
  }
  match pkg.version {
    Some(v) => {
      let mut vv = v
      // Simple sanitization for filenames.
      vv = vv.replace(old=".", new="-")
      vv = vv.replace(old="+", new="-")
      vv = vv.replace(old="/", new="-")
      let s = base + "-" + vv
      used.set(s, true)
      s
    }
    None => {
      let s = base + "-dup"
      used.set(s, true)
      s
    }
  }
}

///|
fn pkg_stem(pkg : @wit.Package) -> String {
  let name = match pkg.name {
    Some(n) => n
    None => "package"
  }
  // Use the package field as the filename stem (e.g. local:demo -> demo.wit).
  let mut last_colon : Int? = None
  for i in 0..<name.length() {
    if name.code_unit_at(i).to_int() == 58 { // ':'
      last_colon = Some(i)
    }
  }
  match last_colon {
    Some(i) => slice_ascii(name, i + 1, name.length())
    None => name
  }
}

///|
fn slice_ascii(s : String, start : Int, end : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = start
  while i < end && i < s.length() {
    sb.write_char(s.code_unit_at(i).to_int().unsafe_to_char())
    i = i + 1
  }
  sb.to_string()
}
