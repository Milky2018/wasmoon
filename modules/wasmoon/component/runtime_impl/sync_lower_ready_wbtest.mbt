///|
test "sync lower accepts an async callee that publishes a result immediately" {
  for callback in [false, true] {
    let source =
      #|(component
      #|  (component $A
      #|    (core func $return (canon task.return (result u32)))
      #|    (core module $M
      #|      (import "" "return" (func $return (param i32)))
      #|      (func (export "run") (param i32) CORE_RESULT local.get 0 call $return EXIT)
      #|      (func (export "callback") (param i32 i32 i32) (result i32) i32.const 0))
      #|    (core instance $m (instantiate $M (with "" (instance (export "return" (func $return))))))
      #|    (func (export "run") async (param "x" u32) (result u32)
      #|      (canon lift (core func $m "run") async CALLBACK)))
      #|  (component $B
      #|    (import "f" (func $f async (param "x" u32) (result u32)))
      #|    (core func $f (canon lower (func $f)))
      #|    (core module $M
      #|      (import "" "f" (func $f (param i32) (result i32)))
      #|      (func (export "run") (result i32) i32.const 42 call $f))
      #|    (core instance $m (instantiate $M (with "" (instance (export "f" (func $f))))))
      #|    (func (export "run") (result u32) (canon lift (core func $m "run"))))
      #|  (instance $a (instantiate $A))
      #|  (instance $b (instantiate $B (with "f" (func $a "run"))))
      #|  (export "run" (func $b "run")))
    let source = source
      .replace_all(
        old="CORE_RESULT",
        new=if callback { "(result i32)" } else { "" },
      )
      .replace_all(old="EXIT", new=if callback { "i32.const 1" } else { "" })
      .replace_all(
        old="CALLBACK",
        new=if callback { "(callback (core func $m \"callback\"))" } else { "" },
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
    debug_inspect(instance.call_exported_func("run", []), content="[U32(42)]")
  }
}

///|
test "sync lower polls a host result before rejecting a pending call and cancels it once" {
  let source =
    #|(component
    #|  (import "f" (func $f async (result u32)))
    #|  (core func $f (canon lower (func $f)))
    #|  (core module $M
    #|    (import "" "f" (func $f (result i32)))
    #|    (func (export "run") (result i32) call $f))
    #|  (core instance $m (instantiate $M (with "" (instance (export "f" (func $f))))))
    #|  (func (export "run") (result u32) (canon lift (core func $m "run"))))
  let component = @component.parse_component(
    @component_text.parse_component_wat(source),
  )
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(false),
  )
  for ready in [false, true] {
    let linker = ComponentLinker::ComponentLinker()
    defer linker.close()
    let cancelled = [0]
    let polled = [0]
    linker.add_import(
      "f",
      Func(
        HostAsync(
          { is_async: true, params: [], result: Some(Prim(U32)), },
          [],
          fn(_, _) {
            HostFuture(
              fn() {
                polled[0] += 1
                if ready {
                  Ready([U32(42)])
                } else {
                  Pending
                }
              },
              fn() { cancelled[0] += 1 },
            )
          },
        ),
      ),
    )
    let instance = linker.instantiate("root", validated)
    if ready {
      debug_inspect(instance.call_exported_func("run", []), content="[U32(42)]")
      inspect(cancelled[0], content="0")
    } else {
      let error = try {
        instance.call_exported_func("run", []) |> ignore
        "unexpected return"
      } catch {
        error => canon_err_message(error)
      }
      inspect(error, content="cannot block a synchronous task before returning")
      inspect(cancelled[0], content="1")
    }
    inspect(polled[0], content="1")
    inspect(
      instance.async_state.tasks.entries_sync_lower_states().length(),
      content="0",
    )
  }
}

///|
test "core start rejects sync lowering of async imports before invoking the host" {
  let source =
    #|(component
    #|  (import "f" (func $f async))
    #|  (core func $f (canon lower (func $f)))
    #|  (core module $M
    #|    (import "" "f" (func $f))
    #|    (func $start call $f) (start $start))
    #|  (core instance $m (instantiate $M (with "" (instance (export "f" (func $f)))))))
  let component = @component.parse_component(
    @component_text.parse_component_wat(source),
  )
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(false),
  )
  let linker = ComponentLinker::ComponentLinker()
  defer linker.close()
  let invoked = [0]
  linker.add_import(
    "f",
    Func(
      HostAsync({ is_async: true, params: [], result: None, }, [], fn(_, _) {
        invoked[0] += 1
        HostFuture(fn() { Ready([]) }, fn() { () })
      }),
    ),
  )
  let error = try {
    linker.instantiate("root", validated) |> ignore
    "unexpected instance"
  } catch {
    CoreModuleInstantiateError(message) => message
    error => canon_err_message(error)
  }
  inspect(error, content="cannot block a synchronous task before returning")
  inspect(invoked[0], content="0")
}
