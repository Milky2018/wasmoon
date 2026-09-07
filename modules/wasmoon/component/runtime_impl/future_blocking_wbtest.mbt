///|
test "synchronous future operations reject their first wait but accept a ready peer" {
  for reading in [true, false] {
    for ready in [false, true] {
      let source =
        #|(component
        #|  (type $f (future))
        #|  (core func $new (canon future.new $f))
        #|  (core func $read (canon future.read $f READ_MODE))
        #|  (core func $write (canon future.write $f WRITE_MODE))
        #|  (core module $M
        #|    (import "" "new" (func $new (result i64)))
        #|    (import "" "read" (func $read (param i32 i32) (result i32)))
        #|    (import "" "write" (func $write (param i32 i32) (result i32)))
        #|    (func (export "run") (local $pair i64) (local $r i32) (local $w i32)
        #|      call $new local.tee $pair i32.wrap_i64 local.set $r
        #|      local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 local.set $w
        #|      READY
        #|      local.get $TARGET i32.const 0 call $OP if unreachable end))
        #|  (core instance $m (instantiate $M (with "" (instance
        #|    (export "new" (func $new)) (export "read" (func $read)) (export "write" (func $write))))))
        #|  (func (export "run") (canon lift (core func $m "run"))))
      let peer = if !ready {
        ""
      } else if reading {
        "local.get $w i32.const 0 call $write i32.const -1 i32.ne if unreachable end"
      } else {
        "local.get $r i32.const 0 call $read i32.const -1 i32.ne if unreachable end"
      }
      let source = source
        .replace_all(old="READ_MODE", new=if reading { "" } else { "async" })
        .replace_all(old="WRITE_MODE", new=if reading { "async" } else { "" })
        .replace_all(old="READY", new=peer)
        .replace_all(old="TARGET", new=if reading { "r" } else { "w" })
        .replace_all(old="OP", new=if reading { "read" } else { "write" })
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
      if ready {
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
          content="cannot block a synchronous task before returning",
        )
        for entry in instance.async_state.futures {
          let (_, future) = entry
          inspect(
            future.pending_read is None && future.pending_write is None,
            content="true",
          )
        }
      }
    }
  }
}
