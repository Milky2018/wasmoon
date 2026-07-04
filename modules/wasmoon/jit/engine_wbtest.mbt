// Tests for JIT engine

///|
test "function entry: creation" {
  let entry = FunctionEntry::new(42)
  inspect(entry.func_idx, content="42")
  inspect(entry.is_compiled(), content="false")
  inspect(entry.call_count, content="0")
}

///|
test "compilation status: show" {
  inspect(CompilationStatus::NotCompiled.to_string(), content="not_compiled")
  inspect(CompilationStatus::Compiled.to_string(), content="compiled")
  inspect(
    CompilationStatus::Failed("test error").to_string(),
    content="failed: test error",
  )
}

///|
test "jit engine: creation" {
  let engine = JITEngine::default()
  let (total, jit, interp, compiled, failures) = engine.stats()
  inspect(total, content="0")
  inspect(jit, content="0")
  inspect(interp, content="0")
  inspect(compiled, content="0")
  inspect(failures, content="0")
}

///|
test "jit engine: on_call counts" {
  let engine = JITEngine::default()

  // First calls should use interpreter
  for _ in 0..<10 {
    let use_jit = engine.on_call(0)
    inspect(use_jit, content="false")
  }
  let (total, jit, interp, _, _) = engine.stats()
  inspect(total, content="10")
  inspect(jit, content="0")
  inspect(interp, content="10")
}

///|
test "jit engine: mark compiled" {
  let engine = JITEngine::default()

  // Call a few times first
  for _ in 0..<5 {
    engine.on_call(0) |> ignore
  }

  // Mark as compiled
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  mc.emit_ret(30)
  let code = @vcode.CompiledFunction::new("test", mc, 16)
  engine.mark_compiled(0, code)

  // Check it's compiled
  inspect(engine.is_compiled(0), content="true")
  if engine.get_compiled(0) is None {
    panic()
  }
}

///|
test "jit engine: compiled calls use jit" {
  let engine = JITEngine::default()

  // Mark as compiled first
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  let code = @vcode.CompiledFunction::new("test", mc, 0)
  engine.mark_compiled(0, code)

  // Now on_call should return true
  let use_jit = engine.on_call(0)
  inspect(use_jit, content="true")
  let (_, jit, _, _, _) = engine.stats()
  inspect(jit, content="1")
}

///|
test "jit engine: mark failed" {
  let engine = JITEngine::default()
  engine.mark_failed(0, "compilation error")
  let (_, _, _, _, failures) = engine.stats()
  inspect(failures, content="1")
  inspect(engine.is_compiled(0), content="false")
}

///|
test "jit engine: invalidate" {
  let engine = JITEngine::default()

  // Compile first
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  let code = @vcode.CompiledFunction::new("test", mc, 0)
  engine.mark_compiled(0, code)
  inspect(engine.is_compiled(0), content="true")

  // Invalidate
  engine.invalidate(0)
  // Note: strategy still shows compiled, but runtime is invalidated
  // The function entry status is updated
  if engine.functions.get(0) is Some(entry) {
    if entry.status is NotCompiled {
      ()
    } else {
      panic()
    }
  }
}

///|
test "jit engine: multiple functions" {
  let engine = JITEngine::default()

  // Call different functions
  for _ in 0..<5 {
    engine.on_call(0) |> ignore
  }
  for _ in 0..<3 {
    engine.on_call(1) |> ignore
  }
  for _ in 0..<7 {
    engine.on_call(2) |> ignore
  }
  let (total, _, interp, _, _) = engine.stats()
  inspect(total, content="15")
  inspect(interp, content="15")
}

///|
test "jit engine: show" {
  let engine = JITEngine::default()
  engine.on_call(0) |> ignore
  let s = engine.to_string()
  inspect(s.length() > 0, content="true")
}
