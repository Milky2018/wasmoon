///|
test "synchronous subtask cancellation waits for cancelled or returned status" {
  for native in [false, true] {
    for accepts_cancel in [false, true] {
      for repeated in [false, true] {
        let source =
          #|(component
          #|  (component $A
          #|    (core func $yield (canon thread.yield))
          #|    (core func $cancel (canon task.cancel))
          #|    (core module $M
          #|      (import "" "yield" (func $yield (result i32)))
          #|      (import "" "cancel" (func $cancel))
          #|      (func (export "run") (result RESULT_TYPE)
          #|        call $yield drop call $yield drop call $yield drop BODY)
          #|      (func (export "callback") (param i32 i32 i32) (result i32)
          #|        local.get 0 i32.const 6 i32.ne if unreachable end
          #|        call $cancel i32.const 0))
          #|    (core instance $m (instantiate $M (with "" (instance
          #|      (export "yield" (func $yield)) (export "cancel" (func $cancel))))))
          #|    (func (export "run") async (result f64) (canon lift (core func $m "run") CALLBACK)))
          #|  (component $B
          #|    (import "run" (func $run async (result f64)))
          #|    (core module $Mem (memory (export "memory") 1))
          #|    (core instance $mem (instantiate $Mem))
          #|    (core func $run (canon lower (func $run) async (memory (core memory $mem "memory"))))
          #|    (core func $cancel (canon subtask.cancel))
          #|    (core func $drop (canon subtask.drop))
          #|    (core module $M
          #|      (import "" "run" (func $run (param i32) (result i32)))
          #|      (import "" "cancel" (func $cancel (param i32) (result i32)))
          #|      (import "" "drop" (func $drop (param i32)))
          #|      (import "" "memory" (memory 1))
          #|      (func (export "run") (local $status i32) (local $task i32)
          #|        i32.const 8 f64.const -17.25 f64.store
          #|        i32.const 8 call $run local.tee $status i32.const 4 i32.shr_u local.set $task
          #|        local.get $status i32.const 15 i32.and i32.const 1 i32.ne if unreachable end
          #|        local.get $task call $cancel i32.const STATUS i32.ne if unreachable end
          #|        i32.const 8 f64.load f64.const VALUE f64.ne if unreachable end
          #|        REPEAT
          #|        local.get $task call $drop))
          #|    (core instance $m (instantiate $M (with "" (instance
          #|      (export "run" (func $run)) (export "cancel" (func $cancel))
          #|      (export "drop" (func $drop)) (export "memory" (memory $mem "memory"))))))
          #|    (func (export "run") async (canon lift (core func $m "run"))))
          #|  (instance $a (instantiate $A))
          #|  (instance $b (instantiate $B (with "run" (func $a "run"))))
          #|  (export "run" (func $b "run")))
        let source = source
          .replace_all(
            old="RESULT_TYPE",
            new=if accepts_cancel { "i32" } else { "f64" },
          )
          .replace_all(
            old="BODY",
            new=if accepts_cancel { "i32.const 1" } else { "f64.const 42.5" },
          )
          .replace_all(
            old="CALLBACK",
            new=if accepts_cancel {
              "async (callback (core func $m \"callback\"))"
            } else {
              ""
            },
          )
          .replace_all(old="STATUS", new=if accepts_cancel { "4" } else { "2" })
          .replace_all(
            old="VALUE",
            new=if accepts_cancel { "-17.25" } else { "42.5" },
          )
          .replace_all(
            old="REPEAT",
            new=if repeated { "local.get $task call $cancel drop" } else { "" },
          )
        let validated = @component_validator.validate_component_for_instantiation_with_config(
          @component.parse_component(
            @component_text.parse_component_wat(source),
          ),
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
        if repeated {
          let message = try {
            instance.call_exported_func("run", []) |> ignore
            "unexpected return"
          } catch {
            error => error.to_string()
          }
          guard message.contains(
            "`subtask.cancel` called after terminal status delivered",
          ) else {
            fail(message)
          }
        } else {
          debug_inspect(instance.call_exported_func("run", []), content="[]")
        }
      }
    }
  }
}

///|
test "subtask cancellation cancels pending host futures once" {
  let source =
    #|(component
    #|  (import "pending" (func $pending async))
    #|  (core func $pending (canon lower (func $pending) async))
    #|  (core func $cancel (canon subtask.cancel ASYNC))
    #|  (core func $drop (canon subtask.drop))
    #|  (core module $M
    #|    (import "" "pending" (func $pending (result i32)))
    #|    (import "" "cancel" (func $cancel (param i32) (result i32)))
    #|    (import "" "drop" (func $drop (param i32)))
    #|    (func (export "run") (local $task i32)
    #|      call $pending i32.const 4 i32.shr_u local.set $task
    #|      local.get $task call $cancel i32.const 4 i32.ne if unreachable end
    #|      local.get $task call $drop))
    #|  (core instance $m (instantiate $M (with "" (instance
    #|    (export "pending" (func $pending)) (export "cancel" (func $cancel)) (export "drop" (func $drop))))))
    #|  (func (export "run") async (canon lift (core func $m "run"))))
  for native in [false, true] {
    for async_cancel in [false, true] {
      let source = source.replace_all(
        old="ASYNC",
        new=if async_cancel { "async" } else { "" },
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
      let starts = [0]
      let cancels = [0]
      linker.add_import(
        "pending",
        Func(
          HostAsync({ is_async: true, params: [], result: None, }, [], fn(
            _,
            _,
          ) {
            starts[0] += 1
            HostFuture(fn() { Pending }, fn() { cancels[0] += 1 })
          }),
        ),
      )
      let instance = linker.instantiate("root", validated)
      debug_inspect(instance.call_exported_func("run", []), content="[]")
      debug_inspect((starts[0], cancels[0]), content="(1, 1)")
    }
  }
}

///|
test "async cancellation resumes only cancellable suspension points" {
  for native in [false, true] {
    for initially_cancellable in [false, true] {
      let source =
        #|(component
        #|  (component $A
        #|    (core func $first (canon thread.yield CANCELLABLE))
        #|    (core func $second (canon thread.yield cancellable))
        #|    (core func $cancel (canon task.cancel))
        #|    (core module $M
        #|      (import "" "first" (func $first (result i32)))
        #|      (import "" "second" (func $second (result i32)))
        #|      (import "" "cancel" (func $cancel))
        #|      (func (export "run")
        #|        call $first i32.const FIRST_RESULT i32.ne if unreachable end SECOND
        #|        call $cancel))
        #|    (core instance $m (instantiate $M (with "" (instance
        #|      (export "first" (func $first)) (export "second" (func $second)) (export "cancel" (func $cancel))))))
        #|    (func (export "run") async (result u32) (canon lift (core func $m "run") async)))
        #|  (component $B
        #|    (import "run" (func $run async (result u32)))
        #|    (core module $Mem (memory (export "memory") 1))
        #|    (core instance $mem (instantiate $Mem))
        #|    (core func $run (canon lower (func $run) async (memory (core memory $mem "memory"))))
        #|    (core func $cancel (canon subtask.cancel async))
        #|    (core func $new (canon waitable-set.new))
        #|    (core func $join (canon waitable.join))
        #|    (core func $wait (canon waitable-set.wait (memory (core memory $mem "memory"))))
        #|    (core module $M
        #|      (import "" "run" (func $run (param i32) (result i32)))
        #|      (import "" "cancel" (func $cancel (param i32) (result i32)))
        #|      (import "" "new" (func $new (result i32)))
        #|      (import "" "join" (func $join (param i32 i32)))
        #|      (import "" "wait" (func $wait (param i32 i32) (result i32)))
        #|      (import "" "memory" (memory 1))
        #|      (func (export "run") (local $task i32) (local $ws i32)
        #|        i32.const 8 i32.const 123 i32.store
        #|        i32.const 8 call $run i32.const 4 i32.shr_u local.set $task
        #|        local.get $task call $cancel i32.const CANCEL_RESULT i32.ne if unreachable end
        #|        WAIT
        #|        i32.const 8 i32.load i32.const 123 i32.ne if unreachable end))
        #|    (core instance $m (instantiate $M (with "" (instance
        #|      (export "run" (func $run)) (export "cancel" (func $cancel))
        #|      (export "new" (func $new)) (export "join" (func $join)) (export "wait" (func $wait))
        #|      (export "memory" (memory $mem "memory"))))))
        #|    (func (export "run") async (canon lift (core func $m "run"))))
        #|  (instance $a (instantiate $A))
        #|  (instance $b (instantiate $B (with "run" (func $a "run"))))
        #|  (export "run" (func $b "run")))
      let source = source
        .replace_all(
          old="CANCELLABLE",
          new=if initially_cancellable { "cancellable" } else { "" },
        )
        .replace_all(
          old="FIRST_RESULT",
          new=if initially_cancellable { "1" } else { "0" },
        )
        .replace_all(
          old="SECOND",
          new=if initially_cancellable {
            ""
          } else {
            "call $second i32.const 1 i32.ne if unreachable end"
          },
        )
        .replace_all(
          old="CANCEL_RESULT",
          new=if initially_cancellable { "4" } else { "-1" },
        )
        .replace_all(
          old="WAIT",
          new=if initially_cancellable {
            ""
          } else {
            "call $new local.set $ws local.get $task local.get $ws call $join local.get $ws i32.const 16 call $wait i32.const 1 i32.ne if unreachable end i32.const 20 i32.load i32.const 4 i32.ne if unreachable end"
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
      debug_inspect(instance.call_exported_func("run", []), content="[]")
    }
  }
}
