///|
using @milkir {
  type Block,
  type FloatCC,
  type Function,
  type IRBuilder,
  type IntCC,
  type Opcode,
  type Type,
  type Value,
}

///|
fn type_from_wasm(wasm_type : @types.ValueType) -> Type {
  match wasm_type {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      FuncRef
    ExternRef | RefExtern | NullExternRef => ExternRef
    _ => Ref
  }
}
