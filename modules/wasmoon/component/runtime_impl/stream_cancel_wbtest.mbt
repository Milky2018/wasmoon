///|
test "stream cancellation consumes completion events and remembers peer closure" {
  for reading in [true, false] {
    for retry in [false, true] {
      let source =
        #|(component
        #|  (core module $mem (memory (export "m") 1))
        #|  (core instance $mem (instantiate $mem))
        #|  (type $s (stream))
        #|  (core func $new (canon stream.new $s))
        #|  (core func $op (canon stream.OP $s async))
        #|  (core func $cancel (canon stream.cancel-OP $s async))
        #|  (core func $drop (canon stream.drop-PEER $s))
        #|  (core func $set (canon waitable-set.new))
        #|  (core func $join (canon waitable.join))
        #|  (core func $poll (canon waitable-set.poll (memory (core memory $mem "m"))))
        #|  (core module $M
        #|    (import "" "new" (func $new (result i64)))
        #|    (import "" "op" (func $op (param i32 i32 i32) (result i32)))
        #|    (import "" "cancel" (func $cancel (param i32) (result i32)))
        #|    (import "" "drop" (func $drop (param i32)))
        #|    (import "" "set" (func $set (result i32)))
        #|    (import "" "join" (func $join (param i32 i32)))
        #|    (import "" "poll" (func $poll (param i32 i32) (result i32)))
        #|    (func (export "run") (result i32) (local $pair i64) (local $end i32) (local $peer i32) (local $ws i32)
        #|      call $new local.set $pair
        #|      local.get $pair i64.const END_SHIFT i64.shr_u i32.wrap_i64 local.set $end
        #|      local.get $pair i64.const PEER_SHIFT i64.shr_u i32.wrap_i64 local.set $peer
        #|      call $set local.set $ws
        #|      local.get $end local.get $ws call $join
        #|      local.get $end i32.const 0 i32.const 1 call $op
        #|      i32.const -1 i32.ne if unreachable end
        #|      local.get $peer call $drop
        #|      local.get $end call $cancel i32.const 1 i32.ne if unreachable end
        #|      FINAL))
        #|  (core instance $m (instantiate $M (with "" (instance
        #|    (export "new" (func $new)) (export "op" (func $op))
        #|    (export "cancel" (func $cancel)) (export "drop" (func $drop))
        #|    (export "set" (func $set)) (export "join" (func $join)) (export "poll" (func $poll))))))
        #|  (func (export "run") (result u32) (canon lift (core func $m "run"))))
      let source = source
        .replace_all(old="OP", new=if reading { "read" } else { "write" })
        .replace_all(old="END_SHIFT", new=if reading { "0" } else { "32" })
        .replace_all(old="PEER_SHIFT", new=if reading { "32" } else { "0" })
        .replace_all(
          old="PEER",
          new=if reading { "writable" } else { "readable" },
        )
        .replace_all(
          old="FINAL",
          new=if retry {
            "local.get $end i32.const 0 i32.const 1 call $op"
          } else {
            "local.get $ws i32.const 0 call $poll"
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
      let instance = linker.instantiate("root", validated)
      if retry {
        let error = try {
          instance.call_exported_func("run", []) |> ignore
          "unexpected return"
        } catch {
          error => canon_err_message(error)
        }
        inspect(
          error,
          content=if reading {
            "cannot read after being notified that the writable end dropped"
          } else {
            "cannot write after being notified that the readable end dropped"
          },
        )
      } else {
        debug_inspect(
          instance.call_exported_func("run", []),
          content="[U32(0)]",
        )
      }
    }
  }
}
