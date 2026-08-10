///|
/// Disassemble a WASM or WAT file
pub fn run_disasm(wasm_path : String) -> Int {
  let mod_ = load_module_from_path(wasm_path) catch {
    e => {
      @logger.error("\{e}")
      return 1
    }
  }
  let output = @disasm.disassemble(mod_)
  println(output)
  0
}
