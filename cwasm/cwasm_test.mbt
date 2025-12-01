// Black-box tests for cwasm module

///|
test "TargetArch from helper functions" {
  let arch64 = @cwasm.aarch64_target()
  let x86 = @cwasm.x86_64_target()
  inspect(arch64, content="aarch64")
  inspect(x86, content="x86_64")
}

///|
test "PrecompiledModule::new" {
  let pcm = @cwasm.PrecompiledModule::new(@cwasm.aarch64_target())
  inspect(pcm.version, content="1")
  inspect(pcm.target, content="aarch64")
  inspect(pcm.function_count(), content="0")
}

///|
test "CompiledEntry::new" {
  let entry = @cwasm.CompiledEntry::new(0, "test_func", [1, 2, 3], 16, 0)
  inspect(entry.func_idx, content="0")
  inspect(entry.name, content="test_func")
  inspect(entry.code.length(), content="3")
  inspect(entry.frame_size, content="16")
  inspect(entry.entry_offset, content="0")
}

///|
test "PrecompiledModule serialize and deserialize roundtrip" {
  let pcm = @cwasm.PrecompiledModule::new(@cwasm.aarch64_target())
  // Create a CompiledFunction mock via CompiledEntry
  let entry = @cwasm.CompiledEntry::new(0, "add", [0xD503201F], 32, 0)
  let cf = entry.to_compiled_function()
  pcm.add_function(0, "add", cf)
  inspect(pcm.function_count(), content="1")
  // Serialize
  let serialized = pcm.serialize()
  inspect(serialized.length() > 0, content="true")
  // Deserialize
  let pcm2 = @cwasm.deserialize(serialized)
  inspect(pcm2.version, content="1")
  inspect(pcm2.target, content="aarch64")
  inspect(pcm2.function_count(), content="1")
}

///|
test "deserialize invalid data raises error" {
  let invalid_data = [0, 0, 0, 0] // Invalid magic
  let result : Result[@cwasm.PrecompiledModule, _] = Ok(
    @cwasm.deserialize(invalid_data),
  ) catch {
    e => Err(e)
  }
  inspect(result is Err(_), content="true")
}

///|
test "PrecompiledModule with multiple functions" {
  let pcm = @cwasm.PrecompiledModule::new(@cwasm.aarch64_target())
  let entry1 = @cwasm.CompiledEntry::new(0, "func0", [1, 2], 16, 0)
  let entry2 = @cwasm.CompiledEntry::new(1, "func1", [3, 4, 5], 32, 0)
  pcm.add_function(0, "func0", entry1.to_compiled_function())
  pcm.add_function(1, "func1", entry2.to_compiled_function())
  inspect(pcm.function_count(), content="2")
  inspect(pcm.functions[0].name, content="func0")
  inspect(pcm.functions[1].name, content="func1")
}
