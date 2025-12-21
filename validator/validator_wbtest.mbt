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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
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
    tags: [],
  }
  validate_module(mod) // Should pass
}

// ============================================================
// Error Context Tests
// ============================================================

///|
test "validator: format_validation_error provides descriptive message" {
  let formatted = format_validation_error(InvalidLocalIndex(5))
  assert_true(formatted.contains("invalid local index"))
  assert_true(formatted.contains("5"))
}

///|
test "validator: ValidationErrorContext formats with function index" {
  let ctx = ValidationErrorContext::from_error(
    TypeMismatch("Expected I32, got I64"),
  ).with_func_idx(3)
  let formatted = ctx.format()
  assert_true(formatted.contains("type mismatch"))
  assert_true(formatted.contains("func[3]"))
}

///|
test "validator: ValidationErrorContext formats with instruction offset" {
  let ctx = ValidationErrorContext::from_error(
      StackUnderflow("Expected I32, but stack is empty"),
    )
    .with_func_idx(2)
    .with_instr_offset(5)
    .with_instruction("i32.add")
  let formatted = ctx.format()
  assert_true(formatted.contains("stack underflow"))
  assert_true(formatted.contains("func[2]"))
  assert_true(formatted.contains("offset: 5"))
  assert_true(formatted.contains("i32.add"))
}

///|
test "validator: validate_module_with_context provides location on error" {
  let func : @types.FunctionCode = {
    locals: [],
    body: [I64Const(1L), I32Const(2), I32Add], // Type mismatch at index 2
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
    tags: [],
  }
  let result = try? validate_module_with_context(mod)
  // Should fail with context
  match result {
    Err(WithContext(ctx)) => {
      assert_true(ctx.func_idx is Some(0))
      assert_true(ctx.instr_offset is Some(2))
      assert_true(ctx.instruction is Some(_))
    }
    _ => panic()
  }
}

///|
test "validator: validate_module_with_context reports correct function index" {
  // First function is valid, second has error
  let func0 : @types.FunctionCode = { locals: [], body: [I32Const(42)] }
  let func1 : @types.FunctionCode = { locals: [], body: [LocalGet(99)] } // Invalid local index
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
    tags: [],
  }
  let result = try? validate_module_with_context(mod)
  match result {
    Err(WithContext(ctx)) => {
      // Should report error in function 1 (not 0)
      assert_true(ctx.func_idx is Some(1))
      assert_true(ctx.instr_offset is Some(0))
    }
    _ => panic()
  }
}

///|
test "validator: all ValidationError types have descriptive messages" {
  // Verify each error type produces a non-empty message
  let errors : Array[ValidationError] = [
    TypeMismatch("test"),
    StackUnderflow("test"),
    StackHeightMismatch("test"),
    InvalidFunctionIndex(0),
    InvalidTypeIndex(0),
    InvalidLocalIndex(0),
    InvalidGlobalIndex(0),
    InvalidTableIndex(0),
    InvalidMemoryIndex(0),
    InvalidLabelIndex(0),
    UnreachableCode,
    MultipleMemories,
    MultipleTables,
    InvalidLimits("test"),
  ]
  for err in errors {
    let formatted = format_validation_error(err)
    assert_true(formatted.length() > 20) // Should have meaningful content
    assert_true(formatted.contains("validation error"))
  }
}

// ============================================================
// Data segment offset validation tests (data.wast regression)
// ============================================================

///|
test "validator: data segment with i64 offset should fail" {
  // data.wast line 414: (data (i64.const 0)) - type mismatch
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [{ memory_idx: 0, offset: [I64Const(0L)], init: b"" }],
    tags: [],
  }
  inspect(
    try? validate_module(mod),
    content=(
      #|Err(TypeMismatch("constant expression: expected I32, got I64"))
    ),
  )
}

///|
test "validator: data segment with ref.null offset should fail" {
  // data.wast line 422: (data (ref.null func)) - type mismatch
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [
      { memory_idx: 0, offset: [RefNull(@types.ValueType::FuncRef)], init: b"" },
    ],
    tags: [],
  }
  inspect(
    try? validate_module(mod),
    content=(
      #|Err(TypeMismatch("constant expression: expected I32, got FuncRef"))
    ),
  )
}

