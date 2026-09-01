///|
fn write_usage(message : String) -> Unit {
  for line in message.split("\n") {
    @logger.plain_error(line.to_owned())
  }
}

///|
fn build_command() -> @argparse.Command {
  let required = @argparse.ValueRange::single()
  Command(
    "wasmoon-tools",
    about="WebAssembly Utility Tools",
    subcommand_required=true,
    subcommands=[
      Command("validate", about="Validate a WebAssembly module", positionals=[
        PositionArg("file", about="Path to WASM or WAT file", num_args=required),
      ]),
      Command(
        "wit",
        about="Parse and resolve WIT packages and print as normalized text/JSON",
        positionals=[
          PositionArg(
            "input",
            about="Input .wit file or a directory containing .wit files",
            num_args=ValueRange(lower=0, upper=1),
          ),
        ],
        options=[
          OptionArg("output", short='o', about="Output file (default: stdout)"),
          OptionArg(
            "out-dir",
            about="Emit the resolved WIT graph to this directory (writes root + deps/*.wit)",
          ),
          OptionArg(
            "importize-world",
            about="Generate a WIT world that imports the exports of the selected world in a WIT package",
          ),
          OptionArg(
            "importize-out-world-name",
            about="Name of the generated world for --importize/--importize-world",
          ),
        ],
        flags=[
          FlagArg("json", short='j', about="Emit JSON AST instead of WIT"),
          FlagArg(
            "no-docs",
            about="Do not include doc comments when emitting WIT text (currently a no-op)",
          ),
          FlagArg(
            "skip-validation",
            about="Skip validation when emitting --wasm/--wat (currently a no-op)",
          ),
          FlagArg(
            "wasm",
            short='w',
            about="Emit a WebAssembly Component binary instead of WIT text",
          ),
          FlagArg(
            "wat",
            short='t',
            about="Emit a WebAssembly Component text format instead of WIT text",
          ),
          FlagArg(
            "importize",
            about="Generate a WIT world that imports the exports of the input component (.wasm)",
          ),
        ],
      ),
      Command(
        "wasm2wat",
        about="Convert WASM binary to WAT text format",
        positionals=[
          PositionArg("file", about="Path to WASM file", num_args=required),
        ],
        options=[
          OptionArg("output", short='o', about="Output file (default: stdout)"),
        ],
      ),
      Command(
        "wat2wasm",
        about="Convert WAT text to WASM binary format",
        positionals=[
          PositionArg("file", about="Path to WAT file", num_args=required),
        ],
        options=[
          OptionArg(
            "output",
            short='o',
            about="Output file (default: input.wasm)",
          ),
        ],
      ),
    ],
  )
}

///|
fn match_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value]) => Some(value)
    None => None
    _ => abort("argparse returned multiple values for \{name}")
  }
}

///|
fn match_flag(matches : @argparse.Matches, name : String) -> Bool {
  matches.flags.get(name) is Some(true)
}

///|
fn main {
  let command = build_command()
  let argv = @env.args()[1:]
  if argv.length() == 0 {
    println(command.render_help())
    return
  }
  let matches = command.parse(argv~) catch {
    err => {
      write_usage(err.to_string())
      @sys.exit(2)
      return
    }
  }
  match matches.subcommand {
    Some(("validate", sub)) => cmd_validate(sub.values["file"][0])
    Some(("wit", sub)) =>
      cmd_wit(
        match_value(sub, "input"),
        match_value(sub, "output"),
        match_value(sub, "out-dir"),
        match_flag(sub, "json"),
        match_flag(sub, "no-docs"),
        match_flag(sub, "skip-validation"),
        match_flag(sub, "wasm"),
        match_flag(sub, "wat"),
        match_flag(sub, "importize"),
        match_value(sub, "importize-world"),
        match_value(sub, "importize-out-world-name"),
      )
    Some(("wasm2wat", sub)) =>
      cmd_wasm2wat(sub.values["file"][0], match_value(sub, "output"))
    Some(("wat2wasm", sub)) =>
      cmd_wat2wasm(sub.values["file"][0], match_value(sub, "output"))
    Some((name, _)) => abort("invalid argparse matches for \{name}")
    None => abort("argparse omitted the required subcommand")
  }
}

///|
fn exit_error(msg : String) -> Unit {
  // Diagnostics go to stderr so `wasm2wat` in stdout mode never mixes an
  // error into the WAT it emits (ISS-376).
  @logger.error(msg)
  @sys.exit(1)
}

///|
fn read_file(path : String) -> Bytes {
  @fs.read_file_to_bytes(path) catch {
    IOError(message) => {
      exit_error("reading file '\{path}': \{message}")
      panic() // unreachable
    }
  }
}

///|
fn write_text_file(path : String, content : String) -> Unit {
  @fs.write_string_to_file(path, content) catch {
    IOError(message) => exit_error("writing file '\{path}': \{message}")
  }
}

