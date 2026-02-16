///|
fn cmd_wat2wasm(file : String, output_opt : String?) -> Unit {
  // Parse WAT text
  let text = read_text_file(file)
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

  // Determine output path
  let output_path = match output_opt {
    Some(path) => path
    None =>
      // Replace .wat extension with .wasm
      if file.has_suffix(".wat") {
        // Remove .wat suffix and add .wasm
        let sb = StringBuilder::new()
        for i in 0..<(file.length() - 4) {
          sb.write_char(file[i].to_int().unsafe_to_char())
        }
        sb.write_string(".wasm")
        sb.to_string()
      } else {
        file + ".wasm"
      }
  }

  // Encode module to binary format
  let bytes = @cwasm.encode(mod)

  // Write to file
  write_binary_file(output_path, bytes)
  println("Wrote \{bytes.length()} bytes to \{output_path}")
}
