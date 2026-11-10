///|
/// Unknown instructions remain collecting. Only operations whose existing
/// lowering cannot allocate guest objects, invoke host code or suspend qualify.
fn noncollecting_instruction(instruction : @types.Instruction) -> Bool {
  match instruction {
    Unreachable
    | Nop
    | Drop
    | Select
    | SelectTyped(_)
    | LocalGet(_)
    | LocalSet(_)
    | LocalTee(_)
    | GlobalGet(_)
    | GlobalSet(_)
    | Br(_)
    | BrIf(_)
    | BrTable(_, _)
    | Return
    | RefNull(_)
    | RefIsNull
    | RefAsNonNull
    | RefEqInstr
    | RefI31
    | I31GetS
    | I31GetU
    | StructGet(_, _)
    | StructGetS(_, _)
    | StructGetU(_, _)
    | StructSet(_, _)
    | ArrayGet(_)
    | ArrayGetS(_)
    | ArrayGetU(_)
    | ArraySet(_)
    | ArrayLen
    | I32Const(_)
    | I64Const(_)
    | F32Const(_)
    | F64Const(_)
    | I32Eqz
    | I32Eq
    | I32Ne
    | I32LtS
    | I32LtU
    | I32GtS
    | I32GtU
    | I32LeS
    | I32LeU
    | I32GeS
    | I32GeU
    | I32Clz
    | I32Ctz
    | I32Popcnt
    | I32Add
    | I32Sub
    | I32Mul
    | I32DivS
    | I32DivU
    | I32RemS
    | I32RemU
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU
    | I32Rotl
    | I32Rotr
    | I32Extend8S
    | I32Extend16S
    | I64Eqz
    | I64Eq
    | I64Ne
    | I64LtS
    | I64LtU
    | I64GtS
    | I64GtU
    | I64LeS
    | I64LeU
    | I64GeS
    | I64GeU
    | I64Clz
    | I64Ctz
    | I64Popcnt
    | I64Add
    | I64Add128
    | I64Sub128
    | I64Sub
    | I64Mul
    | I64MulWideS
    | I64MulWideU
    | I64DivS
    | I64DivU
    | I64RemS
    | I64RemU
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU
    | I64Rotl
    | I64Rotr
    | I64Extend8S
    | I64Extend16S
    | I64Extend32S
    | F32Eq
    | F32Ne
    | F32Lt
    | F32Gt
    | F32Le
    | F32Ge
    | F32Abs
    | F32Neg
    | F32Ceil
    | F32Floor
    | F32Trunc
    | F32Nearest
    | F32Sqrt
    | F32Add
    | F32Sub
    | F32Mul
    | F32Div
    | F32Min
    | F32Max
    | F32Copysign
    | F64Eq
    | F64Ne
    | F64Lt
    | F64Gt
    | F64Le
    | F64Ge
    | F64Abs
    | F64Neg
    | F64Ceil
    | F64Floor
    | F64Trunc
    | F64Nearest
    | F64Sqrt
    | F64Add
    | F64Sub
    | F64Mul
    | F64Div
    | F64Min
    | F64Max
    | F64Copysign
    | I32WrapI64
    | I32TruncF32S
    | I32TruncF32U
    | I32TruncF64S
    | I32TruncF64U
    | I64ExtendI32S
    | I64ExtendI32U
    | I64TruncF32S
    | I64TruncF32U
    | I64TruncF64S
    | I64TruncF64U
    | F32ConvertI32S
    | F32ConvertI32U
    | F32ConvertI64S
    | F32ConvertI64U
    | F32DemoteF64
    | F64ConvertI32S
    | F64ConvertI32U
    | F64ConvertI64S
    | F64ConvertI64U
    | F64PromoteF32
    | I32ReinterpretF32
    | I64ReinterpretF64
    | F32ReinterpretI32
    | F64ReinterpretI64
    | I32TruncSatF32S
    | I32TruncSatF32U
    | I32TruncSatF64S
    | I32TruncSatF64U
    | I64TruncSatF32S
    | I64TruncSatF32U
    | I64TruncSatF64S
    | I64TruncSatF64U => true
    _ => false
  }
}

///|
/// A least fixed point admits only closed acyclic local call chains. Imports,
/// recursion, unknown operations and exhausted analysis bounds keep full roots.
/// Entry/loop polling is excluded by the enclosing embedding-mode check.
fn noncollecting_local_functions(
  module_ : @types.Module,
  imports : Int32,
  base : Int32,
) -> Map[Int32, @wasm_milkir.WasmFunctionEffects] {
  let count = module_.codes.length()
  if count > 65536 {
    return Map([])
  }
  let callers : Array[Array[Int32]] = Array::makei(count, _ => [])
  let dependencies = Array::make(count, 0)
  let admitted = Array::make(count, true)
  let read_only = Array::make(count, true)
  let ready : Array[Int32] = []
  let mut work = 0
  for index, code in module_.codes {
    let pending = [code.body]
    while pending.pop() is Some(body) {
      for instruction in body {
        work += 1
        if work > 1048576 {
          return Map([])
        }
        if instruction is (GlobalSet(_) | StructSet(_, _) | ArraySet(_)) {
          read_only[index] = false
        }
        match instruction {
          Block(_, nested) | Loop(_, nested) => pending.push(nested)
          If(_, yes, no) => {
            pending.push(yes)
            pending.push(no)
          }
          Call(target) =>
            if target >= imports && target - imports < count {
              let callee_index = target - imports
              dependencies[index] += 1
              callers[callee_index].push(index)
            } else {
              admitted[index] = false
            }
          _ =>
            if !noncollecting_instruction(instruction) {
              admitted[index] = false
            }
        }
      }
    }
    if admitted[index] && dependencies[index] == 0 {
      ready.push(index)
    }
  }
  let result : Map[Int32, @wasm_milkir.WasmFunctionEffects] = Map([])
  while ready.pop() is Some(index) {
    result[base + imports + index] = if read_only[index] {
      NonCollectingReadOnly
    } else {
      NonCollectingReadWrite
    }
    for caller in callers[index] {
      read_only[caller] = read_only[caller] && read_only[index]
      dependencies[caller] -= 1
      if admitted[caller] && dependencies[caller] == 0 {
        ready.push(caller)
      }
    }
  }
  result
}
