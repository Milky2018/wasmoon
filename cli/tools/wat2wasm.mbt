///|
fn cmd_wat2wasm(file : String, output_opt : String?) -> Unit {
  // Parse WAT text
  let text = read_text_file(file)
  let _mod = @wat.parse(text) catch {
    e => {
      exit_error("parsing WAT: \{e}")
      panic()
    }
  }

  // Validate module
  @validator.validate_module(_mod) catch {
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

  // TODO: Implement binary WASM writer
  // For now, show an error message
  exit_error(
    "wat2wasm is not yet implemented: binary WASM writer needed\nOutput would be written to: \{output_path}",
  )
}
