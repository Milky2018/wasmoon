// Tests for .cwasm format

///|
test "target arch: to_byte and from_byte" {
  inspect(TargetArch::Unknown.to_byte(), content="0")
  inspect(TargetArch::X86_64.to_byte(), content="1")
  inspect(TargetArch::AArch64.to_byte(), content="2")
  inspect(TargetArch::from_byte(0).to_string(), content="unknown")
  inspect(TargetArch::from_byte(1).to_string(), content="x86_64")
  inspect(TargetArch::from_byte(2).to_string(), content="aarch64")
  inspect(TargetArch::from_byte(99).to_string(), content="unknown")
}

///|
test "compiled entry: creation" {
  let code : Array[Int] = [0x90, 0xC3] // NOP, RET
  let entry = CompiledEntry::new(0, "test_func", code, 16, 0, 2, 1)
  inspect(entry.func_idx, content="0")
  inspect(entry.name, content="test_func")
  inspect(entry.code.length(), content="2")
  inspect(entry.frame_size, content="16")
  inspect(entry.num_params, content="2")
  inspect(entry.num_results, content="1")
}

///|
test "precompiled module: creation" {
  let mod = PrecompiledModule::new(AArch64)
  inspect(mod.version, content="5")
  inspect(mod.target.to_string(), content="aarch64")
  inspect(mod.function_count(), content="0")
}

///|
test "precompiled module: add function" {
  let mod = PrecompiledModule::new(AArch64)

  // Create a simple compiled function
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  mc.emit_ret(30)
  let func = @vcode.CompiledFunction::new("add", mc, 16)
  mod.add_function(0, "add", func, 2, 1)
  inspect(mod.function_count(), content="1")
  inspect(mod.functions[0].num_params, content="2")
  inspect(mod.functions[0].num_results, content="1")
}

///|
test "serialize and deserialize: roundtrip" {
  let mod = PrecompiledModule::new(AArch64)

  // Add a function
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  let func = @vcode.CompiledFunction::new("test", mc, 32)
  mod.add_function(42, "test", func, 3, 1)

  // Serialize
  let bytes = mod.serialize()
  inspect(bytes.length() > 0, content="true")

  // Deserialize
  let restored = deserialize(bytes) catch { _ => panic() }
  inspect(restored.version, content="5")
  inspect(restored.target.to_string(), content="aarch64")
  inspect(restored.function_count(), content="1")
  inspect(restored.functions[0].func_idx, content="42")
  inspect(restored.functions[0].name, content="test")
  inspect(restored.functions[0].frame_size, content="32")
  inspect(restored.functions[0].num_params, content="3")
  inspect(restored.functions[0].num_results, content="1")
}

///|
test "serialize and deserialize: multiple functions" {
  let mod = PrecompiledModule::new(AArch64)

  // Add multiple functions
  for i in 0..<3 {
    let mc = @emit.MachineCode::new()
    mc.emit_nop()
    let func = @vcode.CompiledFunction::new("func_\{i}", mc, i * 16)
    mod.add_function(i, "func_\{i}", func, i, if i > 0 { 1 } else { 0 })
  }

  // Serialize and deserialize
  let bytes = mod.serialize()
  let restored = deserialize(bytes) catch { _ => panic() }
  inspect(restored.function_count(), content="3")
  for i in 0..<3 {
    inspect(restored.functions[i].func_idx, content=i.to_string())
    inspect(restored.functions[i].name, content="func_\{i}")
    inspect(restored.functions[i].num_params, content=i.to_string())
  }
}

///|
test "deserialize: invalid magic" {
  let bytes : Array[Int] = [0x00, 0x00, 0x00, 0x00]
  inspect(try? deserialize(bytes), content="Err(Invalid magic number)")
}

///|
test "deserialize: unsupported version" {
  // Valid magic but wrong version (only v4 is supported)
  let v1_bytes : Array[Int] = [
    0x63, 0x77, 0x61, 0x73, // magic
     0x01, 0x00, 0x00, 0x00,
  ] // version 1
  inspect(try? deserialize(v1_bytes), content="Err(Unsupported version: 1)")
  let v3_bytes : Array[Int] = [
    0x63, 0x77, 0x61, 0x73, // magic
     0x03, 0x00, 0x00, 0x00,
  ] // version 3
  inspect(try? deserialize(v3_bytes), content="Err(Unsupported version: 3)")
}

///|
test "compiled entry: to_compiled_function" {
  let code : Array[Int] = [0xD5, 0x03, 0x20, 0x1F, 0xC0, 0x03, 0x5F, 0xD6]
  let entry = CompiledEntry::new(0, "test", code, 16, 0, 2, 1)
  let func = entry.to_compiled_function()
  inspect(func.name, content="test")
  inspect(func.frame_size, content="16")
  inspect(func.get_code().length(), content="8")
}

///|
test "precompiled module: show" {
  let mod = PrecompiledModule::new(X86_64)
  let s = mod.to_string()
  inspect(s.contains("v2"), content="false")
  inspect(s.contains("x86_64"), content="true")
  inspect(s.contains("0 functions"), content="true")
}

