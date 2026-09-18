///|
test "validator: deeply nested control uses bounded host stack" {
  let module_ = @wat.parse("(module (func (result i32) i32.const 42))")
  let mut body : Array[@types.Instruction] = [I32Const(42)]
  for depth in 0..<2048 {
    body = match depth % 4 {
      0 => [Block(Value(I32), body)]
      1 => [Loop(Value(I32), body)]
      2 => [I32Const(1), If(Value(I32), body, [I32Const(0)])]
      _ => [TryTable(Value(I32), [], body)]
    }
  }
  module_.codes[0] = { locals: [], body, }
  @validator.validate_module(module_)
  @validator.validate_module_with_context(module_)
}
