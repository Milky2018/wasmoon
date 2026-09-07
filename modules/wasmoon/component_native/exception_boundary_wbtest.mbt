///|
test "uncaught exceptions become traps at component boundaries" {
  for native in [false, true] {
    for caught in [false, true] {
      for asynchronous in [false, true] {
        let source =
          #|(component
          #|  (component $A
          #|    (core func $yield (canon thread.yield))
          #|    (core module $M
          #|      (import "" "yield" (func $yield (result i32)))
          #|      (tag $t)
          #|      (func (export "f") YIELD BODY))
          #|    (core instance $m (instantiate $M (with "" (instance (export "yield" (func $yield))))))
          #|    (func (export "f") ASYNC (canon lift (core func $m "f"))))
          #|  (component $B
          #|    (import "f" (func $f ASYNC))
          #|    (core func $f (canon lower (func $f)))
          #|    (core module $M
          #|      (import "" "f" (func $f))
          #|      (func (export "run") (result i32)
          #|        (block $caught
          #|          (try_table (catch_all $caught) (call $f))
          #|          i32.const 42 return)
          #|        i32.const 7))
          #|    (core instance $m (instantiate $M (with "" (instance (export "f" (func $f))))))
          #|    (func (export "run") ASYNC (result u32) (canon lift (core func $m "run"))))
          #|  (instance $a (instantiate $A))
          #|  (instance $b (instantiate $B (with "f" (func $a "f"))))
          #|  (export "run" (func $b "run")))
        let source = source.replace_all(
          old="BODY",
          new=if caught {
            "(block $handled (try_table (catch_all $handled) (throw $t)))"
          } else {
            "(throw $t)"
          },
        )
        let source = source
          .replace_all(old="ASYNC", new=if asynchronous { "async" } else { "" })
          .replace_all(
            old="YIELD",
            new=if asynchronous { "call $yield drop" } else { "" },
          )
        let component = @component.parse_component(
          @component_text.parse_component_wat(source),
        )
        let validated = @component_validator.validate_component_for_instantiation_with_config(
          component,
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
        let waits = [0]
        linker
        .host_runtime_state()
        .set_event_loop(fn() {
          waits[0] += 1
          false
        })
        let instance = linker.instantiate("root", validated)
        if caught {
          debug_inspect(
            instance.call_exported_func("run", []),
            content="[U32(42)]",
          )
        } else {
          let message = try {
            instance.call_exported_func("run", []) |> ignore
            "unexpected return"
          } catch {
            CanonCallError(message) => message
            error => error.to_string()
          }
          guard message.contains(
            if asynchronous {
              "thrown Wasm exception"
            } else {
              "uncaught exception propagated out of component"
            },
          ) else {
            fail("native=\{native}, async=\{asynchronous}: \{message}")
          }
        }
        inspect(waits[0], content="0")
      }
    }
  }
}

///|
test "failed async subtasks do not contaminate later component invocations" {
  let source =
    #|(component
    #|  (component $A
    #|    (core func $yield (canon thread.yield))
    #|    (core module $M
    #|      (import "" "yield" (func $yield (result i32)))
    #|      (tag $t)
    #|      (func (export "f") call $yield drop throw $t))
    #|    (core instance $m (instantiate $M (with "" (instance (export "yield" (func $yield))))))
    #|    (func (export "f") async (canon lift (core func $m "f"))))
    #|  (component $B
    #|    (import "f" (func $f async))
    #|    (core func $f (canon lower (func $f) async))
    #|    (core module $Mem (memory (export "m") 1))
    #|    (core instance $mem (instantiate $Mem))
    #|    (core func $set (canon waitable-set.new))
    #|    (core func $join (canon waitable.join))
    #|    (core func $wait (canon waitable-set.wait (memory (core memory $mem "m"))))
    #|    (core module $M
    #|      (import "" "f" (func $f (result i32)))
    #|      (import "" "set" (func $set (result i32)))
    #|      (import "" "join" (func $join (param i32 i32)))
    #|      (import "" "wait" (func $wait (param i32 i32) (result i32)))
    #|      (func (export "run") (local $task i32) (local $ws i32)
    #|        call $f i32.const 4 i32.shr_u local.set $task
    #|        call $set local.set $ws local.get $task local.get $ws call $join
    #|        local.get $ws i32.const 0 call $wait drop unreachable))
    #|    (core instance $m (instantiate $M (with "" (instance
    #|      (export "f" (func $f)) (export "set" (func $set))
    #|      (export "join" (func $join)) (export "wait" (func $wait))))))
    #|    (func (export "run") async (canon lift (core func $m "run"))))
    #|  (instance $a (instantiate $A))
    #|  (instance $b (instantiate $B (with "f" (func $a "f"))))
    #|  (export "run" (func $b "run")))
  let component = @component.parse_component(
    @component_text.parse_component_wat(source),
  )
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
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
    let cancelled = [0]
    let builder = linker.host_instance_builder("unrelated", HostRuntimeState())
    builder.add_async_func(
      "run",
      { is_async: true, params: [], result: None, },
      fn(_, _) { HostFuture(fn() { Pending }, fn() { cancelled[0] += 1 }) },
    )
    let pending_instance = builder.finish()
    let pending = pending_instance.start_exported_func("run", [])
    debug_inspect(pending.poll(), content="InvocationPending")
    for name in ["first", "second"] {
      let instance = linker.instantiate(name, validated)
      let message = try {
        instance.call_exported_func("run", []) |> ignore
        "unexpected return"
      } catch {
        error => error.to_string()
      }
      guard instance.async_state.subtasks.is_empty() else {
        fail(
          "remaining subtasks=\{instance.async_state.subtasks.length()}, stack=\{Repr(instance.async_state.task_stack)}",
        )
      }
      inspect(cancelled[0], content="0")
      guard message.contains("thrown Wasm exception") else {
        fail("native=\{native}, instance=\{name}: \{message}")
      }
    }
    pending.cancel()
    inspect(cancelled[0], content="1")
  }
}
