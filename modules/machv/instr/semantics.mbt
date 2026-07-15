///|
/// Whether an instruction must be retained even when none of its definitions
/// are live.
pub fn Opcode::has_observable_effect(self : Opcode) -> Bool {
  match self {
    // Loads can trap (for example through guard pages or invalid pointers).
    LoadPtr(_, _)
    | LoadPtrRegOffset(_, _, _, _)
    | LoadPtrNarrowRegOffset(_, _, _, _, _)
    | LoadPtrNarrow(_, _, _) => true
    // Memory stores are observable.
    Store(_, _)
    | StackStore(_)
    | StorePtr(_, _)
    | StorePtrRegOffset(_, _, _, _)
    | StorePtrNarrowRegOffset(_, _, _, _) => true
    // Calls and conditional helpers may change embedding state.
    CallExternalIfI32NeImm(_, _)
    | ReturnCallIndirect(_, _)
    | CallPtr(_, _, _)
    | CallDirect(_, _, _, _)
    | CallExternal(_, _, _, _) => true
    // Traps are observable control flow.
    TrapIfZero(_, _)
    | TrapIfDivOverflow(_, _)
    | TrapIfUge(_)
    | TrapIfUgt(_)
    | TrapIf(_, _) => true
    // Flag-setting compares must remain paired with their consumers.
    IntCmp(_) => true
    _ => false
  }
}

///|
/// Whether register allocation may cheaply clone this instruction near a use.
pub fn Opcode::is_rematerializable(self : Opcode) -> Bool {
  match self {
    LoadConst(_)
    | LoadConstF32(_)
    | LoadConstF64(_)
    | LoadExternalFuncAddr(_)
    | LoadCodeAddr(_) => true
    _ => false
  }
}
