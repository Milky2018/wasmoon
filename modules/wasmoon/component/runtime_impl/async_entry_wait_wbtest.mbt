///|
test "async calls queue while a sibling call waits synchronously" {
  for ready in [false, true] {
    for complete in [false, true] {
      let source =
        #|(component
        #|  (import "host" (func $host async))
        #|  (component $Reader
        #|    (import "host" (func $host async))
        #|    (core func $host (canon lower (func $host) async))
        #|    (type $F (future))
        #|    (core func $read (canon future.read $F))
        #|    (core func $done (canon task.return))
        #|    (core module $M
        #|      (import "" "host" (func $host (result i32)))
        #|      (import "" "done" (func $done))
        #|      (import "" "read" (func $read (param i32 i32) (result i32)))
        #|      (func (export "probe") (result i32) call $host)
        #|      (func (export "first") (param i32) (result i32)
        #|        local.get 0 i32.const 0 call $read drop call $done i32.const 0)
        #|      (func (export "second") (result i32) call $done i32.const 0)
        #|      (func (export "cb") (param i32 i32 i32) (result i32) unreachable))
        #|    (core instance $m (instantiate $M (with "" (instance (export "done" (func $done)) (export "read" (func $read)) (export "host" (func $host))))))
        #|    (func (export "probe") (result u32) (canon lift (core func $m "probe")))
        #|    (func (export "first") async (param "f" $F)
        #|      (canon lift (core func $m "first") async (callback (core func $m "cb"))))
        #|    (func (export "second") async
        #|      (canon lift (core func $m "second") async (callback (core func $m "cb")))))
        #|  (component $Writer
        #|    (type $F (future))
        #|    (import "reader" (instance $reader
        #|      (export "first" (func async (param "f" $F)))
        #|      (export "probe" (func (result u32)))
        #|      (export "second" (func async))))
        #|    (core func $new (canon future.new $F))
        #|    (core func $write (canon future.write $F async))
        #|    (core func $first (canon lower (func $reader "first") async))
        #|    (core func $probe (canon lower (func $reader "probe")))
        #|    (core func $second (canon lower (func $reader "second") async))
        #|    (core func $return (canon task.return (result u32)))
        #|    (core func $set (canon waitable-set.new))
        #|    (core func $join (canon waitable.join))
        #|    (core module $M
        #|      (import "" "new" (func $new (result i64)))
        #|      (import "" "write" (func $write (param i32 i32) (result i32)))
        #|      (import "" "first" (func $first (param i32) (result i32)))
        #|      (import "" "probe" (func $probe (result i32)))
        #|      (import "" "second" (func $second (result i32)))
        #|      (import "" "return" (func $return (param i32)))
        #|      (import "" "set" (func $set (result i32)))
        #|      (import "" "join" (func $join (param i32 i32)))
        #|      (global $ws (mut i32) (i32.const 0))
        #|      (global $left (mut i32) (i32.const 2))
        #|      (func (export "run") (result i32) (local $pair i64) (local $first i32) (local $second i32)
        #|        call $new local.tee $pair i32.wrap_i64 call $first i32.const 4 i32.shr_u local.set $first
        #|        WRITE
        #|        call $probe i32.const 2 i32.ne if unreachable end
        #|        call $second local.tee $second i32.const 15 i32.and if unreachable end
        #|        FINISH)
        #|      (func (export "cb") (param i32 i32 i32) (result i32)
        #|        local.get 0 i32.const 1 i32.ne if unreachable end
        #|        local.get 2 i32.const 2 i32.ne if unreachable end
        #|        global.get $left i32.const 1 i32.sub global.set $left
        #|        global.get $left i32.eqz if (result i32)
        #|          i32.const 42 call $return i32.const 0
        #|        else global.get $ws i32.const 4 i32.shl i32.const 2 i32.or end))
        #|    (core instance $m (instantiate $M (with "" (instance
        #|      (export "new" (func $new)) (export "write" (func $write)) (export "first" (func $first))
        #|      (export "set" (func $set)) (export "join" (func $join))
        #|      (export "probe" (func $probe))
        #|      (export "second" (func $second)) (export "return" (func $return))))))
        #|    (func (export "run") async (result u32)
        #|      (canon lift (core func $m "run") async (callback (core func $m "cb")))))
        #|  (instance $reader (instantiate $Reader (with "host" (func $host))))
        #|  (instance $writer (instantiate $Writer (with "reader" (instance $reader))))
        #|  (export "run" (func $writer "run")))
      let source = source.replace_all(
        old="WRITE",
        new=if ready {
          "local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 i32.const 0 call $write if unreachable end"
        } else {
          ""
        },
      )
      let source = source.replace_all(
        old="FINISH",
        new=if complete {
          (if ready {
            ""
          } else {
            "local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 i32.const 0 call $write if unreachable end "
          }) +
          "call $set global.set $ws local.get $first global.get $ws call $join local.get $second i32.const 4 i32.shr_u global.get $ws call $join global.get $ws i32.const 4 i32.shl i32.const 2 i32.or"
        } else {
          "i32.const 42 call $return i32.const 0"
        },
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
      let host_calls = [0]
      linker.add_import(
        "host",
        Func(
          HostAsync({ is_async: true, params: [], result: None, }, [], fn(
            _,
            _,
          ) {
            host_calls[0] += 1
            HostFuture(fn() { Ready([]) }, fn() { () })
          }),
        ),
      )
      let instance = linker.instantiate("root", validated)
      debug_inspect(instance.call_exported_func("run", []), content="[U32(42)]")
      inspect(host_calls[0], content="1")
    }
  }
}
