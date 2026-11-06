///|
/// Share call transfer planning between emission and its register footprint.
fn plan_call_arguments(
  allocation : @vcode.Allocation,
  instruction : @vcode.Instruction,
  types : Array[@native.ValueType],
  locations : ArrayView[CallArgumentLocation],
  stack_size : Int32,
  operand_start~ : Int32 = 0,
  stack_base~ : Int32 = 0,
  callee? : (Int32, @vcode.PhysicalReg),
  result_area? : (Int32, @vcode.PhysicalReg),
) -> @vcode.ResolvedCallTransferPlan raise @vcode.CallTransferError {
  let transfers = @vcode.call_argument_transfers(
    allocation,
    instruction,
    types,
    locations,
    operand_start~,
    stack_base~,
    callee?,
    result_area?,
  )
  let int_scratch : Array[@vcode.PhysicalReg] = []
  for id in [10, 11, 0] {
    let used_by_callee = callee is Some((_, destination)) &&
      destination.id == id
    let used_by_result_area = result_area is Some((_, destination)) &&
      destination.id == id
    if !used_by_callee && !used_by_result_area {
      int_scratch.push(@vcode.PhysicalReg::new(id, Int))
    }
  }
  @vcode.plan_resolved_call_transfers(
    allocation,
    transfers,
    stack_base,
    stack_size,
    int_scratch,
    [
      @vcode.PhysicalReg::new(14, FpVector),
      @vcode.PhysicalReg::new(15, FpVector),
    ],
    int_transfer_scratch(),
    fp_transfer_scratch(),
    allocation.safepoint_roots(instruction).map(entry => entry.1),
  )
}

///|
fn instruction_call_plan(
  inst : X64Inst,
  allocation : @vcode.Allocation,
  instruction : @vcode.Instruction,
  stack_base~ : Int32 = 0,
) -> @vcode.ResolvedCallTransferPlan? raise @vcode.CallTransferError {
  match inst {
    PlatformCall(_, signature) | ReturnsTwicePlatformCall(_, signature) => {
      let layout = platform_call_layout(signature.params)
      Some(
        plan_call_arguments(
          allocation,
          instruction,
          signature.params,
          layout.arguments,
          layout.stack_size,
          stack_base~,
        ),
      )
    }
    InternalCall(_, signature, plan)
    | InternalCallIndirect(signature, plan)
    | TailCallDirect(_, signature, plan)
    | TailCallIndirect(signature, plan) => {
      let indirect = inst is InternalCallIndirect(_, _) ||
        inst is TailCallIndirect(_, _)
      let operand_start = if indirect { 1 } else { 0 }
      let callee = if indirect { Some((0, int_physical(0))) } else { None }
      let result_area = if inst is TailCallDirect(_, _, _) ||
        inst is TailCallIndirect(_, _) {
        plan
        .result_area_register()
        .map(destination => {
          (signature.params.length() + operand_start, destination)
        })
      } else {
        None
      }
      Some(
        plan_call_arguments(
          allocation,
          instruction,
          signature.params,
          plan.arguments,
          plan.stack_size,
          operand_start~,
          stack_base~,
          callee?,
          result_area?,
        ),
      )
    }
    _ => None
  }
}
