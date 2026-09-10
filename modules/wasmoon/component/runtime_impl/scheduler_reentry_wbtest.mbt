///|
test "scheduler does not recursively poll an active subtask through its guest handle" {
  let source =
    #|(component
    #|  (import "host" (func $host async (result u32)))
    #|  (core module $Memory (memory (export "memory") 1))
    #|  (core instance $memory (instantiate $Memory))
    #|  (core func $host (canon lower (func $host) async (memory $memory "memory")))
    #|  (core func $new (canon waitable-set.new))
    #|  (core func $join (canon waitable.join))
    #|  (core func $wait (canon waitable-set.wait (memory $memory "memory")))
    #|  (core func $drop (canon subtask.drop))
    #|  (core module $M
    #|    (import "" "memory" (memory 1))
    #|    (import "" "host" (func $host (param i32) (result i32)))
    #|    (import "" "new" (func $new (result i32)))
    #|    (import "" "join" (func $join (param i32 i32)))
    #|    (import "" "wait" (func $wait (param i32 i32) (result i32)))
    #|    (import "" "drop" (func $drop (param i32)))
    #|    (func (export "run") (result i32) (local $sub i32) (local $ws i32)
    #|      i32.const 0 call $host i32.const 4 i32.shr_u local.set $sub
    #|      call $new local.set $ws
    #|      local.get $sub local.get $ws call $join
    #|      local.get $ws i32.const 16 call $wait drop
    #|      local.get $sub call $drop
    #|      i32.const 0 i32.load))
    #|  (core instance $m (instantiate $M (with "" (instance
    #|    (export "memory" (memory $memory "memory")) (export "host" (func $host))
    #|    (export "new" (func $new)) (export "join" (func $join))
    #|    (export "wait" (func $wait)) (export "drop" (func $drop))))))
    #|  (func (export "run") async (result u32) (canon lift (core func $m "run"))))
  let linker = ComponentLinker::ComponentLinker()
  defer linker.close()
  let state = linker.host_runtime_state().async_state
  let store = linker.core_linker.get_store()
  let polled = Ref(0)
  let reentered = Ref(false)
  linker.add_import(
    "host",
    Func(
      HostAsync({ is_async: true, params: [], result: Some(Prim(U32)), }, [], (
        _,
        _,
      ) => {
        HostFuture(
          () => {
            polled.val += 1
            if polled.val == 1 {
              Pending
            } else {
              if polled.val == 2 {
                reentered.val = progress_one_subtask_intrinsic(state, store)
              }
              Ready([U32(42)])
            }
          },
          () => (),
        )
      }),
    ),
  )
  let component = @component.parse_component(
    @component_text.parse_component_wat(source),
  )
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(false),
  )
  let instance = linker.instantiate("root", validated)
  debug_inspect(instance.call_exported_func("run", []), content="[U32(42)]")
  inspect(polled.val, content="2")
  inspect(reentered.val, content="false")
}
