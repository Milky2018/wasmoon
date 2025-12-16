///|
/// Parse and display a WAT file
fn run_wat(wat_path : String) -> Unit {
  let content = @fs.read_file_to_string(wat_path) catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let mod_ = @wat.parse(content) catch {
    e => {
      println("Error parsing WAT: \{e}")
      return
    }
  }
  // Display parsed module using the disassembler
  let output = @disasm.disassemble(mod_)
  println("Parsed WAT module:")
  println(output)
}

///|
/// Run testsuite with a WAST file
fn run_testsuite(
  wast_path : String,
  use_jit : Bool,
  show_success : Bool,
) -> Unit {
  // Delegate to run_wast - testsuite now uses WAST format
  run_wast(wast_path, use_jit, show_success)
}
