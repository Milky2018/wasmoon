///|
test "async task return matches the lifted result and canonical options" {
  for callback in [false, true] {
    for
      scenario in [
        "missing", "result", "memory", "encoding", "valid", "unused-lift-memory",
      ] {
      let source =
        #|(component
        #|  (core module $mem (memory (export "m") 1))
        #|  (core instance $mem (instantiate $mem))
        #|  (core func $ret (canon task.return RETURN_OPTIONS))
        #|  (core module $M
        #|    (import "" "ret" (func $ret RETURN_PARAMS))
        #|    (func (export "run") CORE_RESULT BODY EXIT)
        #|    (func (export "cb") (param i32 i32 i32) (result i32) unreachable))
        #|  (core instance $m (instantiate $M (with "" (instance (export "ret" (func $ret))))))
        #|  (func (export "run") async (canon lift (core func $m "run") async CALLBACK LIFT_MEMORY)))
      let return_options = match scenario {
        "result" => "(result u32)"
        "memory" => "(memory (core memory $mem \"m\"))"
        "encoding" => "string-encoding=utf16"
        _ => ""
      }
      let body = match scenario {
        "missing" => ""
        "result" => "i32.const 42 call $ret"
        _ => "call $ret"
      }
      let source = source
        .replace_all(
          old="LIFT_MEMORY",
          new=if scenario == "unused-lift-memory" {
            "(memory (core memory $mem \"m\"))"
          } else {
            ""
          },
        )
        .replace_all(old="RETURN_OPTIONS", new=return_options)
        .replace_all(
          old="RETURN_PARAMS",
          new=if scenario == "result" { "(param i32)" } else { "" },
        )
        .replace_all(
          old="CORE_RESULT",
          new=if callback { "(result i32)" } else { "" },
        )
        .replace_all(old="BODY", new=body)
        .replace_all(old="EXIT", new=if callback { "i32.const 0" } else { "" })
        .replace_all(
          old="CALLBACK",
          new=if callback { "(callback (core func $m \"cb\"))" } else { "" },
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
      if scenario == "valid" || scenario == "unused-lift-memory" {
        debug_inspect(instance.call_exported_func("run", []), content="[]")
      } else {
        let error = try {
          instance.call_exported_func("run", []) |> ignore
          "unexpected return"
        } catch {
          error => canon_err_message(error)
        }
        inspect(
          error,
          content=if scenario == "missing" {
            "async-lifted export failed to produce a result"
          } else {
            "invalid `task.return` signature and/or options for current task"
          },
        )
      }
    }
  }
}

///|
test "async result can be returned by a child after the main thread exits" {
  let source =
    #|(component
    #|  (core module $table (table (export "t") 1 funcref))
    #|  (core instance $table (instantiate $table))
    #|  (core type $start (func (param i32)))
    #|  (core func $new (canon thread.new-indirect $start (core table $table "t")))
    #|  (core func $resume (canon thread.resume-later))
    #|  (core func $ret (canon task.return (result u32)))
    #|  (core module $M
    #|    (import "" "new" (func $new (param i32 i32) (result i32)))
    #|    (import "" "resume" (func $resume (param i32)))
    #|    (import "" "ret" (func $ret (param i32)))
    #|    (import "" "table" (table 1 funcref))
    #|    (func $worker (param i32) local.get 0 call $ret)
    #|    (elem (i32.const 0) func $worker)
    #|    (func (export "run") i32.const 0 i32.const 55 call $new call $resume))
    #|  (core instance $m (instantiate $M (with "" (instance
    #|    (export "new" (func $new)) (export "resume" (func $resume))
    #|    (export "ret" (func $ret)) (export "table" (table $table "t"))))))
    #|  (func (export "run") async (result u32) (canon lift (core func $m "run") async)))
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
  debug_inspect(instance.call_exported_func("run", []), content="[U32(55)]")
}

///|
test "guest handle binding preserves stable child identities and cancellation" {
  let linker = ComponentLinker::ComponentLinker()
  defer linker.close()
  let state = AsyncState(StreamTable())
  let start = alloc_host_core_func(
    linker.get_store(),
    { params: [], results: [], },
    fn(_) { [] },
  )
  let cancelled = [0]
  let thread : GuestThread = {
    owner_component_id: 0,
    handle: 1,
    parent_task_id: -1L,
    task_id: -2L,
    start_func: start,
    context: 0,
    phase: [Suspended],
    scheduled: [true],
    waiting_ws: [None],
    continuation: [
      Some(CoreContinuation(fn() { Returned([]) }, fn() { cancelled[0] += 1 })),
    ],
  }
  state.threads.set(handle_key(0, 1), thread)
  inspect(alloc_task_id(state), content="-1")
  inspect(alloc_task_id(state), content="-2")
  init_task_meta(state, -1L, 0, 0L)
  init_task_meta(state, -2L, 0, -1L)
  state.tasks.write_thread_runnable(-1L, [1])
  state.tasks.write_main_thread_scheduled(-1L, true)
  state.tasks.bind_handle(-1L, 7L)
  inspect(thread.parent_task_id, content="-1")
  inspect(
    state.tasks.entries_task_caller().contains((-2L, -1L)),
    content="true",
  )
  debug_inspect(pop_runnable_explicit_thread(state, 0, 7L), content="Some(1)")
  inspect(consume_main_scheduled(state, 7L), content="true")
  inspect(cancelled[0], content="0")
  retire_task(state, 7L)
  inspect(cancelled[0], content="1")
  debug_inspect(
    (
      state.threads.length(),
      state.tasks.entries_task_caller().length(),
      state.tasks.entries_thread_runnable().length(),
    ),
    content="(0, 0, 0)",
  )
}

///|
test "task return preserves flat string and list descriptors for both memory widths" {
  for memory64 in [false, true] {
    for list in [false, true] {
      let source =
        #|(component
        #|  (core module $Memory (memory (export "m") MEMORY_WIDTH 1) (data (ADDR.const 0) "hello"))
        #|  (core instance $memory (instantiate $Memory))
        #|  (type $result RESULT_TYPE)
        #|  (core func $return (canon task.return (result $result) (memory (core memory $memory "m"))))
        #|  (core module $M
        #|    (import "" "return" (func $return (param ADDR ADDR)))
        #|    (func (export "run") ADDR.const 0 ADDR.const 5 call $return))
        #|  (core instance $m (instantiate $M (with "" (instance (export "return" (func $return))))))
        #|  (func (export "run") async (result $result)
        #|    (canon lift (core func $m "run") async (memory (core memory $memory "m")))))
      let source = source
        .replace_all(old="MEMORY_WIDTH", new=if memory64 { "i64" } else { "" })
        .replace_all(old="ADDR", new=if memory64 { "i64" } else { "i32" })
        .replace_all(
          old="RESULT_TYPE",
          new=if list { "(list u8)" } else { "string" },
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
      debug_inspect(
        instance.call_exported_func("run", []),
        content=if list {
          "[List([U8(104), U8(101), U8(108), U8(108), U8(111)])]"
        } else {
          "[String(\"hello\")]"
        },
      )
    }
  }
}
