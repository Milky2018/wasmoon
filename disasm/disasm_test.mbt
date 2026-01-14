// Tests for WASM disassembler

///|
test "disassemble empty module" {
  let mod_ = @types.Module::new()
  let result = disassemble(mod_)
  inspect(result, content="(module\n)\n")
}

///|
test "disassemble module with types" {
  let mod_ = @types.Module::new()
  mod_.types.push(
    @types.SubType::func([@types.ValueType::I32], [@types.ValueType::I32]),
  )
  mod_.types.push(
    @types.SubType::func([@types.ValueType::I32, @types.ValueType::I32], [
      @types.ValueType::I32,
    ]),
  )
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (type (;0;) (func (param i32) (result i32)))
    #|  (type (;1;) (func (param i32 i32) (result i32)))
    #|)
    #|
  inspect(result, content=expected)
}

///|
test "disassemble module with memory" {
  let mod_ = @types.Module::new()
  mod_.memories.push({
    limits: { min: 1, max: None },
    is_memory64: false,
    page_size_log2: 16,
  })
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (memory (;0;) 1)
    #|)
    #|
  inspect(result, content=expected)
}

///|
test "disassemble module with memory and max" {
  let mod_ = @types.Module::new()
  mod_.memories.push({
    limits: { min: 1, max: Some(16) },
    is_memory64: false,
    page_size_log2: 16,
  })
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (memory (;0;) 1 16)
    #|)
    #|
  inspect(result, content=expected)
}

///|
test "disassemble simple function" {
  let mod_ = @types.Module::new()
  // Add type: (i32, i32) -> i32
  mod_.types.push(
    @types.SubType::func([@types.ValueType::I32, @types.ValueType::I32], [
      @types.ValueType::I32,
    ]),
  )
  // Add function with type 0
  mod_.funcs.push(0)
  // Add function body: local.get 0, local.get 1, i32.add
  mod_.codes.push({
    locals: [],
    body: [
      @types.Instruction::LocalGet(0),
      @types.Instruction::LocalGet(1),
      @types.Instruction::I32Add,
    ],
  })
  // Add export
  mod_.exports.push({ name: "add", desc: @types.ExportDesc::Func(0) })
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (type (;0;) (func (param i32 i32) (result i32)))
    #|  (func (;0;) (type 0) (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add
    #|  )
    #|  (export "add" (func 0))
    #|)
    #|
  inspect(result, content=expected)
}

///|
test "disassemble function with locals" {
  let mod_ = @types.Module::new()
  mod_.types.push(@types.SubType::func([], [@types.ValueType::I32]))
  mod_.funcs.push(0)
  mod_.codes.push({
    locals: [
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I64,
    ],
    body: [@types.Instruction::I32Const(42)],
  })
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (type (;0;) (func (result i32)))
    #|  (func (;0;) (type 0) (result i32)
    #|    (local i32 i32)
    #|    (local i64)
    #|    i32.const 42
    #|  )
    #|)
    #|
  inspect(result, content=expected)
}

///|
test "disassemble block instruction" {
  let mod_ = @types.Module::new()
  mod_.types.push(@types.SubType::func([], [@types.ValueType::I32]))
  mod_.funcs.push(0)
  mod_.codes.push({
    locals: [],
    body: [
      @types.Instruction::Block(
        @types.BlockType::Value(@types.ValueType::I32),
        [@types.Instruction::I32Const(1)],
      ),
    ],
  })
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (type (;0;) (func (result i32)))
    #|  (func (;0;) (type 0) (result i32)
    #|    block (result i32)
    #|      i32.const 1
    #|    end
    #|  )
    #|)
    #|
  inspect(result, content=expected)
}

///|
test "disassemble if-else instruction" {
  let mod_ = @types.Module::new()
  mod_.types.push(
    @types.SubType::func([@types.ValueType::I32], [@types.ValueType::I32]),
  )
  mod_.funcs.push(0)
  mod_.codes.push({
    locals: [],
    body: [
      @types.Instruction::LocalGet(0),
      @types.Instruction::If(
        @types.BlockType::Value(@types.ValueType::I32),
        [@types.Instruction::I32Const(1)],
        [@types.Instruction::I32Const(0)],
      ),
    ],
  })
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (type (;0;) (func (param i32) (result i32)))
    #|  (func (;0;) (type 0) (param i32) (result i32)
    #|    local.get 0
    #|    if (result i32)
    #|      i32.const 1
    #|    else
    #|      i32.const 0
    #|    end
    #|  )
    #|)
    #|
  inspect(result, content=expected)
}

///|
test "disassemble global" {
  let mod_ = @types.Module::new()
  mod_.globals.push({
    type_: { value_type: @types.ValueType::I32, mutable: true },
    init: [@types.Instruction::I32Const(0)],
  })
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (global (;0;) (mut i32) (i32.const 0))
    #|)
    #|
  inspect(result, content=expected)
}

///|
test "disassemble import" {
  let mod_ = @types.Module::new()
  mod_.types.push(@types.SubType::func([@types.ValueType::I32], []))
  mod_.imports.push({
    mod_name: "console",
    name: "log",
    desc: @types.ImportDesc::Func(0),
  })
  let result = disassemble(mod_)
  let expected =
    #|(module
    #|  (type (;0;) (func (param i32)))
    #|  (import "console" "log" (func (type 0)))
    #|)
    #|
  inspect(result, content=expected)
}
