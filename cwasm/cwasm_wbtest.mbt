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
  inspect(mod.version, content="3")
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
  inspect(restored.version, content="3")
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
  // Valid magic but wrong version (v1 is now unsupported)
  let bytes : Array[Int] = [
    0x63, 0x77, 0x61, 0x73, // magic
     0x01, 0x00, 0x00, 0x00,
  ] // version 1
  inspect(try? deserialize(bytes), content="Err(Unsupported version: 1)")
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
