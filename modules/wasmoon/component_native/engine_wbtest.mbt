///|
test "failed component instantiation closes native JIT registrations" {
  let provider_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $provider
      #|    (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $provider (instantiate $provider)))
      #|
    ),
  )
  let provider = @component.parse_component(provider_bytes)
  let provider_validated = @component_validator.validate_component_for_instantiation_with_config(
    provider,
    ComponentValidationConfig(false),
  )
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $ok
      #|    (table 1 funcref)
      #|    (memory 1)
      #|    (global i32 (i32.const 1))
      #|    (func (export "f") (result i32) (i32.const 1)))
      #|  (core instance $registered (instantiate $ok))
      #|  (core module $boom (func $start unreachable) (start $start))
      #|  (core instance $trapped (instantiate $boom)))
      #|
    ),
  )
  let component = @component.parse_component(bytes)
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(false),
  )
  let (engine, contexts) = native_component_session_with_contexts(0, fn(
    _event,
  ) {
    ()
  })
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(engine)
  linker.instantiate("provider", provider_validated) |> ignore
  let baseline = contexts.length()
  inspect(baseline, content="1")
  for root_name in ["first", "second"] {
    try linker.instantiate(root_name, validated) catch {
      _ => ()
    } noraise {
      _ => fail("expected core start to trap")
    }
    inspect(contexts.length() == baseline, content="true")
  }
  linker.close()
}

///|
test "failed native registration cannot reappear at a reused Store index" {
  let failing_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $old
      #|    (func (export "f") (result i32) (i32.const 1)))
      #|  (core instance $old (instantiate $old))
      #|  (core module $boom (func $start unreachable) (start $start))
      #|  (core instance $trapped (instantiate $boom)))
      #|
    ),
  )
  let failing = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(failing_bytes),
    ComponentValidationConfig(false),
  )
  let failed_linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
    open_native_component_session(opt_level=0),
  )
  try failed_linker.instantiate("failed", failing) catch {
    _ => ()
  } noraise {
    _ => fail("expected core start to trap")
  }
  failed_linker.close()
  let provider_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $new
      #|    (func (export "f") (result i32) (i32.const 2)))
      #|  (core instance $new (instantiate $new)))
      #|
    ),
  )
  let provider = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(provider_bytes),
    ComponentValidationConfig(false),
  )
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
    open_native_component_session(opt_level=0),
  )
  linker.instantiate("new", provider) |> ignore
  inspect(
    @wast.collect_registered_funcref_entries(linker.get_store()).length(),
    content="1",
  )
  linker.close()
}

///|
test "native funcref registrations are isolated between live Stores" {
  let provider_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $provider
      #|    (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $provider (instantiate $provider)))
      #|
    ),
  )
  let provider = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(provider_bytes),
    ComponentValidationConfig(false),
  )
  let first = @runtime_impl.ComponentLinker::with_core_execution_engine(
    open_native_component_session(opt_level=0),
  )
  let second = @runtime_impl.ComponentLinker::with_core_execution_engine(
    open_native_component_session(opt_level=0),
  )
  first.instantiate("first", provider) |> ignore
  second.instantiate("second", provider) |> ignore
  inspect(
    @wast.collect_registered_funcref_entries(first.get_store()).length(),
    content="1",
  )
  inspect(
    @wast.collect_registered_funcref_entries(second.get_store()).length(),
    content="1",
  )
  second.close()
  inspect(
    @wast.collect_registered_funcref_entries(first.get_store()).length(),
    content="1",
  )
  first.close()
}

///|
test "admitted continuations resume after a trap while new host calls are rejected" {
  for native in [false, true] {
    let source =
      #|(component
      #|  (type $f (future))
      #|  (core func $yield (canon thread.yield))
      #|  (core func $write (canon future.write $f async))
      #|  (core module $M
      #|    (import "" "yield" (func $yield (result i32)))
      #|    (import "" "write" (func $write (param i32 i32) (result i32)))
      #|    (func (export "run") call $yield drop i32.const 42 i32.const 0 call $write drop))
      #|  (core instance $m (instantiate $M (with "" (instance
      #|    (export "yield" (func $yield)) (export "write" (func $write))))))
      #|  (func (export "run") async (canon lift (core func $m "run") async)))
    let validated = @component_validator.validate_component_for_instantiation_with_config(
      @component.parse_component(@component_text.parse_component_wat(source)),
      ComponentValidationConfig(false),
    )
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      if native {
        open_native_component_session(opt_level=0)
      } else {
        @runtime_impl.interpreter_core_execution_engine()
      },
    )
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    let plain_source =
      #|(component
      #| (core func $yield (canon thread.yield))
      #| (component $Child
      #|  (core module $Inner (func (export "trap") unreachable))
      #|  (core instance $inner (instantiate $Inner))
      #|  (func (export "trap") (canon lift (core func $inner "trap"))))
      #| (instance $child (instantiate $Child))
      #| (core func $trap (canon lower (func $child "trap")))
      #| (core module $M
      #|  (import "" "yield" (func $yield (result i32)))
      #|  (import "" "trap" (func $trap))
      #|  (func (export "run") call $yield drop call $trap))
      #| (core instance $m (instantiate $M (with "" (instance
      #|  (export "yield" (func $yield)) (export "trap" (func $trap))))))
      #| (func (export "run") async (canon lift (core func $m "run") async)))
    let plain = @component_validator.validate_component_for_instantiation_with_config(
      @component.parse_component(
        @component_text.parse_component_wat(plain_source),
      ),
      ComponentValidationConfig(false),
    )
    let plain_instance = linker.instantiate("plain", plain)
    let plain_invocation = plain_instance.start_exported_func("run", [])
    debug_inspect(plain_invocation.poll(), content="InvocationPending")
    let invocation = instance.start_exported_func("run", [])
    debug_inspect(invocation.poll(), content="InvocationPending")
    let error = try {
      invocation.wait() |> ignore
      "unexpected return"
    } catch {
      error => error.to_string()
    }
    inspect(error, content="CanonCallError(\"unknown future handle index 42\")")
    for asynchronous in [false, true] {
      let rejected = try {
        if asynchronous {
          plain_instance.start_exported_func("run", []) |> ignore
        } else {
          plain_instance.call_exported_func("run", []) |> ignore
        }
        "unexpected return"
      } catch {
        error => error.to_string()
      }
      inspect(
        rejected,
        content="CanonCallError(\"cannot enter component instance\")",
      )
    }
    let plain_error = try {
      plain_invocation.wait() |> ignore
      "unexpected return"
    } catch {
      error => error.to_string()
    }
    inspect(
      plain_error,
      content="CanonCallError(\"wasm trap: wasm `unreachable` instruction executed (core=plain::component0::coreinst0 func_idx=0)\")",
    )
  }
}
