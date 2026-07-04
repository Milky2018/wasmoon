///|
fn minimal_i32_const_module_bytes() -> Bytes {
  Bytes::from_array([
    // Magic + version
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    // Type section: (func) -> i32
     0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
    // Function section: one local function of type 0
     0x03, 0x02, 0x01, 0x00,
    // Export section: (export "run" (func 0))
     0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,
    // Code section: i32.const 42; end
     0x0a, 0x06, 0x01, 0x04, 0x00, 0x41, 0x2a, 0x0b,
  ])
}

///|
fn direct_call_module_bytes() -> Bytes {
  Bytes::from_array([
    // Magic + version
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    // Type section: (func) -> i32
     0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
    // Function section: two local functions of type 0
     0x03, 0x03, 0x02, 0x00, 0x00,
    // Export section: (export "run" (func 1))
     0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x01,
    // Code section:
    //   func0: i32.const 42
    //   func1: call 0
     0x0a, 0x0b, 0x02, 0x04, 0x00, 0x41, 0x2a, 0x0b, 0x04, 0x00, 0x10, 0x00, 0x0b,
  ])
}

///|
test "compile api: emits stage progress and returns artifact" {
  let events : Array[CompileProgress] = []
  let compiled = compile_module(minimal_i32_const_module_bytes(), on_progress=fn(
    event,
  ) {
    events.push(event)
    None
  })
  inspect(compiled is Some(_), content="true")
  inspect(events.length() > 0, content="true")
  inspect(events[0].stage.to_string(), content="parse")
  let last = events[events.length() - 1]
  inspect(last.stage.to_string(), content="done")
  inspect(last.compiled_funcs, content="1")
  guard compiled is Some(precompiled) else { return }
  inspect(precompiled.functions.length(), content="1")
  inspect(precompiled.functions[0].name, content="wasm_func_0")
  inspect(precompiled.functions[0].code.length() > 0, content="true")
  inspect(precompiled.functions[0].num_results, content="1")
}

///|
test "compile api: reusable pipeline preserves direct wasm call fixups" {
  let compiled = compile_module(direct_call_module_bytes())
  guard compiled is Some(precompiled) else { fail("compile failed") }
  inspect(precompiled.functions.length(), content="2")
  let mut call_fixup_count = -1
  let mut target_func_idx = -1
  for entry in precompiled.functions {
    if entry.func_idx == 1 {
      call_fixup_count = entry.call_fixups.length()
      if entry.call_fixups.length() > 0 {
        target_func_idx = entry.call_fixups[0].func_idx
      }
    }
  }
  inspect(call_fixup_count, content="1")
  inspect(target_func_idx, content="0")
}

///|
test "compile api: reusable pipeline lowers ref.func without legacy custom" {
  let mod_ = @types.Module::simple([], [FuncRef], [RefFunc(0)], "make_ref")
  let isa = @isa.ISA::current()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    isa,
    current_emit_target(isa),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("ref.func did not compile through reusable pipeline")
  }
  inspect(reusable.entry.func_idx, content="0")
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.GetFuncRef"), content="false")
  inspect(reusable.milk_dump.contains("load_ptr.ref"), content="true")
}

///|
test "compile api: reusable pipeline lowers memory0 base without legacy custom" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [
        I32Const(0),
        I32Const(42),
        I32Store(0, 2, 0),
        I32Const(0),
        I32Load(0, 2, 0),
      ],
      "memory_roundtrip",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let isa = @isa.ISA::current()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    isa,
    current_emit_target(isa),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("memory0 load/store did not compile through reusable pipeline")
  }
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.LoadMemBase"), content="false")
  inspect(reusable.milk_dump.contains("load_ptr.i64"), content="true")
  inspect(reusable.milk_dump.contains("store_ptr.i32"), content="true")
}

