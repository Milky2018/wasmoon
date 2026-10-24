///|
fn prepared_test_component(
  source : String,
) -> @component_validator.ValidatedComponent raise {
  @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
}

///|
test "prepared code avoids compilation across independent live Stores" {
  let component = prepared_test_component(
    (
      #|(component
      #| (core module $M
      #|  (global $g (mut i32) (i32.const 40))
      #|  (func $start i32.const 41 global.set $g) (start $start)
      #|  (func (export "next") (result i32)
      #|   global.get $g i32.const 1 i32.add global.set $g global.get $g))
      #| (core instance $m (instantiate $M))
      #| (func (export "next") (result u32) (canon lift (core func $m "next"))))
    ),
  )
  let code = prepare_native_component_code([component], opt_level=0)
  let compilations = Ref(0)
  fn session() -> @runtime_impl.ComponentLinker raise {
    let (engine, _) = native_component_session_with_contexts(
      0,
      fn(_) { () },
      prepared_code=Some(code),
      on_compile=fn() { compilations.val += 1 },
    )
    @runtime_impl.ComponentLinker::with_core_execution_engine(engine)
  }
  let first = session()
  defer first.close()
  let second = session()
  defer second.close()
  let a = first.instantiate("a", component)
  let b = second.instantiate("b", component)
  assert_true(a.call_exported_func("next", []) is [U32(42)])
  assert_true(a.call_exported_func("next", []) is [U32(43)])
  first.close()
  assert_true(b.call_exported_func("next", []) is [U32(42)])
  let third = session()
  defer third.close()
  let c = third.instantiate("c", component)
  assert_true(c.call_exported_func("next", []) is [U32(42)])
  inspect(compilations.val, content="0")
}

///|
test "prepared code does not execute guest start or retain failed instances" {
  let component = prepared_test_component(
    (
      #|(component
      #| (core module $M (func $start unreachable) (start $start))
      #| (core instance $m (instantiate $M)))
    ),
  )
  let code = prepare_native_component_code([component], opt_level=0)
  for _ in 0..<2 {
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      code.open_session(),
    )
    defer linker.close()
    let before = linker.get_store().counts()
    try linker.instantiate("trapping", component) catch {
      _ => ()
    } noraise {
      _ => fail("expected guest start to trap only during instantiation")
    }
    debug_inspect(
      linker.get_store().counts(),
      content=before.to_repr().to_string(),
    )
  }
}

///|
test "prepared code rejects reuse when imported globals become aliases" {
  for aliased in [false, true] {
    let second = if aliased { "a" } else { "b" }
    let source =
      $|(component
      $| (core module $P
      $|  (global (export "a") (mut i32) (i32.const 7))
      $|  (global (export "b") (mut i32) (i32.const 9)))
      $| (core instance $p (instantiate $P))
      $| (core module $C
      $|  (import "env" "x" (global $x (mut i32)))
      $|  (import "env" "y" (global $y (mut i32)))
      $|  (func (export "run") (result i32)
      $|   i32.const 42 global.set $x global.get $y))
      $| (core instance $c (instantiate $C (with "env" (instance
      $|  (export "x" (global $p "a"))
      $|  (export "y" (global $p "\{second}"))))))
      $| (func (export "run") (result u32) (canon lift (core func $c "run"))))
    let component = prepared_test_component(source)
    let code = prepare_native_component_code([component], opt_level=0)
    let size = code.artifacts.length()
    let compilations = Ref(0)
    let (engine, _) = native_component_session_with_contexts(
      0,
      fn(_) { () },
      prepared_code=Some(code),
      on_compile=fn() { compilations.val += 1 },
    )
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
    )
    defer linker.close()
    let instance = linker.instantiate("root", component)
    assert_true(
      instance.call_exported_func("run", []) is [U32(value)] &&
      value == (if aliased { 42 } else { 9 }),
    )
    assert_eq(compilations.val, if aliased { 1 } else { 0 })
    assert_eq(code.artifacts.length(), size)
  }
}

