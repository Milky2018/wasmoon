///|
test "canonical realloc uses fresh context and cannot leave its component" {
  for invalid in [false, true] {
    let source =
      #|(component
      #|  (core func $get (canon context.get i32 0))
      #|  (core func $set (canon context.set i32 0))
      #|  (core func $index (canon thread.index))
      #|  (core module $M
      #|    (import "" "get" (func $get (result i32)))
      #|    (import "" "set" (func $set (param i32)))
      #|    (import "" "index" (func $index (result i32)))
      #|    (memory (export "m") 1)
      #|    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      #|      ALLOC_BODY i32.const 32)
      #|    (func (export "run") (param i32 i32)
      #|      call $get if unreachable end i32.const 99 call $set))
      #|  (core instance $m (instantiate $M (with "" (instance
      #|    (export "get" (func $get)) (export "set" (func $set))
      #|    (export "index" (func $index))))))
      #|  (func (export "run") (param "x" string)
      #|    (canon lift (core func $m "run") (memory (core memory $m "m"))
      #|      (realloc (core func $m "realloc")))))
    let body = if invalid {
      "call $index drop"
    } else {
      "call $get if unreachable end i32.const 17 call $set"
    }
    let component = @component.parse_component(
      @component_text.parse_component_wat(
        source.replace_all(old="ALLOC_BODY", new=body),
      ),
    )
    let validated = @component_validator.validate_component_for_instantiation_with_config(
      component,
      ComponentValidationConfig(false),
    )
    let linker = ComponentLinker::ComponentLinker()
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    if invalid {
      let error = try {
        instance.call_exported_func("run", [String("abc")]) |> ignore
        "unexpected return"
      } catch {
        error => canon_err_message(error)
      }
      inspect(error, content="cannot leave component instance")
    } else {
      for _ in 0..<2 {
        debug_inspect(
          instance.call_exported_func("run", [String("abc")]),
          content="[]",
        )
      }
    }
  }
}