///|
test "compile api: reusable pipeline lowers memory.size without legacy custom" {
  let mod_ = {
    ..@types.Module::simple([], [I32], [MemorySize(0)], "memory_size"),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let isa = @isa.ISA::current()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    isa,
    current_emit_target(isa),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("memory.size did not compile through reusable pipeline")
  }
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.MemorySize"), content="false")
  inspect(reusable.milk_dump.contains("ushr"), content="true")
  inspect(reusable.milk_dump.contains("ireduce"), content="true")
}

///|
test "compile api: reusable pipeline lowers memory.size for non-zero memory" {
  let mod_ = {
    ..@types.Module::simple([], [I32], [MemorySize(1)], "memory1_size"),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
      { limits: { min: 2, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let isa = @isa.ISA::current()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    isa,
    current_emit_target(isa),
    2,
  )
  guard compiled is Some(reusable) else {
    fail(
      "memory.size for non-zero memory did not compile through reusable pipeline",
    )
  }
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.MemorySize"), content="false")
  inspect(reusable.milk_dump.contains("ushr"), content="true")
}

///|
test "compile api: reusable pipeline lowers non-zero memory load store" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [
        I32Const(0),
        I32Const(7),
        I32Store(1, 2, 0),
        I32Const(0),
        I32Load(1, 2, 0),
      ],
      "memory1_roundtrip",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let isa = @isa.ISA::current()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    isa,
    current_emit_target(isa),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("non-zero memory load/store did not compile through reusable pipeline")
  }
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.LoadMemBase"), content="false")
  inspect(
    reusable.milk_dump.contains("trap \"memory out of bounds\""),
    content="true",
  )
}

///|
test "compile api: reusable pipeline lowers memory64 load" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [I64Const(0L), I32Load(0, 2, 0)],
      "memory64_load",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: true, page_size_log2: 16 },
    ],
  }
  let isa = @isa.ISA::current()
  let env = @wasm_frontend.EmbeddingEnvironment::new()
  let milk = @wasm_frontend.try_lower_native_function(env, mod_, 0) catch {
    e => fail(e.to_string())
  }
  guard milk is Some(milk_func) else {
    fail("memory64 load did not lower natively")
  }
  @milkir.optimize_with_level(milk_func, @milkir.OptLevel::from_int(2))
  |> ignore
  let plan = @wasmoon_jit.plan_wasm_body_milkir_integration_for_target(
    milk_func,
    current_emit_target(isa),
  ) catch {
    e => fail(e.to_string())
  }
  let artifact = @wasmoon_jit.CwasmArtifact::from_jit_plan_with_signature(
    plan,
    @wasmoon_jit.RuntimeSymbolResolver::new(),
    0,
    mod_.get_func_type(0).params.length(),
    mod_.get_func_type(0).results.length(),
  ) catch {
    e => fail(e.to_string())
  }
  let compiled = artifact.to_precompiled_module()
  inspect(compiled.functions.length(), content="1")
  inspect(compiled.functions[0].code.length() > 0, content="true")
  inspect(milk_func.print().contains("wasmoon.LoadMemBase"), content="false")
  inspect(
    milk_func.print().contains("trap \"memory out of bounds\""),
    content="true",
  )
}

///|
test "compile api: parse failure emits failed stage" {
  let events : Array[CompileProgress] = []
  let compiled = compile_module(Bytes::from_array([0x00, 0x01, 0x02]), on_progress=fn(
    event,
  ) {
    events.push(event)
    None
  })
  inspect(compiled is Some(_), content="false")
  inspect(events.length() >= 2, content="true")
  let last = events[events.length() - 1]
  inspect(last.stage.to_string(), content="failed")
}

///|
test "jit cache bytes/ints conversion keeps unsigned bytes" {
  let source = Bytes::from_array([0x00, 0x01, 0x7f, 0x80, 0xfe, 0xff])
  let ints = bytes_to_int_array(source)
  inspect(ints[0], content="0")
  inspect(ints[3], content="128")
  inspect(ints[4], content="254")
  inspect(ints[5], content="255")
  inspect(int_array_to_bytes(ints) == source, content="true")
}
