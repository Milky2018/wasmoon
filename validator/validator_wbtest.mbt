///|
test "validator: valid simple function" {
  let func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(1), I32Const(2), I32Add],
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  // Should not raise
  validate_module(mod)
}

///|
test "validator: valid function with params" {
  let func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  validate_module(mod)
}

///|
test "validator: type mismatch - wrong operand type" {
  let func : @types.FunctionCode = {
    locals: [],
    body: [I64Const(1L), I32Const(2), I32Add], // i64 + i32 is invalid
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let result = try {
    validate_module(mod)
    false
  } catch {
    TypeMismatch(_) => true
    _ => false
  }
  inspect(result, content="true")
}

///|
test "validator: stack underflow" {
  let func : @types.FunctionCode = { locals: [], body: [I32Const(1), I32Add] } // needs 2 operands, only has 1
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let result = try {
    validate_module(mod)
    false
  } catch {
    StackUnderflow(_) => true
    _ => false
  }
  inspect(result, content="true")
}

///|
test "validator: invalid local index" {
  let func : @types.FunctionCode = { locals: [], body: [LocalGet(5)] } // no local at index 5
  let func_type : @types.FuncType = { params: [], results: [] }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let result = try {
    validate_module(mod)
    false
  } catch {
    InvalidLocalIndex(5) => true
    _ => false
  }
  inspect(result, content="true")
}

///|
test "validator: valid function call" {
  // func 0: returns i32
  // func 1: calls func 0 and returns result
  let func0 : @types.FunctionCode = { locals: [], body: [I32Const(42)] }
  let func1 : @types.FunctionCode = { locals: [], body: [Call(0)] }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0, 0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func0, func1],
    datas: [],
  }
  validate_module(mod)
}

///|
test "validator: valid global operations" {
  let func : @types.FunctionCode = {
    locals: [],
    body: [GlobalGet(0), I32Const(1), I32Add, GlobalSet(0), GlobalGet(0)],
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let global_type : @types.GlobalType = {
    value_type: @types.ValueType::I32,
    mutable: true,
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [{ type_: global_type, init: [I32Const(0)] }],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  validate_module(mod)
}

///|
test "validator: stack height - function returns too many values" {
  // Function type says returns 1 i32, but body leaves 2 values on stack
  let func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(1), I32Const(2)], // 2 values, but only 1 expected
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let result = try {
    validate_module(mod)
    false
  } catch {
    StackHeightMismatch(_) => true
    _ => false
  }
  inspect(result, content="true")
}

///|
test "validator: stack height - function returns too few values" {
  // Function type says returns 2 values, but body only leaves 1
  let func : @types.FunctionCode = { locals: [], body: [I32Const(1)] }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32, @types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let result = try {
    validate_module(mod)
    false
  } catch {
    StackHeightMismatch(_) => true
    _ => false
  }
  inspect(result, content="true")
}

///|
test "validator: stack height - block returns correct values" {
  // Block returns 2 values, used correctly
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(
        @types.BlockType::TypeIndex(0),
        [I32Const(10), I32Const(20)], // returns 2 i32
      ),
      I32Add,
    ],
  }
  let block_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32, @types.ValueType::I32],
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [block_type, func_type],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  validate_module(mod) // Should pass
}

///|
test "validator: stack height - block leaves wrong number of values" {
  // Block type says 1 result, but body leaves 2
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        I32Const(1),
        I32Const(2),
      ]),
    ],
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let result = try {
    validate_module(mod)
    false
  } catch {
    StackHeightMismatch(_) => true
    _ => false
  }
  inspect(result, content="true")
}

///|
test "validator: stack height - if branches must match" {
  // Both branches of if must leave same number of values
  // This is valid: both branches return 1 i32
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      I32Const(1), // condition
      If(@types.BlockType::Value(@types.ValueType::I32), [I32Const(10)], [
        I32Const(20),
      ]),
    ],
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  validate_module(mod) // Should pass
}

///|
test "validator: stack height - void function with leftover values" {
  // Void function should have empty stack at end
  let func : @types.FunctionCode = { locals: [], body: [I32Const(1)] } // leaves 1 value, but should be 0
  let func_type : @types.FuncType = { params: [], results: [] }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let result = try {
    validate_module(mod)
    false
  } catch {
    StackHeightMismatch(_) => true
    _ => false
  }
  inspect(result, content="true")
}
