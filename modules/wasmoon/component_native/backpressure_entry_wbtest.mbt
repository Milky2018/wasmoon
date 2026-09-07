///|
test "host async invocations wait for backpressure before entering guest code" {
  for native in [false, true] {
    for callback in [false, true] {
      let source =
        #|(component
        #|  (core func $inc (canon backpressure.inc))
        #|  (core func $dec (canon backpressure.dec))
        #|  (core func $return (canon task.return (result u32)))
        #|  (core module $M
        #|    (import "" "inc" (func $inc))
        #|    (import "" "dec" (func $dec))
        #|    (import "" "return" (func $return (param i32)))
        #|    (global $calls (mut i32) (i32.const 0))
        #|    (func (export "block") call $inc)
        #|    (func (export "unblock") call $dec)
        #|    (func (export "calls") (result i32) global.get $calls)
        #|    (func (export "run") (result i32)
        #|      global.get $calls i32.const 1 i32.add global.set $calls BODY)
        #|    (func (export "callback") (param i32 i32 i32) (result i32) unreachable))
        #|  (core instance $m (instantiate $M (with "" (instance
        #|    (export "inc" (func $inc)) (export "dec" (func $dec)) (export "return" (func $return))))))
        #|  (func (export "block") (canon lift (core func $m "block")))
        #|  (func (export "unblock") (canon lift (core func $m "unblock")))
        #|  (func (export "calls") (result u32) (canon lift (core func $m "calls")))
        #|  (func (export "run") async (result u32) (canon lift (core func $m "run") CALLBACK)))
      let source = source
        .replace_all(
          old="BODY",
          new=if callback {
            "i32.const 42 call $return i32.const 0"
          } else {
            "i32.const 42"
          },
        )
        .replace_all(
          old="CALLBACK",
          new=if callback {
            "async (callback (core func $m \"callback\"))"
          } else {
            ""
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
      let host_runtime = linker.host_runtime_state()
      let instance = linker.instantiate("root", validated)
      instance.call_exported_func("block", []) |> ignore
      let abandoned = instance.start_exported_func("run", [])
      debug_inspect(abandoned.poll(), content="InvocationPending")
      abandoned.cancel()
      debug_inspect(
        instance.call_exported_func("calls", []),
        content="[U32(0)]",
      )
      let blocked = instance.start_exported_func("run", [])
      debug_inspect(blocked.poll(), content="InvocationPending")
      instance.call_exported_func("unblock", []) |> ignore
      debug_inspect(blocked.wait(), content="[U32(42)]")
      instance.call_exported_func("block", []) |> ignore
      let message = try {
        instance.call_exported_func("run", []) |> ignore
        "unexpected return"
      } catch {
        error => error.to_string()
      }
      guard message.contains("cannot make further progress") else {
        fail(message)
      }
      debug_inspect(
        instance.call_exported_func("calls", []),
        content="[U32(1)]",
      )
      let waits = [0]
      host_runtime.set_event_loop(() => {
        waits[0] += 1
        instance.call_exported_func("unblock", []) |> ignore
        true
      })
      debug_inspect(instance.call_exported_func("run", []), content="[U32(42)]")
      inspect(waits[0], content="1")
      debug_inspect(
        instance.call_exported_func("calls", []),
        content="[U32(2)]",
      )
    }
  }
}
