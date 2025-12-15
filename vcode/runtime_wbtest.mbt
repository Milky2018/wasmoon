// Tests for JIT runtime support

///|
test "compiled function: basic" {
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  mc.emit_ret(30)
  let func = CompiledFunction::new("test_func", mc, 16)
  assert_true(func.is_valid())
  inspect(func.code_size, content="8")
  inspect(func.frame_size, content="16")
}

///|
test "compiled function: invalidate" {
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  let func = CompiledFunction::new("test", mc, 0)
  inspect(func.is_valid(), content="true")
  func.invalidate()
  inspect(func.is_valid(), content="false")
}

///|
test "code cache: basic operations" {
  let cache = CodeCache::new(0) // Unlimited

  // Empty cache
  inspect(cache.contains(0), content="false")
  inspect(cache.get(0) is None, content="true")

  // Insert a function
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  let func = CompiledFunction::new("func0", mc, 0)
  cache.insert(0, func)
  inspect(cache.contains(0), content="true")
  inspect(cache.get(0) is Some(_), content="true")
}

///|
test "code cache: invalidation" {
  let cache = CodeCache::new(0)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  cache.insert(0, CompiledFunction::new("func0", mc, 0))

  // Initially valid
  inspect(cache.contains(0), content="true")

  // Invalidate
  cache.invalidate(0)
  inspect(cache.contains(0), content="false")
  inspect(cache.get(0) is None, content="true")
}

///|
test "code cache: removal" {
  let cache = CodeCache::new(0)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  cache.insert(0, CompiledFunction::new("func0", mc, 0))
  cache.remove(0)
  inspect(cache.contains(0), content="false")
}

///|
test "code cache: statistics" {
  let cache = CodeCache::new(0)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  mc.emit_nop()
  cache.insert(0, CompiledFunction::new("func0", mc, 0))
  cache.get(0) |> ignore // Hit
  cache.get(1) |> ignore // Miss
  cache.get(0) |> ignore // Hit
  let (size, count, hits, misses) = cache.stats()
  inspect(count, content="1")
  inspect(size, content="8") // 2 NOPs = 8 bytes
  inspect(hits, content="2")
  inspect(misses, content="1")
}

///|
test "code cache: clear" {
  let cache = CodeCache::new(0)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  cache.insert(0, CompiledFunction::new("func0", mc, 0))
  cache.insert(1, CompiledFunction::new("func1", mc, 0))
  cache.clear()
  let (size, count, _, _) = cache.stats()
  inspect(count, content="0")
  inspect(size, content="0")
}

///|
test "executable region: write" {
  let region = ExecutableRegion::new(0, 1024)
  let bytes : Array[Int] = [0x1F, 0x20, 0x03, 0xD5] // NOP
  match region.write(bytes) {
    Ok(offset) => inspect(offset, content="0")
    Err(_) => panic()
  }
  inspect(region.remaining(), content="1020")
}

///|
test "executable region: finalize" {
  let region = ExecutableRegion::new(0, 1024)
  let bytes : Array[Int] = [0x1F, 0x20, 0x03, 0xD5]
  region.write(bytes) |> ignore
  region.finalize()

  // Cannot write after finalize
  if region.write(bytes) is Ok(_) {
    panic()
  }
}

///|
test "executable region: address" {
  let region = ExecutableRegion::new(5, 1024)
  // Base address = 5 * 0x10000 = 0x50000 = 327680
  inspect(region.address_at(100), content="327780")
}

///|
test "memory manager: alloc region" {
  let mm = MemoryManager::new(4096)
  let region = mm.alloc_region(1024)
  inspect(region.size, content="1024")
  inspect(mm.total_allocated(), content="1024")
}

///|
test "memory manager: write code" {
  let mm = MemoryManager::new(4096)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  mc.emit_nop()
  match mm.write_code(mc) {
    Ok((region, offset)) => {
      inspect(offset, content="0")
      inspect(region.write_pos, content="8")
    }
    Err(_) => panic()
  }
  inspect(mm.total_used(), content="8")
}

///|
test "jit runtime: register and lookup" {
  let runtime = JITRuntime::new(0, 4096)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  mc.emit_ret(30)
  let func = CompiledFunction::new("test", mc, 16)
  if runtime.register(0, func) is Err(_) {
    panic()
  }
  inspect(runtime.lookup(0) is Some(_), content="true")
  inspect(runtime.lookup(1) is None, content="true")
}

///|
test "jit runtime: invalidate" {
  let runtime = JITRuntime::new(0, 4096)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  let func = CompiledFunction::new("test", mc, 0)
  runtime.register(0, func) |> ignore
  runtime.invalidate(0)
  inspect(runtime.lookup(0) is None, content="true")
}

///|
test "jit runtime: statistics" {
  let runtime = JITRuntime::new(0, 4096)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  runtime.register(0, CompiledFunction::new("func0", mc, 0)) |> ignore
  runtime.register(1, CompiledFunction::new("func1", mc, 0)) |> ignore
  let (comps, recomps, count, _, _, _, _) = runtime.stats()
  inspect(comps, content="2")
  inspect(recomps, content="0")
  inspect(count, content="2")
}

///|
test "jit runtime: recompilation" {
  let runtime = JITRuntime::new(0, 4096)
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  runtime.register(0, CompiledFunction::new("func0", mc, 0)) |> ignore
  // Re-register same function (recompilation)
  runtime.register(0, CompiledFunction::new("func0_v2", mc, 0)) |> ignore
  let (comps, recomps, _, _, _, _, _) = runtime.stats()
  inspect(comps, content="1")
  inspect(recomps, content="1")
}

///|
test "int to hex" {
  let zero = 0
  let fifteen = 15
  let sixteen = 16
  let two_fifty_five = 255
  let four_k = 4096
  inspect(zero.to_hex(), content="0")
  inspect(fifteen.to_hex(), content="f")
  inspect(sixteen.to_hex(), content="10")
  inspect(two_fifty_five.to_hex(), content="ff")
  inspect(four_k.to_hex(), content="1000")
}
