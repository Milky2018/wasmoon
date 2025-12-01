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
  inspect(
    try? validate_module(mod),
    content=(
      #|Err(TypeMismatch("Expected I32, got I64"))
    ),
  )
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
  inspect(
    try? validate_module(mod),
    content=(
      #|Err(StackUnderflow("Expected I32, but stack is empty"))
    ),
  )
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
  inspect(try? validate_module(mod), content="Err(InvalidLocalIndex(5))")
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
  inspect(
    try? validate_module(mod),
    content=(
      #|Err(StackHeightMismatch("function return: expected stack height 1, got 2"))
    ),
  )
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
  inspect(
    (try? validate_module(mod)) is Err(StackHeightMismatch(_)),
    content="true",
  )
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
  inspect(
    (try? validate_module(mod)) is Err(StackHeightMismatch(_)),
    content="true",
  )
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
  inspect(
    (try? validate_module(mod)) is Err(StackHeightMismatch(_)),
    content="true",
  )
}

///|
test "validator: control flow - valid br in block" {
  // Block with br that exits with correct value
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        I32Const(42),
        Br(0),
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
test "validator: control flow - invalid label index" {
  // br with invalid label index (no enclosing block)
  let func : @types.FunctionCode = { locals: [], body: [Br(0)] }
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
  inspect(
    (try? validate_module(mod)) is Err(InvalidLabelIndex(0)),
    content="true",
  )
}

///|
test "validator: control flow - nested blocks with br" {
  // Nested blocks: inner br jumps to outer block
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        Block(
          @types.BlockType::Empty,
          [I32Const(100), Br(1)], // br 1 jumps to outer block
        ),
        I32Const(0), // unreachable
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
test "validator: control flow - br_if with correct type" {
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        I32Const(42),
        I32Const(1), // condition
        BrIf(0), // conditional branch
        Drop,
        I32Const(0),
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
test "validator: control flow - loop with br back to start" {
  // Loop that uses br 0 to jump back to start (expects params, not results)
  let loop_type : @types.FuncType = { params: [], results: [] }
  let func_type : @types.FuncType = { params: [], results: [] }
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Loop(
        @types.BlockType::TypeIndex(0),
        [Br(0)], // br 0 in loop jumps to start, carries params (empty)
      ),
    ],
  }
  let mod : @types.Module = {
    types: [loop_type, func_type],
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
test "validator: control flow - return in nested block" {
  let func : @types.FunctionCode = {
    locals: [],
    body: [Block(@types.BlockType::Empty, [I32Const(42), Return]), I32Const(0)],
  } // unreachable after block with return
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
test "validator: control flow - br_table basic" {
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(@types.BlockType::Value(@types.ValueType::I32), [
        I32Const(42), // value to branch with
        I32Const(0), // index
        BrTable([0], 0), // all targets go to same block
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
