///|
test "wat_printer: element segments" {
  let mod_ = @types.Module::new()
  mod_.elems.push({
    mode: @types.ElemMode::Passive,
    type_: @types.ValueType::FuncRef,
    init: [[@types.Instruction::RefFunc(0)], [@types.Instruction::RefFunc(1)]],
  })
  mod_.elems.push({
    mode: @types.ElemMode::Active(0, [@types.Instruction::I32Const(0)]),
    type_: @types.ValueType::FuncRef,
    init: [[@types.Instruction::RefFunc(0)], [@types.Instruction::RefFunc(1)]],
  })
  mod_.elems.push({
    mode: @types.ElemMode::Declarative,
    type_: @types.ValueType::FuncRef,
    init: [[@types.Instruction::RefFunc(0)]],
  })
  let output = module_to_wat(mod_)
  let expected =
    #|(module
    #|  (elem (;0;) funcref (ref.func 0) (ref.func 1))
    #|  (elem (;1;) (i32.const 0) funcref (ref.func 0) (ref.func 1))
    #|  (elem (;2;) declare funcref (ref.func 0))
    #|)
    #|
  inspect(output, content=expected)
}