///|
test "validator: data segment with empty offset should fail" {
  // data.wast line 430: (data (offset)) - type mismatch (empty expression)
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [{ memory_idx: 0, offset: [], init: b"" }],
    tags: [],
  }
  inspect(
    try? validate_module(mod),
    content=(
      #|Err(TypeMismatch("empty constant expression"))
    ),
  )
}

///|
test "validator: data segment with non-constant instruction should fail" {
  // data.wast line 464: (data (i32.ctz (i32.const 0))) - constant expression required
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [{ memory_idx: 0, offset: [I32Ctz], init: b"" }],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(ConstantExpressionRequired)")
}

///|
test "validator: data segment with nop offset should fail" {
  // data.wast line 472: (data (nop)) - constant expression required
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [{ memory_idx: 0, offset: [Nop], init: b"" }],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(ConstantExpressionRequired)")
}

///|
test "validator: data segment with unknown global should fail" {
  // data.wast line 505: (data (global.get 0)) with no globals - unknown global 0
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [{ memory_idx: 0, offset: [GlobalGet(0)], init: b"" }],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(InvalidGlobalIndex(0))")
}

///|
test "validator: data segment with mutable global offset should fail" {
  // data.wast line 522: global must be immutable for constant expression
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [
      {
        type_: { value_type: @types.ValueType::I32, mutable: true },
        init: [I32Const(0)],
      },
    ],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [{ memory_idx: 0, offset: [GlobalGet(0)], init: b"" }],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(MutableGlobalInConstExpr)")
}

///|
test "validator: data segment with valid i32 const offset should pass" {
  // Valid data segment with i32.const offset
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [{ memory_idx: 0, offset: [I32Const(0)], init: b"hello" }],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Ok(())")
}

///|
test "validator: data segment with immutable global offset should pass" {
  // Valid data segment with immutable global.get offset
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [
      {
        type_: { value_type: @types.ValueType::I32, mutable: false },
        init: [I32Const(0)],
      },
    ],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [{ memory_idx: 0, offset: [GlobalGet(0)], init: b"hello" }],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Ok(())")
}

// ============================================================
// Elem segment offset validation tests (elem.wast regression)
// ============================================================

///|
test "validator: elem segment with i64 offset should fail" {
  // elem.wast line 732: (elem (i64.const 0)) - type mismatch
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      {
        mode: Active(0, [I64Const(0L)]),
        type_: @types.ValueType::FuncRef,
        init: [],
      },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  inspect(
    try? validate_module(mod),
    content=(
      #|Err(TypeMismatch("constant expression: expected I32, got I64"))
    ),
  )
}

///|
test "validator: elem segment with non-constant instruction should fail" {
  // elem.wast line 783: (elem (i32.ctz (i32.const 0))) - constant expression required
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      { mode: Active(0, [I32Ctz]), type_: @types.ValueType::FuncRef, init: [] },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(ConstantExpressionRequired)")
}

///|
test "validator: elem segment with unknown global should fail" {
  // elem.wast line 824: (elem (global.get 0)) with no globals
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      {
        mode: Active(0, [GlobalGet(0)]),
        type_: @types.ValueType::FuncRef,
        init: [],
      },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(InvalidGlobalIndex(0))")
}

///|
test "validator: elem segment with mutable global offset should fail" {
  // elem.wast line 841: global must be immutable for constant expression
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
        },
        init: None,
      },
    ],
    memories: [],
    globals: [
      {
        type_: { value_type: @types.ValueType::I32, mutable: true },
        init: [I32Const(0)],
      },
    ],
    exports: [],
    start: None,
    elems: [
      {
        mode: Active(0, [GlobalGet(0)]),
        type_: @types.ValueType::FuncRef,
        init: [],
      },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(MutableGlobalInConstExpr)")
}

///|
test "validator: elem segment with invalid table index should fail" {
  // elem.wast line 721: (elem (i32.const 0) $f) with no table
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      {
        mode: Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [],
      },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(InvalidTableIndex(0))")
}