///|
fn write_bytes_file(path : String, data : Bytes) -> Unit {
  @fs.write_bytes_to_file(path, data) catch {
    IOError(message) => exit_error("writing file '\{path}': \{message}")
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
    IOError(message) => exit_error("writing file '\{path}': \{message}")
  }
}

///|
fn read_text_file(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    IOError(message) => {
      exit_error("reading file '\{path}': \{message}")
      panic()
    }
  }
}

///|
fn parse_module(path : String) -> @types.Module {
  // Check if it's WAT (text) or WASM (binary)
  if path.has_suffix(".wat") || path.has_suffix(".wast") {
    let text = read_text_file(path)
    @core_wat.parse(text) catch {
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
  _no_docs : Bool,
  _skip_validation : Bool,
  as_wasm : Bool,
  as_wat : Bool,
  importize : Bool,
  importize_world : String?,
  importize_out_world_name : String?,
) -> Unit {
  // Currently `no-docs` / `skip-validation` are accepted for CLI parity but are
  // no-ops (wasmoon's WIT parser does not preserve docs, and validation happens
  // during resolve/encode).
  let input_opt2 : String? = match input_opt {
    Some(p) => if p == "-" { None } else { Some(p) }
    None => None
  }
  let input = input_opt2.unwrap_or("")

  // Read stdin as a single-document WIT package when no input path is provided.
  if input_opt2 is None {
    if out_dir_opt is Some(_) {
      exit_error("cannot use --out-dir when reading WIT from stdin")
      panic()
    }
    if importize || importize_world is Some(_) {
      exit_error(
        "`--importize*` requires a file input (component .wasm or WIT package)",
      )
      panic()
    }
    let src = read_stdin_all_text()
    let root = @wit.parse_package(src) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
    let res = @wit.resolve_package(root, []) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
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
    return
  }

  // Extract WIT from a wasm-encoded component package.
  if input.has_suffix(".wasm") && !is_dir(input) {
    if as_wasm || as_wat {
      exit_error(
        "cannot use --wasm/--wat when the input is already a .wasm component",
      )
      panic()
    }
    if out_dir_opt is Some(_) {
      exit_error("cannot use --out-dir when the input is a .wasm component")
      panic()
    }
    let bytes = read_file(input)
    let pkg = @wit.decode_wit_package_from_component(bytes) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
    let pkg2 = if importize {
      @wit.importize_first_world_in_package(
        pkg,
        out_world_name=importize_out_world_name,
      ) catch {
        e => {
          exit_error(e.to_string())
          panic()
        }
      }
    } else if importize_world is Some(_) {
      exit_error(
        "use --importize (not --importize-world) with a component .wasm input",
      )
      panic()
    } else {
      pkg
    }
    let out = if as_json {
      @wit.package_to_json(pkg2)
    } else {
      @wit.format_package(pkg2)
    }
    match output_opt {
      Some(path) => write_text_file(path, out)
      None => println(out)
    }
    return
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
    if importize || importize_world is Some(_) {
      exit_error("cannot use `--importize*` with --wasm/--wat")
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
    if importize || importize_world is Some(_) {
      exit_error("cannot use `--importize*` with --out-dir")
      panic()
    }
    write_wit_out_dir(out_dir, res, as_json)
    return
  }
  let pkg_for_print : @wit.Package = if importize {
    exit_error("use --importize-world with a WIT package input")
    panic()
  } else if importize_world is Some(wname) {
    @wit.importize_resolved_package(
      res,
      wname,
      out_world_name=importize_out_world_name,
    ) catch {
      e => {
        exit_error(e.to_string())
        panic()
      }
    }
  } else {
    {
      name: res.root.name,
      version: res.root.version,
      items: res.root.items,
      nested: res.deps,
    }
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
fn read_stdin_all_bytes() -> Bytes {
  let out : Array[Byte] = []
  let buf = FixedArray::make(4096, b'\x00')
  while true {
    match @wasi.native_read(0, buf, 4096) {
      Some(n) if n > 0 =>
        for i in 0..<n {
          out.push(buf[i])
        }
      _ => break
    }
  }
  Bytes::from_array(out)
}

///|
fn read_stdin_all_text() -> String {
  let bytes = read_stdin_all_bytes()
  // WIT inputs are assumed ASCII/UTF-8; this matches existing parser usage.
  let sb = StringBuilder::StringBuilder()
  for i in 0..<bytes.length() {
    sb.write_char(bytes[i].to_int().unsafe_to_char())
  }
  sb.to_string()
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
    IOError(message) => {
      exit_error(message)
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
    IOError(message) => {
      exit_error(message)
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
    IOError(message) => {
      exit_error(message)
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
      IOError(message) => {
        exit_error(message)
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
      IOError(message) => {
        exit_error(message)
        panic()
      }
    }
  }

  // wasm-tools writes deps first, then root. We'll do the same.
  let used : Map[String, Bool] = Map([])
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
  let sb = StringBuilder::StringBuilder()
  let mut i = start
  while i < end && i < s.length() {
    sb.write_char(s.code_unit_at(i).to_int().unsafe_to_char())
    i = i + 1
  }
  sb.to_string()
}
