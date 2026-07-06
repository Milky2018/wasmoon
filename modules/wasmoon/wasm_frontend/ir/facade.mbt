///|
pub using @milkir {
  type Block,
  type ExternalSymbol,
  type FloatCC,
  type Function,
  type IRBuilder,
  type Inst,
  type IntCC,
  type Metadata,
  type Opcode,
  type OptLevel,
  type OptResult,
  type Signature,
  type StackSlot,
  type Terminator,
  type Type,
  type Value,
  optimize,
  optimize_function,
  optimize_with_level,
  instruction_count,
  validate_function,
}

///|
pub fn type_from_wasm(wasm_type : @types.ValueType) -> Type {
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
