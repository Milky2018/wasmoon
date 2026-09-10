///|
test "async drivers preserve string arguments and run post-return exactly once" {
  for native in [false, true] {
    for async_lower in [false, true] {
      for yielding in [false, true] {
        let source =
          #|(component
          #|  (component $A
          #|    (core func $yield (canon thread.yield))
          #|    (core module $M
          #|      (import "" "yield" (func $yield (result i32)))
          #|      (memory (export "memory") 1)
          #|      (global $posts (mut i32) (i32.const 0))
          #|      (func (export "realloc") (param i32 i32 i32 i32) (result i32) i32.const 64)
          #|      (func (export "echo") (param i32 i32) (result i32)
          #|        YIELD
          #|        i32.const 0 local.get 0 i32.store
          #|        i32.const 4 local.get 1 i32.store i32.const 0)
          #|      (func (export "post") (param i32)
          #|        global.get $posts i32.const 1 i32.add global.set $posts
          #|        i32.const 64 i32.const 0 i32.store)
          #|      (func (export "posts") (result i32) global.get $posts))
          #|    (core instance $m (instantiate $M (with "" (instance (export "yield" (func $yield))))))
          #|    (func (export "echo") async (param "x" string) (result string)
          #|      (canon lift (core func $m "echo") (memory (core memory $m "memory"))
          #|        (realloc (core func $m "realloc")) (post-return (core func $m "post"))))
          #|    (func (export "posts") (result u32) (canon lift (core func $m "posts"))))
          #|  (component $B
          #|    (import "echo" (func $echo async (param "x" string) (result string)))
          #|    (core module $Mem
          #|      (memory (export "memory") 1)
          #|      (data (i32.const 32) "hello")
          #|      (func (export "realloc") (param i32 i32 i32 i32) (result i32) i32.const 64))
          #|    (core instance $mem (instantiate $Mem))
          #|    (core func $echo (canon lower (func $echo) ASYNC
          #|      (memory (core memory $mem "memory")) (realloc (core func $mem "realloc"))))
          #|    (core func $new (canon waitable-set.new))
          #|    (core func $join (canon waitable.join))
          #|    (core func $wait (canon waitable-set.wait (memory (core memory $mem "memory"))))
          #|    (core func $drop (canon subtask.drop))
          #|    (core func $drop-set (canon waitable-set.drop))
          #|    (core module $M
          #|      (import "" "echo" (func $echo (param i32 i32 i32) RESULT))
          #|      (import "" "memory" (memory 1))
          #|      (import "" "new" (func $new (result i32)))
          #|      (import "" "join" (func $join (param i32 i32)))
          #|      (import "" "wait" (func $wait (param i32 i32) (result i32)))
          #|      (import "" "drop" (func $drop (param i32)))
          #|      (import "" "drop-set" (func $drop-set (param i32)))
          #|      (func (export "run") (result i32) (local $status i32) (local $task i32) (local $set i32)
          #|        i32.const 32 i32.const 5 i32.const 8 call $echo WAIT
          #|        (if (i32.ne (i32.load (i32.const 12)) (i32.const 5)) (then unreachable))
          #|        (if (i32.ne (i32.load (i32.load (i32.const 8))) (i32.const 0x6c6c6568)) (then unreachable))
          #|        (if (i32.ne (i32.load8_u offset=4 (i32.load (i32.const 8))) (i32.const 111)) (then unreachable))
          #|        i32.const 42))
          #|    (core instance $m (instantiate $M (with "" (instance
          #|      (export "echo" (func $echo)) (export "memory" (memory $mem "memory"))
          #|      (export "new" (func $new)) (export "join" (func $join)) (export "wait" (func $wait))
          #|      (export "drop" (func $drop)) (export "drop-set" (func $drop-set))))))
          #|    (func (export "run") async (result u32) (canon lift (core func $m "run"))))
          #|  (instance $a (instantiate $A))
          #|  (instance $b (instantiate $B (with "echo" (func $a "echo"))))
          #|  (export "run" (func $b "run")) (export "posts" (func $a "posts")))
        let wait =
          #|local.set $status
          #|local.get $status i32.const 4 i32.shr_u local.set $task
          #|(if (i32.ne (i32.and (local.get $status) (i32.const 15)) (i32.const 2)) (then
          #|  call $new local.set $set
          #|  local.get $task local.get $set call $join
          #|  local.get $set i32.const 16 call $wait drop
          #|  local.get $task i32.const 0 call $join
          #|  local.get $set call $drop-set))
          #|(if (local.get $task) (then local.get $task call $drop))
        let source = source
          .replace_all(
            old="YIELD",
            new=if yielding { "call $yield drop" } else { "" },
          )
          .replace_all(old="ASYNC", new=if async_lower { "async" } else { "" })
          .replace_all(
            old="RESULT",
            new=if async_lower { "(result i32)" } else { "" },
          )
          .replace_all(old="WAIT", new=if async_lower { wait } else { "" })
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
        for count in 1..<3 {
          debug_inspect(
            instance.call_exported_func("run", []),
            content="[U32(42)]",
          )
          let posts = instance.call_exported_func("posts", [])
          guard posts is [U32(actual)] && actual == count else {
            fail("post-return count mismatch")
          }
        }
      }
    }
  }
}