///|
test "memory definition: creation and roundtrip" {
  let mod = PrecompiledModule::new(AArch64)

  // Add memory with no maximum
  mod.add_memory(1, None)
  inspect(mod.memories.length(), content="1")
  inspect(mod.memories[0].min_pages, content="1")
  inspect(mod.memories[0].max_pages, content="None")

  // Add memory with maximum
  mod.add_memory(2, Some(16))
  inspect(mod.memories.length(), content="2")
  inspect(mod.memories[1].min_pages, content="2")
  inspect(mod.memories[1].max_pages, content="Some(16)")

  // Serialize and deserialize
  let bytes = mod.serialize()
  let restored = deserialize(bytes) catch { _ => panic() }
  inspect(restored.memories.length(), content="2")
  inspect(restored.memories[0].min_pages, content="1")
  inspect(restored.memories[0].max_pages, content="None")
  inspect(restored.memories[1].min_pages, content="2")
  inspect(restored.memories[1].max_pages, content="Some(16)")
}

///|
test "data segment: creation and roundtrip" {
  let mod = PrecompiledModule::new(AArch64)

  // Add a data segment with "Hello"
  let hello_data : Array[Int] = [0x48, 0x65, 0x6C, 0x6C, 0x6F] // "Hello"
  mod.add_data_segment(0, 100, hello_data)
  inspect(mod.data_segments.length(), content="1")
  inspect(mod.data_segments[0].memory_idx, content="0")
  inspect(mod.data_segments[0].offset, content="100")
  inspect(mod.data_segments[0].data.length(), content="5")

  // Add another data segment
  let world_data : Array[Int] = [0x57, 0x6F, 0x72, 0x6C, 0x64] // "World"
  mod.add_data_segment(0, 200, world_data)
  inspect(mod.data_segments.length(), content="2")

  // Serialize and deserialize
  let bytes = mod.serialize()
  let restored = deserialize(bytes) catch { _ => panic() }
  inspect(restored.data_segments.length(), content="2")
  inspect(restored.data_segments[0].memory_idx, content="0")
  inspect(restored.data_segments[0].offset, content="100")
  inspect(restored.data_segments[0].data.length(), content="5")
  inspect(restored.data_segments[0].data[0], content="72") // 'H'
  inspect(restored.data_segments[0].data[4], content="111") // 'o'
  inspect(restored.data_segments[1].offset, content="200")
  inspect(restored.data_segments[1].data[0], content="87") // 'W'
}

///|
test "complete module: memory + data + function roundtrip" {
  let mod = PrecompiledModule::new(AArch64)

  // Add memory definition (1 page minimum, 4 pages maximum)
  mod.add_memory(1, Some(4))

  // Add data segment at offset 64 - simulates initialized string data
  let msg_data : Array[Int] = [
    0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, // "Hello "
     0x57, 0x6F, 0x72, 0x6C, 0x64, 0x21, // "World!"
     0x0A, // newline
  ]
  mod.add_data_segment(0, 64, msg_data)

  // Add iovec-like structure at offset 0 (pointer=64, len=13)
  let iovec_data : Array[Int] = [
    64, 0, 0, 0, // pointer to string (little-endian u32)
     13, 0, 0, 0,
  ] // length of string (little-endian u32)
  mod.add_data_segment(0, 0, iovec_data)

  // Add an import
  mod.add_import("wasi_snapshot_preview1", "fd_write", 4, 1)

  // Add a compiled function
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  mc.emit_ret(30)
  let func = @vcode.CompiledFunction::new("_start", mc, 32)
  mod.add_function(0, "_start", func, 0, 0)

  // Serialize
  let bytes = mod.serialize()
  inspect(bytes.length() > 100, content="true")

  // Deserialize and verify all components
  let restored = deserialize(bytes) catch { _ => panic() }

  // Check version
  inspect(restored.version, content="5")

  // Check memory
  inspect(restored.memories.length(), content="1")
  inspect(restored.memories[0].min_pages, content="1")
  inspect(restored.memories[0].max_pages, content="Some(4)")

  // Check data segments
  inspect(restored.data_segments.length(), content="2")
  inspect(restored.data_segments[0].offset, content="64")
  inspect(restored.data_segments[0].data.length(), content="13")
  inspect(restored.data_segments[1].offset, content="0")
  inspect(restored.data_segments[1].data.length(), content="8")

  // Check import
  inspect(restored.imports.length(), content="1")
  inspect(restored.imports[0].module_name, content="wasi_snapshot_preview1")
  inspect(restored.imports[0].func_name, content="fd_write")

  // Check function
  inspect(restored.functions.length(), content="1")
  inspect(restored.functions[0].name, content="_start")
  inspect(restored.functions[0].frame_size, content="32")
}

///|
test "data segment: empty data" {
  let mod = PrecompiledModule::new(AArch64)

  // Add empty data segment
  let empty : Array[Int] = []
  mod.add_data_segment(0, 0, empty)
  inspect(mod.data_segments[0].data.length(), content="0")

  // Roundtrip
  let bytes = mod.serialize()
  let restored = deserialize(bytes) catch { _ => panic() }
  inspect(restored.data_segments.length(), content="1")
  inspect(restored.data_segments[0].data.length(), content="0")
}

///|
test "memory definition: large pages" {
  let mod = PrecompiledModule::new(AArch64)

  // Add memory with large page counts (simulating real WASM modules)
  mod.add_memory(256, Some(65536)) // 16MB min, 4GB max
  let bytes = mod.serialize()
  let restored = deserialize(bytes) catch { _ => panic() }
  inspect(restored.memories[0].min_pages, content="256")
  inspect(restored.memories[0].max_pages, content="Some(65536)")
}
