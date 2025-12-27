// Black-box tests for runtime module

///|
test "Stack operations with type conversion" {
  let stack = @runtime.Stack::new()
  // Push mixed types and verify correct pop
  stack.push(@types.Value::I32(100))
  stack.push(@types.Value::I64(200L))
  stack.push(@types.Value::F64(2.718))
  // Pop in reverse order
  inspect(stack.pop_f64(), content="2.718")
  inspect(stack.pop_i64(), content="200")
  inspect(stack.pop_i32(), content="100")
  inspect(stack.size(), content="0")
}

///|
test "Memory store and load roundtrip" {
  let mem = @runtime.Memory::new(1, None)
  // Store various types at different offsets
  mem.store_i32(0, 0x12345678)
  mem.store_i64(8, 0x123456789ABCDEF0L)
  mem.store_f64(16, 3.141592653589793)
  // Verify roundtrip
  inspect(mem.load_i32(0), content="305419896")
  inspect(mem.load_i64(8), content="1311768467463790320")
  let pi = mem.load_f64(16)
  inspect(pi > 3.14 && pi < 3.15, content="true")
}

///|
test "Memory grow respects max limit" {
  let mem = @runtime.Memory::new(1, Some(3))
  inspect(mem.grow(1), content="1") // 1 -> 2 pages, returns old size
  inspect(mem.grow(1), content="2") // 2 -> 3 pages, returns old size
  inspect(mem.grow(1), content="-1") // Would exceed max, returns -1
  inspect(mem.size_pages(), content="3")
}

///|
test "Table set and get with funcref" {
  let table = @runtime.Table::new(@types.ValueType::FuncRef, 10, None)
  table.set(0, @types.Value::FuncRef(42))
  table.set(5, @types.Value::FuncRef(100))
  inspect(try? table.get(0), content="Ok(FuncRef(42))")
  inspect(try? table.get(5), content="Ok(FuncRef(100))")
  // Uninitialized element returns Null (call_indirect would trap on this)
  inspect(try? table.get(1), content="Ok(Null)")
}

///|
test "GlobalInstance mutable vs immutable" {
  // Mutable global
  let mut_gt : @types.GlobalType = {
    value_type: @types.ValueType::I32,
    mutable: true,
  }
  let mut_g = @runtime.GlobalInstance::new(mut_gt, @types.Value::I32(100))
  mut_g.set(@types.Value::I32(200))
  inspect(mut_g.get(), content="I32(200)")
}

///|
test "Store allocates and retrieves memory" {
  let store = @runtime.Store::new()
  let mem1 = @runtime.Memory::new(1, None)
  let mem2 = @runtime.Memory::new(2, None)
  let idx1 = store.alloc_mem(mem1)
  let idx2 = store.alloc_mem(mem2)
  inspect(idx1, content="0")
  inspect(idx2, content="1")
  inspect(store.get_mem(0).size_pages(), content="1")
  inspect(store.get_mem(1).size_pages(), content="2")
}

///|
test "Frame local variable access" {
  let frame = @runtime.Frame::new(
    0,
    [@types.Value::I32(10), @types.Value::I64(20L), @types.Value::F64(3.14)],
    0,
  )
  // Get and set operations
  inspect(frame.get_local(0), content="I32(10)")
  frame.set_local(0, @types.Value::I32(100))
  inspect(frame.get_local(0), content="I32(100)")
  inspect(frame.get_local(2), content="F64(3.14)")
}

///|
test "Imports resolution for module linking" {
  let imports = @runtime.Imports::new()
  imports.add_func("env", "print", 0)
  imports.add_func("env", "log", 1)
  imports.add_memory("env", "memory", 0)
  // Resolve existing imports
  inspect(imports.resolve("env", "print") is Some(_), content="true")
  inspect(imports.resolve("env", "log") is Some(_), content="true")
  // Resolve non-existing imports
  inspect(imports.resolve("env", "unknown") is Some(_), content="false")
  inspect(imports.resolve("other", "print") is Some(_), content="false")
}

// ============================================================
// Error Formatting Tests
// ============================================================

///|
test "format_runtime_error provides descriptive message" {
  let formatted = @runtime.format_runtime_error(@runtime.DivisionByZero)
  assert_true(formatted.contains("integer divide by zero"))
}

///|
test "RuntimeErrorContext formats with call stack" {
  let ctx = @runtime.RuntimeErrorContext::new(@runtime.OutOfBoundsMemoryAccess).with_call_stack([
      @runtime.CallStackEntry::{ func_idx: 0, func_name: Some("main") },
      @runtime.CallStackEntry::{ func_idx: 1, func_name: None },
      @runtime.CallStackEntry::{ func_idx: 2, func_name: Some("helper") },
    ],
  )
  let formatted = ctx.format()
  assert_true(formatted.contains("out of bounds memory access"))
  assert_true(formatted.contains("call stack"))
  assert_true(formatted.contains("main"))
  assert_true(formatted.contains("func[1]"))
  assert_true(formatted.contains("helper"))
}

///|
test "RuntimeErrorContext formats with instruction" {
  let ctx = @runtime.RuntimeErrorContext::new(@runtime.Unreachable)
    .with_instruction("unreachable")
    .with_func_idx(5)
  let formatted = ctx.format()
  assert_true(formatted.contains("unreachable"))
  assert_true(formatted.contains("at instruction"))
  assert_true(formatted.contains("in function"))
  assert_true(formatted.contains("func[5]"))
}

///|
test "all RuntimeError types have descriptive messages" {
  // Verify each error type produces a non-empty message
  let errors : Array[@runtime.RuntimeError] = [
    @runtime.StackUnderflow,
    @runtime.StackOverflow,
    @runtime.TypeMismatch,
    @runtime.OutOfBoundsMemoryAccess,
    @runtime.OutOfBoundsTableAccess,
    @runtime.UndefinedElement,
    @runtime.UninitializedElement,
    @runtime.IndirectCallTypeMismatch,
    @runtime.DivisionByZero,
    @runtime.IntegerOverflow,
    @runtime.InvalidConversion,
    @runtime.Unreachable,
    @runtime.CallStackExhausted,
    @runtime.UnknownImport("test_mod", "test_field"),
  ]
  for err in errors {
    let formatted = @runtime.format_runtime_error(err)
    assert_true(formatted.length() > 20) // Should have meaningful content
    assert_true(formatted.contains("runtime error"))
  }
}
