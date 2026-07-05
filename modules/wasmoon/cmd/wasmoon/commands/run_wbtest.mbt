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
test "compile api: reusable pipeline lowers direct wasm calls through func table" {
  let compiled = compile_module(direct_call_module_bytes())
  guard compiled is Some(precompiled) else { fail("compile failed") }
  inspect(precompiled.functions.length(), content="2")
  let mut call_fixup_count = -1
  for entry in precompiled.functions {
    if entry.func_idx == 1 {
      call_fixup_count = entry.call_fixups.length()
    }
  }
  inspect(call_fixup_count, content="0")
}

///|
test "compile api: reusable pipeline lowers ref.func without legacy custom" {
  let mod_ = @types.Module::simple([], [FuncRef], [RefFunc(0)], "make_ref")
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
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
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
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
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
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
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
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
test "compile api: reusable pipeline lowers memory.grow runtime call" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [I32Const(1), MemoryGrow(0)],
      "memory_grow",
    ),
    memories: [
      {
        limits: { min: 1, max: Some(2L) },
        is_memory64: false,
        page_size_log2: 16,
      },
    ],
  }
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("memory.grow did not compile through reusable pipeline")
  }
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.MemoryGrow"), content="false")
  inspect(
    reusable.milk_dump.contains("call wasmoon.runtime.memory_grow"),
    content="true",
  )
  inspect(reusable.entry.call_fixups.length(), content="1")
  inspect(reusable.entry.call_fixups[0].func_idx, content="-21000")
}

///|
test "compile api: reusable pipeline lowers memory fill and copy runtime calls" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [],
      [
        I32Const(0),
        I32Const(255),
        I32Const(8),
        MemoryFill(0),
        I32Const(0),
        I32Const(4),
        I32Const(8),
        MemoryCopy(0, 0),
      ],
      "memory_fill_copy",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("memory fill/copy did not compile through reusable pipeline")
  }
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.MemoryFill"), content="false")
  inspect(reusable.milk_dump.contains("wasmoon.MemoryCopy"), content="false")
  inspect(
    reusable.milk_dump.contains("call wasmoon.runtime.memory_fill"),
    content="true",
  )
  inspect(
    reusable.milk_dump.contains("call wasmoon.runtime.memory_copy"),
    content="true",
  )
  inspect(reusable.entry.call_fixups.length(), content="2")
  inspect(reusable.entry.call_fixups[0].func_idx, content="-21002")
  inspect(reusable.entry.call_fixups[1].func_idx, content="-21004")
}

///|
test "compile api: reusable pipeline lowers memory segment runtime calls" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [],
      [I32Const(0), I32Const(0), I32Const(0), MemoryInit(0, 0), DataDrop(0)],
      "memory_segment_ops",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("memory segment ops did not compile through reusable pipeline")
  }
  inspect(reusable.milk_dump.contains("wasmoon.MemoryInit"), content="false")
  inspect(reusable.milk_dump.contains("wasmoon.DataDrop"), content="false")
  inspect(
    reusable.milk_dump.contains("call wasmoon.runtime.memory_init"),
    content="true",
  )
  inspect(
    reusable.milk_dump.contains("call wasmoon.runtime.data_drop"),
    content="true",
  )
  inspect(reusable.entry.call_fixups.length(), content="2")
  inspect(reusable.entry.call_fixups[0].func_idx, content="-21006")
  inspect(reusable.entry.call_fixups[1].func_idx, content="-21007")
}

///|
test "compile api: reusable pipeline lowers table runtime calls" {
  let table : @types.Table = {
    type_: {
      elem_type: FuncRef,
      limits: { min: 2, max: None },
      is_table64: false,
    },
    init: None,
  }
  let mod_ = {
    ..@types.Module::simple(
      [I64],
      [],
      [
        LocalGet(0),
        I32Const(1),
        TableGrow(0),
        Drop,
        I32Const(0),
        LocalGet(0),
        I32Const(1),
        TableFill(0),
        I32Const(0),
        I32Const(1),
        I32Const(1),
        TableCopy(0, 0),
        I32Const(0),
        I32Const(0),
        I32Const(1),
        TableInit(0, 0),
        ElemDrop(0),
      ],
      "table_runtime_ops",
    ),
    tables: [table],
  }
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("table ops did not compile through reusable pipeline")
  }
  inspect(reusable.milk_dump.contains("wasmoon.TableGrow"), content="false")
  inspect(reusable.milk_dump.contains("wasmoon.TableFill"), content="false")
  inspect(reusable.milk_dump.contains("wasmoon.TableCopy"), content="false")
  inspect(reusable.milk_dump.contains("wasmoon.TableInit"), content="false")
  inspect(reusable.milk_dump.contains("wasmoon.ElemDrop"), content="false")
  inspect(reusable.entry.call_fixups.length(), content="5")
  inspect(reusable.entry.call_fixups[0].func_idx, content="-21008")
  inspect(reusable.entry.call_fixups[1].func_idx, content="-21009")
  inspect(reusable.entry.call_fixups[2].func_idx, content="-21010")
  inspect(reusable.entry.call_fixups[3].func_idx, content="-21011")
  inspect(reusable.entry.call_fixups[4].func_idx, content="-21012")
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
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
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
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("memory64 load did not compile through reusable pipeline")
  }
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.LoadMemBase"), content="false")
  inspect(
    reusable.milk_dump.contains("trap \"memory out of bounds\""),
    content="true",
  )
}

///|
test "compile api: reusable pipeline lowers memory64 narrow load store" {
  let mod_ = {
    ..@types.Module::simple(
      [],
      [I32],
      [
        I64Const(0L),
        I32Const(7),
        I32Store8(0, 0, 0),
        I64Const(0L),
        I32Load8U(0, 0, 0),
      ],
      "memory64_narrow_roundtrip",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: true, page_size_log2: 16 },
    ],
  }
  let target_arch = @wasmoon_jit.host_target_arch()
  let compiled = try_compile_with_reusable_pipeline(
    mod_,
    0,
    0,
    mod_.get_func_type(0),
    target_arch,
    current_emit_target(target_arch),
    2,
  )
  guard compiled is Some(reusable) else {
    fail("memory64 narrow load/store did not compile through reusable pipeline")
  }
  inspect(reusable.entry.code.length() > 0, content="true")
  inspect(reusable.milk_dump.contains("wasmoon.LoadMemBase"), content="false")
  inspect(reusable.milk_dump.contains("load_ptr8u.i32"), content="true")
  inspect(reusable.milk_dump.contains("store_ptr8"), content="true")
  inspect(
    reusable.milk_dump.contains("trap \"memory out of bounds\""),
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
