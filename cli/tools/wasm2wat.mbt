///|
fn cmd_wasm2wat(file : String, output_opt : String?) -> Unit {
  let content = read_file(file)

  // Parse WASM binary
  let mod_ = @parser.parse_module(content) catch {
    e => {
      exit_error("parsing WASM: \{e}")
      panic()
    }
  }

  // Convert to WAT text
  let wat_text = module_to_wat(mod_)

  // Output
  match output_opt {
    Some(output_path) => write_text_file(output_path, wat_text)
    None => println(wat_text)
  }
}
