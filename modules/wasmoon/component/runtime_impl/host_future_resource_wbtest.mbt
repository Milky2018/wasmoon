///|
test "canonical future reads transfer owned host resources in both rendezvous orders" {
  for read_first in [false, true] {
    let linker = ComponentLinker()
    defer linker.close()
    let runtime = linker.host_runtime_state()
    let source = runtime.resource_table()
    let resource_type = linker.new_host_resource_type()
    guard resource_type is Some(ResourceType(type_id, _, _, _)) else {
      return fail("missing resource type")
    }
    let builder = linker.host_instance_builder("host", runtime)
    builder.set_type_space([resource_type])
    builder.add_type("r", 0)
    linker.add_instance("host", builder.finish())
    let bytes = @component_text.parse_component_wat(
      (
        #|(component
        #|  (import "host" (instance $host (export "r" (type (sub resource)))))
        #|  (alias export $host "r" (type $r))
        #|  (export "r" (type $r))
        #|  (type $future (future (own $r)))
        #|  (core module $Mem (memory (export "m") 1))
        #|  (core instance $mem (instantiate $Mem))
        #|  (core func $read (canon future.read $future async (memory (core memory $mem "m"))))
        #|  (core func $drop (canon resource.drop $r))
        #|  (core module $M
        #|    (import "" "m" (memory 1))
        #|    (import "" "read" (func $read (param i32 i32) (result i32)))
        #|    (import "" "drop" (func $drop (param i32)))
        #|    (func (export "read") (param i32) (result i32)
        #|      local.get 0 i32.const 0 call $read)
        #|    (func (export "drop") i32.const 0 i32.load call $drop))
        #|  (core instance $m (instantiate $M (with "" (instance
        #|    (export "m" (memory $mem "m"))
        #|    (export "read" (func $read)) (export "drop" (func $drop))))))
        #|  (func (export "read") (param "f" $future) (result s32) (canon lift (core func $m "read")))
        #|  (func (export "drop") (canon lift (core func $m "drop"))))
      ),
    )
    let validated = @component_validator.validate_component_for_instantiation(
      @component.parse_component(bytes),
    )
    let instance = linker.instantiate("reader", validated)
    let destroyed = Ref(0)
    let representation = Ref(0)
    let owned = source.alloc({
      type_id,
      rep: 99,
      dtor: None,
      host_dtor: Some(
        HostResourceDestructor(rep => {
          representation.val = rep
          destroyed.val += 1
        }),
      ),
      kind: HostDefined,
      impl_component_id: source.id,
      own: true,
      borrow_scope: None,
      num_lends: [0],
    })
    let ready = Ref(!read_first)
    let future = runtime.new_host_value_future_source(
      source,
      TypeIdx(1),
      [resource_type, Some(Own(0))],
      () => if ready.val { Ready(U32(owned)) } else { Pending },
      () => (),
    )
    let future = runtime.move_readable_future(
      source,
      instance.resource_table,
      future,
    )
    assert_eq(instance.call_exported_func("read", [U32(future)]), [
      S32(if read_first { -1 } else { 0 }),
    ])
    if read_first {
      ready.val = true
      progress_host_future_sources(runtime.async_state(), linker.get_store())
      |> ignore
    }
    assert_true(source.get(owned) is None)
    instance.call_exported_func("drop", []) |> ignore
    assert_eq(destroyed.val, 1)
    assert_eq(representation.val, 99)
    runtime.drop_host_readable_future(instance.resource_table, future)
  }
}
