// Black-box tests for runtime module

///|
test "Stack basic operations" {
  let stack = @runtime.Stack::new()
  inspect(stack.size(), content="0")
  stack.push(@types.Value::I32(42))
  inspect(stack.size(), content="1")
  inspect(stack.peek(), content="I32(42)")
  inspect(stack.pop(), content="I32(42)")
  inspect(stack.size(), content="0")
}

///|
test "Stack typed pop operations" {
  let stack = @runtime.Stack::new()
  stack.push(@types.Value::I32(100))
  inspect(stack.pop_i32(), content="100")
  stack.push(@types.Value::I64(200L))
  inspect(stack.pop_i64(), content="200")
  stack.push(@types.Value::F32(3.14))
  let f32_val = stack.pop_f32()
  inspect(f32_val > 3.13 && f32_val < 3.15, content="true")
  stack.push(@types.Value::F64(2.718))
  inspect(stack.pop_f64(), content="2.718")
}

///|
test "Stack clear" {
  let stack = @runtime.Stack::new()
  stack.push(@types.Value::I32(1))
  stack.push(@types.Value::I32(2))
  stack.push(@types.Value::I32(3))
  inspect(stack.size(), content="3")
  stack.clear()
  inspect(stack.size(), content="0")
}

///|
test "Memory basic operations" {
  let mem = @runtime.Memory::new(1, None) // 1 page = 64KB
  inspect(mem.size_pages(), content="1")
  mem.store_i32(0, 42)
  inspect(mem.load_i32(0), content="42")
  mem.store_byte(100, b'\x7F')
  inspect(mem.load_byte(100), content="b'\\x7F'")
}

///|
test "Memory grow" {
  let mem = @runtime.Memory::new(1, Some(3))
  inspect(mem.size_pages(), content="1")
  let result = mem.grow(1)
  inspect(result, content="1") // Returns old size
  inspect(mem.size_pages(), content="2")
}

///|
test "Memory i64 operations" {
  let mem = @runtime.Memory::new(1, None)
  mem.store_i64(0, 0x123456789ABCDEF0L)
  inspect(mem.load_i64(0), content="1311768467463790320")
}

///|
test "Memory float operations" {
  let mem = @runtime.Memory::new(1, None)
  mem.store_f32(0, 3.14)
  let loaded = mem.load_f32(0)
  inspect(loaded > 3.13 && loaded < 3.15, content="true")
  mem.store_f64(8, 2.718281828)
  let loaded64 = mem.load_f64(8)
  inspect(loaded64 > 2.71 && loaded64 < 2.72, content="true")
}

///|
test "Memory fill" {
  let mem = @runtime.Memory::new(1, None)
  mem.fill(0, b'\xFF', 10)
  inspect(mem.load_byte(0), content="b'\\xFF'")
  inspect(mem.load_byte(9), content="b'\\xFF'")
}

///|
test "Table basic operations" {
  let table = @runtime.Table::new(@types.ValueType::FuncRef, 10, Some(100))
  inspect(table.size(), content="10")
  table.set(0, @types.Value::FuncRef(42))
  inspect(table.get(0), content="FuncRef(42)")
}

///|
test "Table grow" {
  let table = @runtime.Table::new(@types.ValueType::FuncRef, 5, Some(20))
  inspect(table.size(), content="5")
  let old_size = table.grow(5, @types.Value::Null)
  inspect(old_size, content="5")
  inspect(table.size(), content="10")
}

///|
test "GlobalInstance operations" {
  let gt : @types.GlobalType = {
    value_type: @types.ValueType::I32,
    mutable: true,
  }
  let g = @runtime.GlobalInstance::new(gt, @types.Value::I32(100))
  inspect(g.get(), content="I32(100)")
  g.set(@types.Value::I32(200))
  inspect(g.get(), content="I32(200)")
}

///|
test "Store basic operations" {
  let store = @runtime.Store::new()
  let mem = @runtime.Memory::new(1, None)
  let mem_idx = store.alloc_mem(mem)
  inspect(mem_idx, content="0")
  let retrieved_mem = store.get_mem(0)
  inspect(retrieved_mem.size_pages(), content="1")
}

///|
test "Frame local variables" {
  let frame = @runtime.Frame::new(
    0,
    [@types.Value::I32(10), @types.Value::I64(20L)],
    0,
  )
  inspect(frame.get_local(0), content="I32(10)")
  inspect(frame.get_local(1), content="I64(20)")
  frame.set_local(0, @types.Value::I32(100))
  inspect(frame.get_local(0), content="I32(100)")
}

///|
test "Linker basic operations" {
  let linker = @runtime.Linker::new()
  let store = linker.get_store()
  inspect(store.funcs.length(), content="0")
}

///|
test "Imports resolution" {
  let imports = @runtime.Imports::new()
  imports.add_func("env", "print", 0)
  imports.add_memory("env", "memory", 0)
  inspect(imports.resolve("env", "print") is Some(_), content="true")
  inspect(imports.resolve("env", "unknown") is Some(_), content="false")
}

///|
test "ModuleInstance::new" {
  let inst = @runtime.ModuleInstance::new()
  inspect(inst.types.length(), content="0")
  inspect(inst.func_addrs.length(), content="0")
  inspect(inst.exports.length(), content="0")
}

///|
test "ExternVal variants" {
  let func_val = @runtime.ExternVal::Func(0)
  let table_val = @runtime.ExternVal::Table(1)
  let mem_val = @runtime.ExternVal::Memory(2)
  let global_val = @runtime.ExternVal::Global(3)
  // Test pattern matching
  inspect(func_val is @runtime.ExternVal::Func(_), content="true")
  inspect(table_val is @runtime.ExternVal::Table(_), content="true")
  inspect(mem_val is @runtime.ExternVal::Memory(_), content="true")
  inspect(global_val is @runtime.ExternVal::Global(_), content="true")
}