///|
test "validator: elem segment type mismatch with table should fail" {
  // elem.wast line 978: funcref elem on externref table
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::ExternRef,
          limits: { min: 1, max: None },
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      {
        mode: Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [],
      },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  inspect((try? validate_module(mod)) is Err(TypeMismatch(_)), content="true")
}

///|
test "validator: elem segment with valid i32 const offset should pass" {
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      {
        mode: Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [],
      },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Ok(())")
}

///|
test "validator: elem init with wrong type should fail" {
  // elem.wast line 853: (elem funcref (ref.null extern)) - type mismatch
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      {
        mode: Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefNull(@types.ValueType::ExternRef)]],
      },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  inspect((try? validate_module(mod)) is Err(TypeMismatch(_)), content="true")
}

///|
test "validator: elem with unknown function should fail" {
  // call_indirect.wast line 1037: (module (table funcref (elem 0 0)))
  // elem segment references function index 0, but no functions are defined
  let mod : @types.Module = {
    types: [],
    imports: [],
    funcs: [],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 2, max: None },
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      {
        mode: Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(0)], [RefFunc(0)]], // references func 0, which doesn't exist
      },
    ],
    codes: [],
    datas: [],
    tags: [],
  }
  // Should fail with "unknown function" error
  inspect((try? validate_module(mod)) is Err(_), content="true")
}

// ============================================================
// Regression tests for func.wast and func_ptrs.wast bugs
// ============================================================

///|
test "regression: invalid type index should fail" {
  // func.wast line 435: (func (type 2)) - unknown type
  // When a function references a type that doesn't exist, validation should fail
  let mod : @types.Module = {
    types: [{ params: [], results: [] }], // only type 0 exists
    imports: [],
    funcs: [2], // references type 2, which doesn't exist
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [{ locals: [], body: [] }],
    datas: [],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Err(InvalidTypeIndex(2))")
}

///|
test "regression: uninitialized non-nullable local should fail" {
  // func.wast line 659: (func (local $x (ref $t)) (drop (local.get $x)))
  // Non-nullable reference locals must be initialized before use
  let mod : @types.Module = {
    types: [{ params: [], results: [] }],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [
      {
        locals: [@types.ValueType::RefFunc], // non-nullable ref local
        body: [LocalGet(0), Drop],
      },
    ],
    datas: [],
    tags: [],
  } // reading uninitialized local
  inspect(try? validate_module(mod), content="Err(UninitializedLocal(0))")
}

///|
test "regression: initialized non-nullable local should pass" {
  // After setting a non-nullable local, reading it should be valid
  // Use FuncRef (nullable) as local type since RefFunc(idx) instruction pushes FuncRef
  let mod : @types.Module = {
    types: [{ params: [], results: [] }],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [
      // Need to declare function 0 for ref.func usage
      {
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(0)]],
        mode: Declarative,
      },
    ],
    codes: [
      {
        locals: [@types.ValueType::FuncRef], // nullable ref local
        body: [
          RefFunc(0), // push a FuncRef value
          LocalSet(0), // set the local
          LocalGet(0), // reading is valid (nullable is always initialized)
          Drop,
        ],
      },
    ],
    datas: [],
    tags: [],
  }
  inspect(try? validate_module(mod), content="Ok(())")
}

///|
test "regression: nullable ref local reading without initialization should pass" {
  // Nullable reference types (FuncRef) have a default value (null),
  // so reading without explicit initialization is valid
  let mod : @types.Module = {
    types: [{ params: [], results: [] }],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [
      {
        locals: [@types.ValueType::FuncRef], // nullable ref local
        body: [LocalGet(0), Drop],
      },
    ],
    datas: [],
    tags: [],
  } // reading uninitialized nullable local is OK
  inspect(try? validate_module(mod), content="Ok(())")
}

///|
test "regression: param with non-nullable ref type should be initialized" {
  // Function parameters are always initialized by the caller
  let mod : @types.Module = {
    types: [{ params: [@types.ValueType::RefFunc], results: [] }],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [{ locals: [], body: [LocalGet(0), Drop] }],
    datas: [], // param 0 is always initialized
    tags: [],
  }
  inspect(try? validate_module(mod), content="Ok(())")
}
