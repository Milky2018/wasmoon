///|
fn is_ascii_space(c : Char) -> Bool {
  c == ' ' || c == '\n' || c == '\r' || c == '\t'
}

///|
fn starts_with_component_form(text : String) -> Bool {
  let mut i = 0
  while i < text.length() {
    let c = text.code_unit_at(i).unsafe_to_char()
    if is_ascii_space(c) {
      i += 1
      continue
    }
    if c != '(' {
      return false
    }
    i += 1
    while i < text.length() &&
          is_ascii_space(text.code_unit_at(i).unsafe_to_char()) {
      i += 1
    }
    let keyword = StringBuilder::new()
    while i < text.length() {
      let k = text.code_unit_at(i).unsafe_to_char()
      if is_ascii_space(k) || k == ')' || k == '(' {
        break
      }
      keyword.write_char(k)
      i += 1
    }
    return keyword.to_string() == "component"
  }
  false
}

///|
fn derive_wasm_output_path(file : String) -> String {
  if file.has_suffix(".wat") {
    let sb = StringBuilder::new()
    for index in 0..<(file.length() - 4) {
      sb.write_char(file.code_unit_at(index).unsafe_to_char())
    }
    sb.write_string(".wasm")
    sb.to_string()
  } else {
    file + ".wasm"
  }
}

///|
fn cmd_wat2wasm(file : String, output_opt : String?) -> Unit {
  let text = read_text_file(file)
  let output_path = if output_opt is Some(path) {
    path
  } else {
    derive_wasm_output_path(file)
  }

  if starts_with_component_form(text) {
    let bytes = @text_parser.parse_component_wat(text) catch {
      e => {
        exit_error("parsing component WAT: \{e}")
        panic()
      }
    }
    write_bytes_file(output_path, bytes)
    println("Wrote \{bytes.length()} bytes to \{output_path}")
    return
  }

  // Parse WAT text
  let mod = @wat.parse(text) catch {
    e => {
      exit_error("parsing WAT: \{e}")
      panic()
    }
  }

  // Validate module
  @validator.validate_module(mod) catch {
    e => {
      exit_error("validation: \{@validator.format_validation_error(e)}")
      panic()
    }
  }

  // Encode module to binary format
  let bytes = @cwasm.encode(mod)

  // Write to file
  write_binary_file(output_path, bytes)
  println("Wrote \{bytes.length()} bytes to \{output_path}")
}
