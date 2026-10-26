///|
/// Logical locations are independent of physical addresses. Indexed struct
/// types can alias through subtyping; field invalidation must not use a type
/// index as evidence that two objects are disjoint.
pub(all) enum Location {
  StructField(Int32, Int32)
  ArrayLength
  ArrayElements
  Unknown
} derive(Eq, Debug)

///|
pub extend Location with Eq::{equal, not_equal}

///|
pub extend Location with Debug::{to_repr}

///|
/// A single conservative contract for Wasm optimization and native borrowing.
/// Allocation may move a payload without changing a stable reference or its
/// logical field values. Raw memory writes can invalidate a physical view even
/// when the current producer cannot describe their logical alias location.
pub struct Effects {
  read : Location?
  write : Location?
  may_trap : Bool
  may_collect : Bool
  may_reenter : Bool
  may_suspend : Bool
  may_replace_heap : Bool
  invalidates_address : Bool
  allocation : Bool
  checked_reference : Int32?
}

///|
fn effects(
  read~ : Location? = None,
  write~ : Location? = None,
  may_trap~ : Bool = false,
  may_collect~ : Bool = false,
  may_reenter~ : Bool = false,
  may_suspend~ : Bool = false,
  may_replace_heap~ : Bool = false,
  invalidates_address~ : Bool = false,
  allocation~ : Bool = false,
  checked_reference~ : Int32? = None,
) -> Effects {
  {
    read,
    write,
    may_trap,
    may_collect,
    may_reenter,
    may_suspend,
    may_replace_heap,
    invalidates_address,
    allocation,
    checked_reference,
  }
}

///|
fn unknown() -> Effects {
  effects(
    read=Some(Unknown),
    write=Some(Unknown),
    may_trap=true,
    may_collect=true,
    may_reenter=true,
    may_suspend=true,
    may_replace_heap=true,
    invalidates_address=true,
  )
}

///|
/// Unknown dialect operations are never admitted by an optimistic default.
/// The exhaustive typed match makes every new Wasm operation choose a contract.
pub fn analyze(opcode : @milkir.Opcode) -> Effects {
  match opcode {
    Scalar(IntBinary(SignedDiv | UnsignedDiv | SignedRem | UnsignedRem))
    | Scalar(Convert(FloatToSignedInt | FloatToUnsignedInt)) =>
      effects(may_trap=true)
    Scalar(_) | Vector(_) => effects()
    GlobalValue(_) => effects(read=Some(Unknown))
    Memory(Load(_) | LoadNarrow(_, _, _)) =>
      effects(read=Some(Unknown), may_trap=true)
    Memory(_) | Call(_) => unknown()
    Ext(extension, _) =>
      match @wasm_milkir.decode(extension) {
        None => unknown()
        Some(operation) => wasm_effects(operation)
      }
  }
}

///|
fn wasm_effects(operation : @wasm_milkir.WasmOpcode) -> Effects {
  match operation {
    StructGet(type_, field)
    | StructGetS(type_, field, _)
    | StructGetU(type_, field, _) =>
      effects(
        read=Some(StructField(type_, field)),
        may_trap=true,
        checked_reference=Some(0),
      )
    StructSet(type_, field) =>
      effects(
        write=Some(StructField(type_, field)),
        may_trap=true,
        checked_reference=Some(0),
      )
    ArrayLen =>
      effects(read=Some(ArrayLength), may_trap=true, checked_reference=Some(0))
    ArrayGet(_) | ArrayGetS(_, _) | ArrayGetU(_, _) =>
      effects(
        read=Some(ArrayElements),
        may_trap=true,
        checked_reference=Some(0),
      )
    ArraySet(_) =>
      effects(
        write=Some(ArrayElements),
        may_trap=true,
        checked_reference=Some(0),
      )
    ArrayFill(_) | ArrayCopy(_, _) =>
      effects(
        read=Some(ArrayElements),
        write=Some(ArrayElements),
        may_trap=true,
        invalidates_address=true,
        checked_reference=Some(0),
      )
    ArrayInitData(_, _) | ArrayInitElem(_, _) =>
      effects(
        write=Some(ArrayElements),
        may_trap=true,
        invalidates_address=true,
      )
    StructNew(_)
    | StructNewDefault(_)
    | ArrayNew(_)
    | ArrayNewDefault(_)
    | ArrayNewFixed(_, _)
    | ArrayNewData(_, _)
    | ArrayNewElem(_, _) =>
      effects(
        may_trap=true,
        may_collect=true,
        invalidates_address=true,
        allocation=true,
      )
    I31New | RefEq | AnyConvertExtern | ExternConvertAny => effects()
    I31GetS | I31GetU => effects(may_trap=true)
    // Native ref tests/casts only inspect retained type metadata and identity
    // tables. They neither allocate nor invoke managed/guest code; a cast's
    // failure trap remains observable and may not be speculated.
    RefTest(_, _) => effects(read=Some(Unknown))
    RefCast(_, _) => effects(read=Some(Unknown), may_trap=true)
    // These operations remain conservative until their embedding contracts
    // describe all root, heap, exception and continuation state transitions.
    WasmCall(_)
    | SafepointPoll(_, _, _, _)
    | WasmCallIndirect(_, _)
    | CallRef(_)
    | ReturnCall(_)
    | ReturnCallIndirect(_, _)
    | ReturnCallRef(_)
    | GetFuncRef(_)
    | Throw(_)
    | ThrowRef
    | TryTableBegin(_)
    | TryTableEnd(_)
    | GetExceptionTag
    | GetExceptionValue(_)
    | GetExceptionValueCount
    | Delegate(_)
    | SpillLocalsForThrow(_)
    | GetSpilledLocal(_)
    | GetExceptionRef
    | ContNew(_)
    | ContBind(_, _)
    | ContSuspend(_)
    | ContResume(_, _, _, _)
    | ContSwitch(_, _) => unknown()
  }
}

///|
pub fn Effects::preserves_checked_references(self : Effects) -> Bool {
  !self.may_reenter && !self.may_replace_heap && !self.may_suspend
}

///|
pub fn Effects::preserves_physical_addresses(self : Effects) -> Bool {
  self.preserves_checked_references() &&
  !self.may_collect &&
  !self.invalidates_address
}

///|
pub fn Effects::preserves_struct_values(self : Effects) -> Bool {
  self.preserves_checked_references() && !(self.write is Some(Unknown))
}
