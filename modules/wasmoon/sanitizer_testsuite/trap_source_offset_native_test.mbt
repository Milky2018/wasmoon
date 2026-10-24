///|
test "decoded AST trap report never fabricates a Wasm byte offset" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let module_ = @wat.parse("(module (func (export \"run\") unreachable))")
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  try context.call_core_func(store, instance, 0, []) catch {
    Trap(_) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("unreachable returned")
  }
  let report = context.jit_module.get_last_trap_report().unwrap()
  assert_eq(report.wasm_func_idx, Some(0))
  assert_eq(report.wasm_offset, None)
}

///|
fn offset_fixture_nested() -> Bytes {
  // Custom padding and a non-canonical local-vector LEB distinguish original
  // module offsets from re-encoded positions and native function displacements.
  // The caller returns i32 after a void call, so the call cannot become a tail call.
  b"\x00asm\x01\x00\x00\x00\x00\x06\x01x\x00\x00\x00\x00\x01\x08\x02\x60\x00\x00\x60\x00\x01\x7f\x03\x03\x02\x00\x01\x07\x07\x01\x03run\x00\x01\x0a\x0d\x02\x04\x80\x00\x00\x0b\x06\x00\x10\x00\x41\x07\x0b"
}

///|
test "binary trap and caller report original offsets after artifact serialization" {
  let binary = offset_fixture_nested()
  assert_eq(binary[46], b'\x00')
  assert_eq(binary[50], b'\x10')
  for level in [0, 2] {
    let artifact = @commands.compile_module(binary, opt_level=level).unwrap()
    let decoded = @artifact.decode(@artifact.encode(artifact))
    assert_eq(decoded, artifact)
    let module_ = @jit.JITModule::load_artifact(
      @commands.verify_compiled_jit_artifact(decoded),
      [([], []), ([], [I32])],
      function_names=["leaf", "run"],
    )
    defer module_.close()
    try module_.call_with_context(module_.get_func(1).unwrap(), []) catch {
      JITTrap(_) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("unreachable returned")
    }
    let report = module_.get_last_trap_report().unwrap()
    assert_eq(report.wasm_func_idx, Some(0))
    assert_eq(
      report.wasm_offset,
      Some(46L),
      msg="level=\{level}, native=\{Repr(report.native_offset)}, sources=\{Repr(artifact.functions.map(f => (f.sources, f.traps)))}",
    )
    assert_true(report.native_offset != report.wasm_offset)
    assert_eq(
      report.wasm_frames.map(frame => frame.wasm_offset),
      [Some(46L), Some(50L)],
      msg="level=\{level}, native frames=\{Repr(report.wasm_frames.map(frame => (frame.func_idx, frame.pc, frame.wasm_offset, frame.native_offset)))}",
    )
    assert_eq(report.wasm_frames.map(frame => frame.func_idx), [0, 1])
  }
}

///|
test "resumed optimized trap preserves original binary position" {
  // One (param i32) function loops to force native suspension, then traps.
  let binary = b"\x00asm\x01\x00\x00\x00\x00\x06\x01x\x00\x00\x00\x00\x01\x05\x01\x60\x01\x7f\x00\x03\x02\x01\x00\x07\x07\x01\x03run\x00\x00\x0a\x11\x01\x0f\x00\x03\x40\x20\x00\x41\x01\x6b\x22\x00\x0d\x00\x0b\x00\x0b"
  assert_eq(binary[53], b'\x00')
  for level in [0, 2] {
    let artifact = @commands.compile_module(
      binary,
      opt_level=level,
      enable_cancellation=true,
    ).unwrap()
    let module_ = @jit.JITModule::load_artifact(
      @commands.verify_compiled_jit_artifact(
        @artifact.decode(@artifact.encode(artifact)),
      ),
      [([I32], [])],
    )
    defer module_.close()
    assert_true(module_.set_cooperative_scheduling(true))
    let yields = Ref(0)
    try {
      let mut outcome = module_.start_continuation_call(
        module_.get_func(0).unwrap(),
        [10000L],
      )
      while outcome is JITSuspended(CooperativeYield, continuation) {
        errdefer continuation.cancel()
        yields.val += 1
        outcome = continuation.continue_execution()
      }
      fail("unreachable returned")
    } catch {
      @jit.JITTrap::JITTrap(_) => ()
      error => fail(error.to_string())
    }
    assert_true(yields.val > 1)
    let report = module_.get_last_trap_report().unwrap()
    assert_eq(
      report.wasm_offset,
      Some(53L),
      msg="level=\{level}, native=\{Repr(report.native_offset)}, sources=\{Repr(artifact.functions.map(f => (f.sources, f.traps)))}",
    )
    assert_true(report.native_offset != report.wasm_offset)
  }
}

