///|
/// Disassemble a WASM file
fn run_disasm(wasm_path : String) -> Unit {
  let bytes = @fs.read_file_to_bytes(wasm_path) catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let mod_ = @parser.parse_module(bytes) catch {
    e => {
      println("Error parsing module: \{e}")
      return
    }
  }
  let output = @disasm.disassemble(mod_)
  println(output)
}
