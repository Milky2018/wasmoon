///|
test "future drops reject unknown handles and the opposite endpoint" {
  for readable in [true, false] {
    for unknown in [true, false] {
      let source =
        #|(component
        #|  (type $f (future))
        #|  (core func $new (canon future.new $f))
        #|  (core func $drop (canon future.drop-END $f))
        #|  (core module $M
        #|    (import "" "new" (func $new (result i64)))
        #|    (import "" "drop" (func $drop (param i32)))
        #|    (func (export "run")
        #|      HANDLE call $drop))
        #|  (core instance $m (instantiate $M (with "" (instance
        #|    (export "new" (func $new)) (export "drop" (func $drop))))))
        #|  (func (export "run") (canon lift (core func $m "run"))))
      let source = source
        .replace_all(
          old="END",
          new=if readable { "readable" } else { "writable" },
        )
        .replace_all(
          old="HANDLE",
          new=if unknown {
            "i32.const 42"
          } else if readable {
            "call $new i64.const 32 i64.shr_u i32.wrap_i64"
          } else {
            "call $new i32.wrap_i64"
          },
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
      let error = try {
        instance.call_exported_func("run", []) |> ignore
        "unexpected return"
      } catch {
        error => canon_err_message(error)
      }
      inspect(
        error,
        content=if unknown {
          "unknown future handle index 42"
        } else {
          "type mismatch"
        },
      )
    }
  }
}
