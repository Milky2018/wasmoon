///|
fn cmd_validate(file : String) -> Unit {
  let mod_ = parse_module(file)

  // Validate the module
  @validator.validate_module(mod_) catch {
    e => {
      println("\{file}: invalid")
      println(@validator.format_validation_error(e))
      native_exit(1)
    }
  }
  println("\{file}: valid")
}
