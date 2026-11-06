///|
test "core module import type checks use the complete name pair" {
  let component = @component_validator.validate_component_for_instantiation(
    @component.parse_component(
      @component_text.parse_component_wat(
        (
          #|(component
          #|  (core type $t (module
          #|    (type (func (result i32)))
          #|    (type (func (result i64)))
          #|    (import "a::b" "c" (func (type 0)))
          #|    (import "a" "b::c" (func (type 1)))))
          #|  (import "m" (core module (type $t))))
        ),
      ),
    ),
  )
  let accepted = []
  for result in [@types.ValueType::I32, I64] {
    let module_ = @types.Module::empty()
    module_.types.push(
      @types.func_types_to_subtypes([{ params: [], results: [result], }])[0],
    )
    module_.imports.push({ mod_name: "a::b", name: "c", desc: Func(0), })
    let linker = ComponentLinker()
    defer linker.close()
    linker.add_core_module("m", module_)
    let actual = try {
      linker.instantiate("root", component) |> ignore
      true
    } catch {
      ImportTypeMismatch(_) => false
      error => fail(error.to_string())
    }
    accepted.push(actual)
  }
  debug_inspect(accepted, content="[true, false]")
}

///|
test "each actual core import is checked even when names repeat" {
  let component = @component_validator.validate_component_for_instantiation(
    @component.parse_component(
      @component_text.parse_component_wat(
        (
          #|(component
          #|  (core type $t (module
          #|    (type (func (result i32)))
          #|    (import "a" "f" (func (type 0)))))
          #|  (import "m" (core module (type $t))))
        ),
      ),
    ),
  )
  let module_ = @types.Module::empty()
  for
    ty in @types.func_types_to_subtypes([
      { params: [], results: [I32], },
      { params: [], results: [I64], },
    ]) {
    module_.types.push(ty)
  }
  module_.imports.push({ mod_name: "a", name: "f", desc: Func(0), })
  module_.imports.push({ mod_name: "a", name: "f", desc: Func(1), })
  let linker = ComponentLinker()
  defer linker.close()
  linker.add_core_module("m", module_)
  try linker.instantiate("root", component) catch {
    ImportTypeMismatch(_) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("a repeated import hid its incompatible signature")
  }
}
