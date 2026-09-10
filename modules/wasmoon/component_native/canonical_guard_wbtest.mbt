///|
test "intra-component streams permit only numeric payloads in either rendezvous order" {
  for native in [false, true] {
    for payload in ["string", "bool", "u64", ""] {
      for writer_first in [false, true] {
        let source =
          #|(component
          #|  (core module $Mem
          #|    (memory (export "memory") 1)
          #|    (func (export "realloc") (param i32 i32 i32 i32) (result i32) i32.const 64))
          #|  (core instance $mem (instantiate $Mem))
          #|  (type $s (stream PAYLOAD))
          #|  (core func $new (canon stream.new $s))
          #|  (core func $read (canon stream.read $s async (memory (core memory $mem "memory"))
          #|    (realloc (core func $mem "realloc"))))
          #|  (core func $write (canon stream.write $s async (memory (core memory $mem "memory"))))
          #|  (core module $M
          #|    (import "" "new" (func $new (result i64)))
          #|    (import "" "read" (func $read (param i32 i32 i32) (result i32)))
          #|    (import "" "write" (func $write (param i32 i32 i32) (result i32)))
          #|    (func (export "run") (local $ends i64) (local $r i32) (local $w i32)
          #|      call $new local.set $ends local.get $ends i32.wrap_i64 local.set $r
          #|      local.get $ends i64.const 32 i64.shr_u i32.wrap_i64 local.set $w
          #|      FIRST i32.const -1 i32.ne if unreachable end
          #|      SECOND i32.const 16 i32.ne if unreachable end))
          #|  (core instance $m (instantiate $M (with "" (instance
          #|    (export "new" (func $new)) (export "read" (func $read)) (export "write" (func $write))))))
          #|  (func (export "run") (canon lift (core func $m "run"))))
        let read = "local.get $r i32.const 16 i32.const 1 call $read"
        let write = "local.get $w i32.const 0 i32.const 1 call $write"
        let source = source
          .replace_all(old="PAYLOAD", new=payload)
          .replace_all(old="FIRST", new=if writer_first { write } else { read })
          .replace_all(
            old="SECOND",
            new=if writer_first { read } else { write },
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
        if payload == "u64" || payload == "" {
          debug_inspect(instance.call_exported_func("run", []), content="[]")
        } else {
          let message = try {
            instance.call_exported_func("run", []) |> ignore
            "unexpected return"
          } catch {
            error => error.to_string()
          }
          guard message.contains(
            "cannot read from and write to intra-component future/stream with non-numeric payload",
          ) else {
            fail(
              "native=\{native}, payload=\{payload}, writer_first=\{writer_first}: \{message}",
            )
          }
        }
      }
    }
  }
}

///|
test "thread promotion checks post-return restrictions before unsupported operation" {
  for native in [false, true] {
    for
      operation in ["thread.suspend-then-promote", "thread.yield-then-promote"] {
      for post in [false, true] {
        let source =
          #|(component
          #|  (core func $promote (canon OPERATION))
          #|  (core module $M
          #|    (import "" "promote" (func $promote (param i32) (result i32)))
          #|    (func (export "noop"))
          #|    (func (export "promote") i32.const 0 call $promote drop))
          #|  (core instance $m (instantiate $M (with "" (instance (export "promote" (func $promote))))))
          #|  (func (export "run") (canon lift (core func $m "ENTRY") POST)))
        let source = source
          .replace_all(old="OPERATION", new=operation)
          .replace_all(old="ENTRY", new=if post { "noop" } else { "promote" })
          .replace_all(
            old="POST",
            new=if post {
              "(post-return (core func $m \"promote\"))"
            } else {
              ""
            },
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
        let message = try {
          instance.call_exported_func("run", []) |> ignore
          "unexpected return"
        } catch {
          error => error.to_string()
        }
        guard message.contains(
          if post {
            "cannot leave component instance"
          } else {
            "\{operation} is not implemented"
          },
        ) else {
          fail(message)
        }
      }
    }
  }
}
