///|
/// Disassemble a WASM or WAT file
pub fn run_disasm(wasm_path : String) -> Unit {
  let mod_ = load_module_from_path(wasm_path) catch {
    e => {
      println("Error: \{e}")
      return
    }
  }
  let output = @disasm.disassemble(mod_)
  println(output)
}