///|
test "integer trap keeps its source through checked lowering and constant folding" {
  let binary = b"\x00asm\x01\x00\x00\x00\x01\x05\x01\x60\x00\x01\x7f\x03\x02\x01\x00\x07\x07\x01\x03run\x00\x00\x0a\x09\x01\x07\x00\x41\x2a\x41\x00\x6d\x0b"
  assert_eq(binary[37], b'\x6d')
  for level in [0, 2] {
    let artifact = @commands.compile_module(binary, opt_level=level).unwrap()
    let module_ = @jit.JITModule::load_artifact(
      @commands.verify_compiled_jit_artifact(artifact),
      [([], [I32])],
    )
    defer module_.close()
    try module_.call_with_context(module_.get_func(0).unwrap(), []) catch {
      JITTrap(_) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("division by zero returned")
    }
    let report = module_.get_last_trap_report().unwrap()
    assert_eq(report.wasm_offset, Some(37L), msg="level=\{level}")
  }
}

///|
test "unreachable nested bodies do not shift the next branch source position" {
  let binary = b"\x00asm\x01\x00\x00\x00\x01\x05\x01\x60\x01\x7f\x00\x03\x02\x01\x00\x07\x07\x01\x03run\x00\x00\x0a\x11\x01\x0f\x00\x20\x00\x04\x40\x00\x1f\x40\x00\x01\x0b\x05\x00\x0b\x0b"
  assert_eq(binary[37], b'\x00')
  assert_eq(binary[44], b'\x00')
  for level in [0, 2] {
    let artifact = @commands.compile_module(binary, opt_level=level).unwrap()
    let module_ = @jit.JITModule::load_artifact(
      @commands.verify_compiled_jit_artifact(artifact),
      [([I32], [])],
    )
    defer module_.close()
    for (argument, expected) in [(0L, 44L), (1L, 37L)] {
      try
        module_.call_with_context(module_.get_func(0).unwrap(), [argument])
      catch {
        JITTrap(_) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("branch trap returned")
      }
      assert_eq(
        module_.get_last_trap_report().unwrap().wasm_offset,
        Some(expected),
        msg="level=\{level}, argument=\{argument}",
      )
    }
  }
}

///|
test "native stack guard remains explicitly unmapped rather than borrowing a call offset" {
  let binary = b"\x00asm\x01\x00\x00\x00\x00\x06\x01x\x00\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x07\x07\x01\x03run\x00\x00\x0a\x06\x01\x04\x00\x10\x00\x0b"
  let artifact = @commands.compile_module(binary, opt_level=0).unwrap()
  let module_ = @jit.JITModule::load_artifact(
    @commands.verify_compiled_jit_artifact(artifact),
    [([], [])],
  )
  defer module_.close()
  assert_true(module_.configure_native_fiber_stack_size(65536L))
  try module_.call_with_context(module_.get_func(0).unwrap(), []) catch {
    JITTrap(message) =>
      assert_true(message.has_prefix("call stack exhausted"), msg=message)
    error => fail(error.to_string())
  } noraise {
    _ => fail("unbounded recursion returned")
  }
  let report = module_.get_last_trap_report().unwrap()
  assert_eq(report.wasm_offset, None)
  assert_true(report.wasm_frames.length() > 1)
  for frame in report.wasm_frames[1:] {
    assert_eq(frame.wasm_offset, Some(40L))
  }
}

///|
test "explicit return source covers RET without claiming the synthetic epilogue" {
  let binary = b"\x00asm\x01\x00\x00\x00\x01\x05\x01\x60\x00\x01\x7f\x03\x02\x01\x00\x07\x07\x01\x03run\x00\x00\x0a\x07\x01\x05\x00\x41\x2a\x0f\x0b"
  assert_eq(binary[35], b'\x0f')
  for level in [0, 2] {
    let artifact = @commands.compile_module(binary, opt_level=level).unwrap()
    let sites = artifact.functions[0].sources.filter(site => {
      site.source.byte_offset == Some(35L)
    })
    assert_eq(sites.length(), 1)
    let expected_length = match artifact.manifest.target.architecture {
      AArch64 => 4
      X64 => 1
    }
    assert_eq(sites[0].length, expected_length)
    assert_eq(
      sites[0].offset + sites[0].length,
      artifact.functions[0].code.length(),
    )
    let module_ = @jit.JITModule::load_artifact(
      @commands.verify_compiled_jit_artifact(artifact),
      [([], [I32])],
    )
    defer module_.close()
    assert_eq(module_.call_with_context(module_.get_func(0).unwrap(), []), [42L])
  }
}
