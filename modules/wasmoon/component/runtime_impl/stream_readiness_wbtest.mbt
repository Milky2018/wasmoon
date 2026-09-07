///|
test "zero-length stream readiness completes only the writer until data arrives" {
  for read_first in [true, false] {
    let source =
      #|(component
      #|  (core module $memory (memory (export "m") 1))
      #|  (core instance $memory (instantiate $memory))
      #|  (type $s (stream))
      #|  (core func $new (canon stream.new $s))
      #|  (core func $read (canon stream.read $s async))
      #|  (core func $write (canon stream.write $s async))
      #|  (core func $set (canon waitable-set.new))
      #|  (core func $join (canon waitable.join))
      #|  (core func $poll (canon waitable-set.poll (memory (core memory $memory "m"))))
      #|  (core module $M
      #|    (import "" "m" (memory 1))
      #|    (import "" "new" (func $new (result i64)))
      #|    (import "" "read" (func $read (param i32 i32 i32) (result i32)))
      #|    (import "" "write" (func $write (param i32 i32 i32) (result i32)))
      #|    (import "" "set" (func $set (result i32)))
      #|    (import "" "join" (func $join (param i32 i32)))
      #|    (import "" "poll" (func $poll (param i32 i32) (result i32)))
      #|    (func (export "run") (local $pair i64) (local $r i32) (local $w i32) (local $ws i32)
      #|      call $new local.tee $pair i32.wrap_i64 local.set $r
      #|      local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 local.set $w
      #|      call $set local.set $ws
      #|      local.get $r local.get $ws call $join
      #|      local.get $w local.get $ws call $join
      #|      INITIAL
      #|      local.get $ws i32.const 0 call $poll if unreachable end
      #|      local.get $w i32.const 0 i32.const 0 call $write if unreachable end
      #|      local.get $ws i32.const 0 call $poll if unreachable end
      #|      local.get $w i32.const 0 i32.const 1 call $write
      #|      i32.const -1 i32.ne if unreachable end
      #|      local.get $ws i32.const 0 call $poll i32.const 2 i32.ne if unreachable end
      #|      i32.const 0 i32.load local.get $r i32.ne if unreachable end
      #|      i32.const 4 i32.load if unreachable end
      #|      local.get $r i32.const 0 i32.const 1 call $read i32.const 16 i32.ne if unreachable end
      #|      local.get $ws i32.const 0 call $poll i32.const 3 i32.ne if unreachable end
      #|      i32.const 0 i32.load local.get $w i32.ne if unreachable end
      #|      i32.const 4 i32.load i32.const 16 i32.ne if unreachable end
      #|      local.get $ws i32.const 0 call $poll if unreachable end))
      #|  (core instance $m (instantiate $M (with "" (instance
      #|    (export "m" (memory $memory "m")) (export "new" (func $new))
      #|    (export "read" (func $read)) (export "write" (func $write))
      #|    (export "set" (func $set)) (export "join" (func $join)) (export "poll" (func $poll))))))
      #|  (func (export "run") (canon lift (core func $m "run"))))
    let initial = if read_first {
      (
        #|local.get $r i32.const 0 i32.const 0 call $read i32.const -1 i32.ne if unreachable end
        #|local.get $w i32.const 0 i32.const 0 call $write if unreachable end
      )
    } else {
      (
        #|local.get $w i32.const 0 i32.const 0 call $write i32.const -1 i32.ne if unreachable end
        #|local.get $r i32.const 0 i32.const 0 call $read i32.const -1 i32.ne if unreachable end
        #|local.get $ws i32.const 0 call $poll i32.const 3 i32.ne if unreachable end
        #|i32.const 0 i32.load local.get $w i32.ne if unreachable end
        #|i32.const 4 i32.load if unreachable end
      )
    }
    let component = @component.parse_component(
      @component_text.parse_component_wat(
        source.replace_all(old="INITIAL", new=initial),
      ),
    )
    let validated = @component_validator.validate_component_for_instantiation_with_config(
      component,
      ComponentValidationConfig(false),
    )
    let linker = ComponentLinker::ComponentLinker()
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    debug_inspect(instance.call_exported_func("run", []), content="[]")
  }
}

///|
test "payloadless streams bound element counts without allocating payload bytes" {
  let source =
    #|(component
    #|  (type $s (stream))
    #|  (core func $new (canon stream.new $s))
    #|  (core func $read (canon stream.read $s async))
    #|  (core func $write (canon stream.write $s async))
    #|  (core module $M
    #|    (import "" "new" (func $new (result i64)))
    #|    (import "" "read" (func $read (param i32 i32 i32) (result i32)))
    #|    (import "" "write" (func $write (param i32 i32 i32) (result i32)))
    #|    (func (export "run") (param $len i32) (result i32) (local $pair i64)
    #|      call $new local.set $pair
    #|      local.get $pair i32.wrap_i64 i32.const -1 local.get $len call $read
    #|      i32.const -1 i32.ne if unreachable end
    #|      local.get $pair i64.const 32 i64.shr_u i32.wrap_i64
    #|      i32.const -1 local.get $len call $write))
    #|  (core instance $m (instantiate $M (with "" (instance
    #|    (export "new" (func $new)) (export "read" (func $read)) (export "write" (func $write))))))
    #|  (func (export "run") (param "len" u32) (result u32) (canon lift (core func $m "run"))))
  let component = @component.parse_component(
    @component_text.parse_component_wat(source),
  )
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(false),
  )
  for count in [0x10000000U, 0xffffffffU, 0x0fffffffU] {
    let linker = ComponentLinker::ComponentLinker()
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    if count > 0x0fffffffU {
      let error = try {
        instance.call_exported_func("run", [U32(count.reinterpret_as_int())])
        |> ignore
        "unexpected return"
      } catch {
        error => canon_err_message(error)
      }
      inspect(error, content="stream read/write count too large")
    } else {
      debug_inspect(
        instance.call_exported_func("run", [U32(count.reinterpret_as_int())]),
        content="[U32(-16)]",
      )
    }
  }
}
