// Black-box tests for types module

///|
test "ValueType equality" {
  inspect(@types.ValueType::I32 == @types.ValueType::I32, content="true")
  inspect(@types.ValueType::I32 == @types.ValueType::I64, content="false")
  inspect(@types.ValueType::F32 == @types.ValueType::F64, content="false")
}

///|
test "ValueType to_string" {
  inspect(@types.ValueType::I32, content="I32")
  inspect(@types.ValueType::I64, content="I64")
  inspect(@types.ValueType::F32, content="F32")
  inspect(@types.ValueType::F64, content="F64")
  inspect(@types.ValueType::FuncRef, content="FuncRef")
  inspect(@types.ValueType::ExternRef, content="ExternRef")
}

///|
test "Value equality" {
  inspect(@types.Value::I32(42) == @types.Value::I32(42), content="true")
  inspect(@types.Value::I32(42) == @types.Value::I32(0), content="false")
  inspect(@types.Value::I64(100L) == @types.Value::I64(100L), content="true")
  inspect(@types.Value::Null == @types.Value::Null, content="true")
}

///|
test "Value to_string" {
  inspect(@types.Value::I32(42), content="I32(42)")
  inspect(@types.Value::I64(100L), content="I64(100)")
  inspect(@types.Value::F32(3.14), content="F32(3.140000104904175)")
  inspect(@types.Value::F64(2.718), content="F64(2.718)")
  inspect(@types.Value::Null, content="Null")
}

///|
test "FuncType equality" {
  let ft1 : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let ft2 : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let ft3 : @types.FuncType = {
    params: [@types.ValueType::I64],
    results: [@types.ValueType::I64],
  }
  inspect(ft1 == ft2, content="true")
  inspect(ft1 == ft3, content="false")
}

///|
test "Limits equality" {
  let l1 : @types.Limits = { min: 1, max: Some(10) }
  let l2 : @types.Limits = { min: 1, max: Some(10) }
  let l3 : @types.Limits = { min: 1, max: None }
  inspect(l1 == l2, content="true")
  inspect(l1 == l3, content="false")
}

///|
test "BlockType variants" {
  inspect(@types.BlockType::Empty, content="Empty")
  inspect(@types.BlockType::Value(@types.ValueType::I32), content="Value(I32)")
  inspect(@types.BlockType::TypeIndex(0), content="TypeIndex(0)")
}

///|
test "Instruction equality" {
  inspect(
    @types.Instruction::I32Const(42) == @types.Instruction::I32Const(42),
    content="true",
  )
  inspect(
    @types.Instruction::I32Const(42) == @types.Instruction::I32Const(0),
    content="false",
  )
  inspect(@types.Instruction::Nop == @types.Instruction::Nop, content="true")
  inspect(
    @types.Instruction::Nop == @types.Instruction::Unreachable,
    content="false",
  )
}

///|
test "Module::new creates empty module" {
  let m = @types.Module::new()
  inspect(m.types.length(), content="0")
  inspect(m.imports.length(), content="0")
  inspect(m.funcs.length(), content="0")
  inspect(m.exports.length(), content="0")
  inspect(m.codes.length(), content="0")
  inspect(m.start, content="None")
}

///|
test "Export and ExportDesc" {
  let exp : @types.Export = { name: "add", desc: @types.ExportDesc::Func(0) }
  inspect(exp.name, content="add")
  inspect(exp.desc, content="Func(0)")
}

///|
test "Import and ImportDesc" {
  let imp : @types.Import = {
    mod_name: "env",
    name: "print",
    desc: @types.ImportDesc::Func(0),
  }
  inspect(imp.mod_name, content="env")
  inspect(imp.name, content="print")
  inspect(imp.desc, content="Func(0)")
}

///|
test "GlobalType" {
  let gt : @types.GlobalType = {
    value_type: @types.ValueType::I32,
    mutable: true,
  }
  inspect(gt.value_type, content="I32")
  inspect(gt.mutable, content="true")
}
