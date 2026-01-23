///|
/// Unit tests for ValueType helpers.

///|
test "ValueType::jit_abi_code basic numeric types" {
  inspect(ValueType::I32.jit_abi_code(), content="0")
  inspect(ValueType::I64.jit_abi_code(), content="1")
  inspect(ValueType::F32.jit_abi_code(), content="2")
  inspect(ValueType::F64.jit_abi_code(), content="3")
  inspect(ValueType::V128.jit_abi_code(), content="4")
}

///|
test "ValueType::jit_abi_code reference types use i64 slots" {
  inspect(ValueType::FuncRef.jit_abi_code(), content="1")
  inspect(ValueType::RefFunc.jit_abi_code(), content="1")
  inspect(ValueType::ExternRef.jit_abi_code(), content="1")
  inspect(ValueType::NullRef.jit_abi_code(), content="1")
  inspect(ValueType::RefNullStruct(0).jit_abi_code(), content="1")
}
