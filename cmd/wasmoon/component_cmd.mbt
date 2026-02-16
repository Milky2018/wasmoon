///|
fn run_component_command(
  file_path : String,
  dump : Bool,
  validate : Bool,
  wit_names : Bool,
) -> Unit {
  let bytes = @fs.read_file_to_bytes(file_path) catch {
    IOError(_e) => {
      println("file \{file_path} not found")
      return
    }
  }
  let parsed = @component.parse_component(bytes) catch {
    e => {
      println("parse component error: \{e}")
      return
    }
  }
  if validate {
    @validator.validate_component_with_config(
      parsed,
      @validator.ComponentValidationConfig::new(wit_names),
    ) catch {
      e => {
        println("validate component error: \{e}")
        return
      }
    }
    println("component validated ok")
  }
  if dump {
    println(parsed)
    return
  }
  let has_start = match parsed.start {
    Some(_) => true
    None => false
  }
  println(
    "component version=\{parsed.binary.version} layer=\{parsed.binary.layer} sections=\{parsed.binary.sections.length()}",
  )
  println(
    "core_modules=\{parsed.core_modules.length()} core_instances=\{parsed.core_instances.length()} core_types=\{parsed.core_types.length()} nested_components=\{parsed.components.length()}",
  )
  println(
    "types=\{parsed.types.length()} imports=\{parsed.imports.length()} exports=\{parsed.exports.length()} instances=\{parsed.instances.length()} aliases=\{parsed.aliases.length()} canons=\{parsed.canons.length()} start=\{has_start}",
  )
}
