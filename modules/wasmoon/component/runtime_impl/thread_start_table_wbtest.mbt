///|
test "indirect thread start resolves and checks the selected table entry" {
  for empty in [false, true] {
    let source =
      #|(component
      #|  (core module $T
      #|    (table (export "t0") 1 funcref)
      #|    (table (export "t1") 1 funcref)
      #|    (func $worker (param i32))
      #|    (elem (table 0) (i32.const 0) func $worker))
      #|  (core instance $t (instantiate $T))
      #|  (core type $start (func (param i32)))
      #|  (core func $new (canon thread.new-indirect $start (core table $t "TABLE")))
      #|  (core module $M
      #|    (import "" "new" (func $new (param i32 i32) (result i32)))
      #|    (func (export "run") (result i32) i32.const 0 i32.const 42 call $new i32.eqz))
      #|  (core instance $m (instantiate $M (with "" (instance (export "new" (func $new))))))
      #|  (func (export "run") async (result u32) (canon lift (core func $m "run"))))
    let source = source.replace_all(
      old="TABLE",
      new=if empty { "t1" } else { "t0" },
    )
    let component = @component.parse_component(
      @component_text.parse_component_wat(source),
    )
    let validated = @component_validator.validate_component_for_instantiation_with_config(
      component,
      ComponentValidationConfig(false),
    )
    let linker = ComponentLinker::ComponentLinker()
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    if empty {
      let error = try {
        instance.call_exported_func("run", []) |> ignore
        "unexpected return"
      } catch {
        error => canon_err_message(error)
      }
      inspect(error, content="uninitialized element")
    } else {
      debug_inspect(instance.call_exported_func("run", []), content="[U32(0)]")
    }
  }
}
