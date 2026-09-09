///|
/// Run the unstable component-spec conformance harness without printing output.
pub fn run_component_script(
  path : String,
  error_format : ComponentErrorFormat,
  use_jit? : Bool = true,
  component_implements? : Bool = true,
) -> Int {
  @component_conformance.run_component_script(
    path,
    match error_format {
      Text => Text
      Json => Json
    },
    use_jit~,
    component_implements~,
  )
}

///|
/// Run the unstable component-spec conformance harness as a CLI command.
pub fn run_component_script_cli(
  path : String,
  error_format : ComponentErrorFormat,
  use_jit? : Bool = true,
  component_implements? : Bool = true,
) -> Int {
  @component_conformance.run_component_script_cli(
    path,
    match error_format {
      Text => Text
      Json => Json
    },
    use_jit~,
    component_implements~,
  )
}