///|
test "prepared code matches actual imported memory maximum before reuse" {
  for maximum in [2, 4] {
    let source =
      $|(component
      $| (core module $P (memory (export "memory") 1 \{maximum}))
      $| (core instance $p (instantiate $P))
      $| (core module $C
      $|  (import "" "memory" (memory 1 4))
      $|  (func (export "grow") (param i32) (result i32)
      $|   local.get 0 memory.grow))
      $| (core instance $c (instantiate $C (with "" (instance
      $|  (export "memory" (memory $p "memory"))))))
      $| (func (export "grow") (param "pages" u32) (result u32)
      $|  (canon lift (core func $c "grow"))))
    let component = prepared_test_component(source)
    let code = prepare_native_component_code([component], opt_level=0)
    let compilations = Ref(0)
    let (engine, _) = native_component_session_with_contexts(
      0,
      fn(_) { () },
      prepared_code=Some(code),
      on_compile=fn() { compilations.val += 1 },
    )
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
    )
    defer linker.close()
    let instance = linker.instantiate("root", component)
    assert_true(
      instance.call_exported_func("grow", [U32(2)]) is [U32(value)] &&
      value == (if maximum == 2 { -1 } else { 1 }),
    )
    assert_eq(compilations.val, if maximum == 2 { 1 } else { 0 })
  }
}

///|
test "prepared code retains installation quotas and failure rollback" {
  let component = prepared_test_component(
    (
      #|(component
      #| (core module $M (func (export "run")))
      #| (core instance $m (instantiate $M))
      #| (func (export "run") (canon lift (core func $m "run"))))
    ),
  )
  let code = prepare_native_component_code([component], opt_level=0)
  let budget = @runtime.ResourceBudget::new(code_bytes=0L)
  let denied = @runtime_impl.ComponentLinker::with_core_execution_engine(
    code.open_session(),
    resource_budget=Some(budget),
  )
  defer denied.close()
  let before = denied.get_store().counts()
  for _ in 0..<2 {
    try denied.instantiate("denied", component) catch {
      ResourceLimitExceeded(CodeBytes) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("prepared code bypassed installation quota")
    }
    debug_inspect(
      denied.get_store().counts(),
      content=before.to_repr().to_string(),
    )
    assert_eq(budget.used(CodeBytes), 0L)
    assert_eq(budget.used(Instances), 0L)
  }
  denied.close()
  let healthy = @runtime_impl.ComponentLinker::with_core_execution_engine(
    code.open_session(),
  )
  defer healthy.close()
  let instance = healthy.instantiate("healthy", component)
  assert_true(instance.call_exported_func("run", []).is_empty())
}

///|
test "prepared code covers nested definitions with bounded immutable storage" {
  let component = prepared_test_component(
    (
      #|(component
      #| (component $Child
      #|  (core module $M (func (export "run") (result i32) i32.const 42))
      #|  (core instance $m (instantiate $M))
      #|  (func (export "run") (result u32) (canon lift (core func $m "run"))))
      #| (instance $a (instantiate $Child))
      #| (instance $b (instantiate $Child))
      #| (alias export $b "run" (func $run))
      #| (export "run" (func $run)))
    ),
  )
  let code = prepare_native_component_code([component, component], opt_level=0)
  assert_eq(code.artifacts.length(), 1)
  let compilations = Ref(0)
  let (engine, _) = native_component_session_with_contexts(
    0,
    fn(_) { () },
    prepared_code=Some(code),
    on_compile=fn() { compilations.val += 1 },
  )
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(engine)
  defer linker.close()
  let instance = linker.instantiate("root", component)
  assert_true(instance.call_exported_func("run", []) is [U32(42)])
  assert_eq(compilations.val, 0)
  assert_eq(code.artifacts.length(), 1)
}

///|
test "prepared code cannot override the session compilation policy" {
  let component = prepared_test_component(
    (
      #|(component
      #| (core module $M (func (export "run") (result i32) i32.const 42))
      #| (core instance $m (instantiate $M))
      #| (func (export "run") (result u32) (canon lift (core func $m "run"))))
    ),
  )
  let code = prepare_native_component_code([component], opt_level=0)
  let compilations = Ref(0)
  let (engine, _) = native_component_session_with_contexts(
    1,
    fn(_) { () },
    prepared_code=Some(code),
    on_compile=fn() { compilations.val += 1 },
  )
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(engine)
  defer linker.close()
  let instance = linker.instantiate("root", component)
  assert_true(instance.call_exported_func("run", []) is [U32(42)])
  assert_eq(compilations.val, 1)
  assert_eq(code.artifacts.length(), 1)
}
