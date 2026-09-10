///|
test "error context debug output validates its complete descriptor before storing" {
  for native in [false, true] {
    for pointer in [65528, 65527, 65532, -4] {
      let source =
        #|(component
        #|  (core module $Mem
        #|    (memory (export "memory") 1)
        #|    (data (i32.const 0) "a")
        #|    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
        #|      i32.const 96 i32.const 96 i32.load i32.const 1 i32.add i32.store
        #|      i32.const 32))
        #|  (core instance $mem (instantiate $Mem))
        #|  (core func $new (canon error-context.new (memory (core memory $mem "memory"))))
        #|  (core func $debug (canon error-context.debug-message
        #|    (memory (core memory $mem "memory")) (realloc (core func $mem "realloc"))))
        #|  (core module $M
        #|    (import "" "new" (func $new (param i32 i32) (result i32)))
        #|    (import "" "debug" (func $debug (param i32 i32)))
        #|    (import "" "memory" (memory 1))
        #|    (func (export "run") (param i32)
        #|      i32.const 65532 i32.const 123 i32.store
        #|      i32.const 0 i32.const 1 call $new local.get 0 call $debug))
        #|  (core instance $m (instantiate $M (with "" (instance
        #|    (export "new" (func $new)) (export "debug" (func $debug))
        #|    (export "memory" (memory $mem "memory"))))))
        #|  (func (export "run") (param "p" u32) (canon lift (core func $m "run"))))
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
      let message = try {
        instance.call_exported_func("run", [U32(pointer)]) |> ignore
        "returned"
      } catch {
        error => error.to_string()
      }
      if pointer == 65532 || pointer == -4 {
        inspect(
          message.contains("invalid debug message pointer"),
          content="true",
        )
        // Read guest memory directly after the trapping component entry is poisoned.
        let memory = instance.store.get_mem(instance.core_mems[0])
        inspect(memory.load_i32(65532), content="123")
        inspect(memory.load_i32(96), content="1")
      } else {
        inspect(message, content="returned")
      }
    }
  }
}
