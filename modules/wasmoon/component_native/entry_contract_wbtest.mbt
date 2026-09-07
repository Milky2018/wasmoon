///|
test "component containment does not prohibit calls but active reentry does" {
  for native in [false, true] {
    for scenario in ["parent-to-child", "child-to-parent", "cycle"] {
      let source =
        #|(component
        #|  (core module $Leaf (func (export "f") (result i32) i32.const 42))
        #|  (core instance $leaf (instantiate $Leaf))
        #|  (func $f (result u32) (canon lift (core func $leaf "f")))
        #|  (component $Child
        #|    (import "f" (func $f (result u32)))
        #|    (core func $f (canon lower (func $f)))
        #|    (core module $M
        #|      (import "" "f" (func $f (result i32)))
        #|      (func (export "run") (result i32) CHILD_BODY))
        #|    (core instance $m (instantiate $M (with "" (instance (export "f" (func $f))))))
        #|    (func (export "run") (result u32) (canon lift (core func $m "run"))))
        #|  (instance $child (instantiate $Child (with "f" (func $f))))
        #|  (core func $child-run (canon lower (func $child "run")))
        #|  (core module $M
        #|    (import "" "run" (func $run (result i32)))
        #|    (func (export "run") (result i32) call $run))
        #|  (core instance $m (instantiate $M (with "" (instance (export "run" (func $child-run))))))
        #|  (func $run (result u32) (canon lift (core func $m "run")))
        #|  (export "run" (func EXPORT)))
      let source = source
        .replace_all(
          old="CHILD_BODY",
          new=if scenario == "parent-to-child" {
            "i32.const 42"
          } else {
            "call $f"
          },
        )
        .replace_all(
          old="EXPORT",
          new=if scenario == "child-to-parent" {
            "$child \"run\""
          } else {
            "$run"
          },
        )
      let validated = @component_validator.validate_component_for_instantiation_with_config(
        @component.parse_component(@component_text.parse_component_wat(source)),
        ComponentValidationConfig(false),
      )
      let engine = if native {
        open_native_component_session(opt_level=0)
      } else {
        @runtime_impl.interpreter_core_execution_engine()
      }
      let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
        engine,
      )
      defer linker.close()
      let instance = linker.instantiate("root", validated)
      if scenario == "cycle" {
        for _ in 0..<2 {
          let message = try {
            instance.call_exported_func("run", []) |> ignore
            "unexpected return"
          } catch {
            error => error.to_string()
          }
          guard message.contains("cannot enter component instance") else {
            fail(message)
          }
        }
      } else {
        debug_inspect(
          instance.call_exported_func("run", []),
          content="[U32(42)]",
        )
      }
    }
  }
}

///|
test "core start may call an already defined canonical adapter in its component" {
  let source =
    #|(component
    #|  (core module $M
    #|    (global $calls (mut i32) (i32.const 0))
    #|    (func (export "increment") global.get $calls i32.const 1 i32.add global.set $calls)
    #|    (func (export "calls") (result i32) global.get $calls))
    #|  (core instance $m (instantiate $M))
    #|  (func $increment (canon lift (core func $m "increment")))
    #|  (core func $increment (canon lower (func $increment)))
    #|  (core module $Start
    #|    (import "" "increment" (func $increment))
    #|    (func $start call $increment) (start $start))
    #|  (core instance (instantiate $Start (with "" (instance (export "increment" (func $increment))))))
    #|  (func (export "calls") (result u32) (canon lift (core func $m "calls"))))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  for native in [false, true] {
    let engine = if native {
      open_native_component_session(opt_level=0)
    } else {
      @runtime_impl.interpreter_core_execution_engine()
    }
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
    )
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    debug_inspect(instance.call_exported_func("calls", []), content="[U32(1)]")
  }
}
