///|
test "component compute obeys shared Store execution limits and recovers" {
  let source =
    #|(component
    #|  (core module $m
    #|    (func (export "run") (param i32) (result i32)
    #|      local.get 0
    #|      if (loop $forever br $forever) end
    #|      i32.const 42))
    #|  (core instance $i (instantiate $m))
    #|  (func (export "run") (param "spin" u32) (result u32)
    #|    (canon lift (core func $i "run"))))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  let budget = @runtime.ResourceBudget::new(instances=100L)
  for native in [false, true] {
    for mode in 0..<3 {
      let engine = if native {
        open_native_component_session(opt_level=0)
      } else {
        @runtime_impl.interpreter_core_execution_engine()
      }
      let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
        engine,
        resource_budget=Some(budget),
      )
      let instance = linker.instantiate("limited", validated)
      let store = linker.get_store()
      assert_eq(instance.call_exported_func("run", [U32(0)]), [U32(42)])
      let polls = Ref(0)
      try
        store.with_execution_limits(
          () => instance.call_exported_func("run", [U32(1)]),
          safepoints=if mode == 0 { Some(32L) } else { None },
          timeout_ms=if mode == 1 { Some(2) } else { None },
          cancel=if mode == 2 {
            Some(fn() {
              polls.val += 1
              polls.val > 8
            })
          } else {
            None
          },
        )
      catch {
        @runtime_impl.ComponentRuntimeError::ExecutionBudgetExceeded if mode ==
          0 => ()
        @runtime_impl.ComponentRuntimeError::ExecutionTimedOut if mode == 1 =>
          ()
        @runtime_impl.ComponentRuntimeError::Cancelled if mode == 2 => ()
        error => fail("native=\{native}, mode=\{mode}: \{error}")
      } noraise {
        _ => fail("missing compute interruption")
      }
      // Canonical ABI traps poison the component Store; cleanup must not reset it.
      try instance.call_exported_func("run", [U32(0)]) catch {
        CanonCallError(message) => assert_true(message.contains("cannot enter"))
        error => fail(error.to_string())
      } noraise {
        _ => fail("trapped component unexpectedly remained enterable")
      }
      linker.close()
      assert_eq(budget.used(Instances), 0L)
      let replacement_engine = if native {
        open_native_component_session(opt_level=0)
      } else {
        @runtime_impl.interpreter_core_execution_engine()
      }
      let replacement = @runtime_impl.ComponentLinker::with_core_execution_engine(
        replacement_engine,
        resource_budget=Some(budget),
      )
      let healthy = replacement.instantiate("healthy", validated)
      assert_eq(healthy.call_exported_func("run", [U32(0)]), [U32(42)])
      replacement.close()
      assert_eq(budget.used(Instances), 0L)
    }
  }
}

///|
async test "pure component compute yields to language cancellation and cleans parked work" {
  let source =
    #|(component
    #|  (core module $m (func (export "run") (loop $forever br $forever)))
    #|  (core instance $i (instantiate $m))
    #|  (func (export "run") async (canon lift (core func $i "run") async)))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  for native in [false, true] {
    let budget = @runtime.ResourceBudget::new(pending_work=16L)
    let engine = if native {
      open_native_component_session(opt_level=0)
    } else {
      @runtime_impl.interpreter_core_execution_engine()
    }
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
      resource_budget=Some(budget),
    )
    defer linker.close()
    let instance = linker.instantiate("cancelled", validated)
    let invocation = linker
      .get_store()
      .with_execution_limits(
        () => instance.start_exported_func("run", []),
        // Fail boundedly if cooperative scheduling regresses and starves the async timer.
        timeout_ms=Some(500),
      )
    try @async.with_timeout(10, () => invocation.join()) catch {
      @async.TimeoutError => ()
      error => fail("native=\{native}: \{error}")
    } noraise {
      _ => fail("infinite compute returned")
    }
    invocation.cancel()
    linker.close()
    assert_eq(budget.used(PendingWork), 0L)
    assert_eq(budget.used(Instances), 0L)
  }
}

///|
test "component native code quota rolls back instantiation and remains classified" {
  let source =
    #|(component
    #|  (core module $m (func (export "run")))
    #|  (core instance $i (instantiate $m))
    #|  (func (export "run") (canon lift (core func $i "run"))))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  let budget = @runtime.ResourceBudget::new(code_bytes=0L)
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
    open_native_component_session(opt_level=0),
    resource_budget=Some(budget),
  )
  defer linker.close()
  try linker.instantiate("denied", validated) catch {
    ResourceLimitExceeded(CodeBytes) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("native installation ignored the host quota")
  }
  assert_eq(budget.used(CodeBytes), 0L)
  assert_eq(budget.used(Instances), 0L)
  let empty = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(
      @component_text.parse_component_wat("(component)"),
    ),
    ComponentValidationConfig(false),
  )
  linker.instantiate("healthy", empty) |> ignore
  linker.close()
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "native and interpreter GC allocation cannot bypass payload admission" {
  let source =
    #|(component
    #|  (core module $m
    #|    (type $s (struct (field i32)))
    #|    (global $saved (mut (ref null $s)) (ref.null $s))
    #|    (func (export "clear") ref.null $s global.set $saved)
    #|    (func (export "run") (result i32)
    #|      i32.const 1 struct.new $s global.set $saved i32.const 42))
    #|  (core instance $i (instantiate $m))
    #|  (func (export "clear") (canon lift (core func $i "clear")))
    #|  (func (export "run") (result u32) (canon lift (core func $i "run"))))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  for native in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_bytes=32L, gc_objects=4L)
    let engine = if native {
      open_native_component_session(opt_level=0)
    } else {
      @runtime_impl.interpreter_core_execution_engine()
    }
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
      resource_budget=Some(budget),
    )
    defer linker.close()
    let instance = linker.instantiate("limited", validated)
    assert_eq(instance.call_exported_func("run", []), [U32(42)])
    assert_eq(budget.used(GcBytes), 32L)
    instance.call_exported_func("clear", []) |> ignore
    linker.get_store().collect_garbage() |> ignore
    assert_eq(budget.used(GcBytes), 0L)
    assert_eq(instance.call_exported_func("run", []), [U32(42)])
    try instance.call_exported_func("run", []) catch {
      ResourceLimitExceeded(GcBytes) => ()
      error => fail("native=\{native}: \{error}")
    } noraise {
      _ => fail("native=\{native}: GC allocation bypassed host quota")
    }
    linker.close()
    assert_eq(budget.used(GcBytes), 0L)
    assert_eq(budget.used(GcObjects), 0L)
  }
}
