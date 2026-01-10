// Black-box tests for cwasm module

///|
test "PrecompiledModule serialize and deserialize roundtrip" {
  let pcm = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  // Create a CompiledFunction mock via CompiledEntry
  let entry = @cwasm.CompiledEntry::new(0, "add", [0xD503201F], 32, 0, 2, 1)
  let cf = entry.to_compiled_function()
  pcm.add_function(0, "add", cf, 2, 1)
  inspect(pcm.function_count(), content="1")
  // Serialize
  let serialized = pcm.serialize()
  inspect(serialized.length() > 0, content="true")
  // Deserialize
  let pcm2 = @cwasm.deserialize(serialized)
  inspect(pcm2.version, content="5")
  inspect(pcm2.target, content="aarch64")
  inspect(pcm2.function_count(), content="1")
  inspect(pcm2.functions[0].num_params, content="2")
  inspect(pcm2.functions[0].num_results, content="1")
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
test "PrecompiledModule serialize roundtrip with multiple functions" {
  let pcm = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let entry1 = @cwasm.CompiledEntry::new(0, "func0", [1, 2, 3, 4], 16, 0, 0, 0)
  let entry2 = @cwasm.CompiledEntry::new(
    1,
    "func1",
    [5, 6, 7, 8, 9],
    32,
    4,
    1,
    1,
  )
  pcm.add_function(0, "func0", entry1.to_compiled_function(), 0, 0)
  pcm.add_function(1, "func1", entry2.to_compiled_function(), 1, 1)
  // Serialize and deserialize
  let serialized = pcm.serialize()
  let pcm2 = @cwasm.deserialize(serialized)
  // Verify all data preserved
  inspect(pcm2.function_count(), content="2")
  inspect(pcm2.functions[0].name, content="func0")
  inspect(pcm2.functions[0].frame_size, content="16")
  inspect(pcm2.functions[0].num_params, content="0")
  inspect(pcm2.functions[1].name, content="func1")
  inspect(pcm2.functions[1].frame_size, content="32")
  inspect(pcm2.functions[1].num_params, content="1")
}
