///|
pub(all) enum CallingConvention {
  Aapcs64
} derive(Eq, Debug)

///|
pub(all) struct AbiPolicy {
  pointer_size : Int
  stack_alignment : Int
  int_argument_regs : Array[@machv.PReg]
  float_argument_regs : Array[@machv.PReg]
  int_return_regs : Array[@machv.PReg]
  float_return_regs : Array[@machv.PReg]
  caller_saved_regs : Array[@machv.PReg]
  callee_saved_regs : Array[@machv.PReg]
} derive(Debug)

///|
pub(all) struct Target {
  triple : String
  calling_convention : CallingConvention
  abi : AbiPolicy
} derive(Debug)

///|
fn int_reg(index : Int) -> @machv.PReg {
  { index, class: Int }
}

///|
fn float_reg(index : Int) -> @machv.PReg {
  { index, class: Float64 }
}

///|
fn float32_reg(index : Int) -> @machv.PReg {
  { index, class: Float32 }
}

///|
pub fn abi_policy() -> AbiPolicy {
  {
    pointer_size: 8,
    stack_alignment: 16,
    int_argument_regs: [
      int_reg(0),
      int_reg(1),
      int_reg(2),
      int_reg(3),
      int_reg(4),
      int_reg(5),
      int_reg(6),
      int_reg(7),
    ],
    float_argument_regs: [
      float_reg(0),
      float_reg(1),
      float_reg(2),
      float_reg(3),
      float_reg(4),
      float_reg(5),
      float_reg(6),
      float_reg(7),
    ],
    int_return_regs: [int_reg(0), int_reg(1)],
    float_return_regs: [float_reg(0), float_reg(1)],
    caller_saved_regs: [
      int_reg(0),
      int_reg(1),
      int_reg(2),
      int_reg(3),
      int_reg(4),
      int_reg(5),
      int_reg(6),
      int_reg(7),
      int_reg(8),
      int_reg(9),
      int_reg(10),
      int_reg(11),
      int_reg(12),
      int_reg(13),
      int_reg(14),
      int_reg(15),
      int_reg(16),
      int_reg(17),
      float_reg(0),
      float_reg(1),
      float_reg(2),
      float_reg(3),
      float_reg(4),
      float_reg(5),
      float_reg(6),
      float_reg(7),
    ],
    callee_saved_regs: [
      int_reg(19),
      int_reg(20),
      int_reg(21),
      int_reg(22),
      int_reg(23),
      int_reg(24),
      int_reg(25),
      int_reg(26),
      int_reg(27),
      int_reg(28),
      float_reg(8),
      float_reg(9),
      float_reg(10),
      float_reg(11),
      float_reg(12),
      float_reg(13),
      float_reg(14),
      float_reg(15),
    ],
  }
}

///|
pub fn target() -> Target {
  {
    triple: "aarch64-unknown-aapcs64",
    calling_convention: Aapcs64,
    abi: abi_policy(),
  }
}

///|
pub fn allocatable_regs(
  reserve_extra_results_ptr? : Bool = false,
) -> Array[@machv.PReg] {
  let env = build_machine_env(reserve_extra_results_ptr~)
  let regs : Array[@machv.PReg] = []
  for r in env.preferred_int {
    regs.push(r)
  }
  regs.push(int_reg(int_reg_index(Scratch1)))
  regs.push(int_reg(int_reg_index(Scratch2)))
  for r in env.nonpreferred_int {
    regs.push(r)
  }
  for r in env.preferred_float {
    regs.push(float32_reg(r.index))
    regs.push(r)
  }
  for r in env.nonpreferred_float {
    regs.push(float32_reg(r.index))
    regs.push(r)
  }
  for r in env.preferred_vector {
    regs.push(r)
  }
  for r in env.nonpreferred_vector {
    regs.push(r)
  }
  regs
}

///|
fn class_for_type(ty : @milkir.Type) -> @machv.RegClass {
  match ty {
    F32 => Float32
    F64 => Float64
    V128 => Vector
    I32 | I64 | Ptr | Ref | CallableRef | OpaqueRef => Int
  }
}

///|
fn align_to(value : Int, align : Int) -> Int {
  if value == 0 {
    0
  } else {
    (value + align - 1) / align * align
  }
}

///|
fn require_call_conv_layout(
  layout : @abi.CallConventionLayout?,
) -> @abi.CallConventionLayout {
  match layout {
    Some(call_conv) => call_conv
    None =>
      abort(
        "aarch64_target: call-convention lowering requires a call convention layout",
      )
  }
}

///|
fn machv_reg_class(class : @abi.RegClass) -> @machv.RegClass {
  match class {
    Int => Int
    Float32 => Float32
    Float64 => Float64
    Vector => Vector
  }
}

///|
fn machv_preg(preg : @abi.PReg) -> @machv.PReg {
  { index: preg.index, class: machv_reg_class(preg.class) }
}

///|
fn machv_pregs(regs : Array[@abi.PReg]) -> Array[@machv.PReg] {
  let result : Array[@machv.PReg] = []
  for preg in regs {
    result.push(machv_preg(preg))
  }
  result
}

///|
fn abi_stack_size_align(ty : @milkir.Type) -> (Int, Int) {
  match ty {
    V128 => (16, 16)
    _ => (8, 8)
  }
}

///|
fn abi_stack_location(
  ty : @milkir.Type,
  offset : Int,
) -> @machv.AbiValueLocation {
  let (size, align) = abi_stack_size_align(ty)
  Stack(offset~, size~, align~)
}

///|
fn abi_return_area_location(
  ty : @milkir.Type,
  offset : Int,
) -> @machv.AbiValueLocation {
  let (size, align) = abi_stack_size_align(ty)
  ReturnArea(offset~, size~, align~)
}

///|
fn abi_location_preg(location : @machv.AbiValueLocation) -> @machv.PReg? {
  match location {
    Reg(preg) => Some(preg)
    Stack(..) | ReturnArea(..) => None
  }
}

///|
fn extra_results_ptr_preg() -> @machv.PReg {
  int_reg(int_reg_index(ExtraResultsPtr))
}

///|
fn vreg_for_value(value : @milkir.Value) -> @machv.VReg {
  { id: value.id, class: class_for_type(value.ty) }
}

///|
fn reg_for_value(value : @milkir.Value) -> @machv.Reg {
  Virtual(vreg_for_value(value))
}

///|
fn regs_for_values(values : Array[@milkir.Value]) -> Array[@machv.Reg] {
  values.map(reg_for_value)
}

///|
fn add_uses(inst : @machv.Instruction, values : Array[@milkir.Value]) -> Unit {
  for value in values {
    inst.add_operand(@machv.Operand::use_reg(reg_for_value(value)))
  }
}

///|
fn add_defs(inst : @machv.Instruction, values : Array[@milkir.Value]) -> Unit {
  for value in values {
    inst.add_operand(@machv.Operand::def(reg_for_value(value)))
  }
}

///|
fn add_return_moves(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  values : Array[@milkir.Value],
  uses_call_conv_layout? : Bool = false,
) -> Unit {
  for i, value in values {
    let location = if i < out.result_locations.length() {
      out.result_locations[i]
    } else {
      Reg({ index: -1, class: class_for_type(value.ty) })
    }
    match location {
      Reg(dst) => {
        let move_inst = out.new_inst(Move)
        move_inst.add_operand(@machv.Operand::use_reg(reg_for_value(value)))
        move_inst.add_operand(@machv.Operand::def(Physical(dst)))
        block.append(move_inst)
      }
      ReturnArea(offset~, ..) => {
        uses_call_conv_layout |> ignore
        let store = out.new_inst(StorePtr(mem_type_for_type(value.ty), offset))
        store.add_operand(
          @machv.Operand::use_reg(Physical(extra_results_ptr_preg())),
        )
        store.add_operand(@machv.Operand::use_reg(reg_for_value(value)))
        block.append(store)
      }
      Stack(..) => ()
    }
  }
}

///|
fn add_call_return_area_loads(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  inst : @machv.Instruction,
  values : Array[@milkir.Value],
) -> Unit {
  for i, value in values {
    guard i < inst.abi_result_locations.length() else { continue }
    match inst.abi_result_locations[i] {
      ReturnArea(offset~, ..) => {
        let load = out.new_inst(LoadPtr(mem_type_for_type(value.ty), offset))
        load.add_operand(
          @machv.Operand::use_reg(Physical(extra_results_ptr_preg())),
        )
        load.add_operand(@machv.Operand::def(reg_for_value(value)))
        block.append(load)
      }
      Reg(_) | Stack(..) => ()
    }
  }
}

///|
fn add_call_conv_result_moves(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  inst : @machv.Instruction,
  values : Array[@milkir.Value],
) -> Unit {
  for i, value in values {
    guard i < inst.abi_result_locations.length() else { continue }
    match inst.abi_result_locations[i] {
      Reg(src) => {
        let move_inst = out.new_inst(Move)
        move_inst.add_operand(@machv.Operand::use_reg(Physical(src)))
        move_inst.add_operand(@machv.Operand::def(reg_for_value(value)))
        block.append(move_inst)
      }
      ReturnArea(offset~, ..) => {
        let load = out.new_inst(LoadPtr(mem_type_for_type(value.ty), offset))
        load.add_operand(
          @machv.Operand::use_reg(Physical(extra_results_ptr_preg())),
        )
        load.add_operand(@machv.Operand::def(reg_for_value(value)))
        block.append(load)
      }
      Stack(..) => ()
    }
  }
}

///|
fn signature_param_location(
  ty : @milkir.Type,
  int_arg_idx : Int,
  float_arg_idx : Int,
  stack_offset : Int,
  uses_call_conv_layout? : Bool = false,
  call_conv_layout? : @abi.CallConventionLayout? = None,
) -> (@machv.AbiValueLocation, Int, Int, Int) {
  let abi = abi_policy()
  let int_arg_regs = if uses_call_conv_layout {
    let call_conv = require_call_conv_layout(call_conv_layout)
    [machv_preg(call_conv.context_arg), ..machv_pregs(call_conv.user_arg_gprs)]
  } else {
    abi.int_argument_regs
  }
  let float_arg_regs = if uses_call_conv_layout {
    machv_pregs(require_call_conv_layout(call_conv_layout).arg_fprs)
  } else {
    abi.float_argument_regs
  }
  match class_for_type(ty) {
    Int =>
      if int_arg_idx < int_arg_regs.length() {
        (
          Reg(int_arg_regs[int_arg_idx]),
          int_arg_idx + 1,
          float_arg_idx,
          stack_offset,
        )
      } else {
        let (_, align) = abi_stack_size_align(ty)
        let offset = align_to(stack_offset, align)
        let location = abi_stack_location(ty, offset)
        (
          location,
          int_arg_idx + 1,
          float_arg_idx,
          offset + @machv.abi_location_stack_size(location),
        )
      }
    Float32 | Float64 | Vector =>
      if float_arg_idx < float_arg_regs.length() {
        let class = class_for_type(ty)
        (
          Reg(preg_with_class(float_arg_regs[float_arg_idx], class)),
          int_arg_idx,
          float_arg_idx + 1,
          stack_offset,
        )
      } else {
        let (_, align) = abi_stack_size_align(ty)
        let offset = align_to(stack_offset, align)
        let location = abi_stack_location(ty, offset)
        (
          location,
          int_arg_idx,
          float_arg_idx + 1,
          offset + @machv.abi_location_stack_size(location),
        )
      }
  }
}

///|
fn signature_result_location(
  ty : @milkir.Type,
  int_result_idx : Int,
  float_result_idx : Int,
  return_area_offset : Int,
  uses_call_conv_layout? : Bool = false,
  call_conv_layout? : @abi.CallConventionLayout? = None,
) -> (@machv.AbiValueLocation, Int, Int, Int) {
  let abi = abi_policy()
  let int_return_regs = if uses_call_conv_layout {
    machv_pregs(require_call_conv_layout(call_conv_layout).ret_gprs)
  } else {
    abi.int_return_regs
  }
  let float_return_regs = if uses_call_conv_layout {
    machv_pregs(require_call_conv_layout(call_conv_layout).ret_fprs)
  } else {
    abi.float_return_regs
  }
  match class_for_type(ty) {
    Int =>
      if int_result_idx < int_return_regs.length() {
        (
          Reg(int_return_regs[int_result_idx]),
          int_result_idx + 1,
          float_result_idx,
          return_area_offset,
        )
      } else {
        let (_, align) = abi_stack_size_align(ty)
        let offset = align_to(return_area_offset, align)
        let location = abi_return_area_location(ty, offset)
        (
          location,
          int_result_idx + 1,
          float_result_idx,
          offset + @machv.abi_location_stack_size(location),
        )
      }
    Float32 | Float64 | Vector =>
      if float_result_idx < float_return_regs.length() {
        let class = class_for_type(ty)
        (
          Reg(preg_with_class(float_return_regs[float_result_idx], class)),
          int_result_idx,
          float_result_idx + 1,
          return_area_offset,
        )
      } else {
        let (_, align) = abi_stack_size_align(ty)
        let offset = align_to(return_area_offset, align)
        let location = abi_return_area_location(ty, offset)
        (
          location,
          int_result_idx,
          float_result_idx + 1,
          offset + @machv.abi_location_stack_size(location),
        )
      }
  }
}

///|
fn add_function_signature(
  func : @milkir.Function,
  out : @machv.AbstractFunction,
  uses_call_conv_layout? : Bool = false,
  call_conv_layout? : @abi.CallConventionLayout? = None,
) -> Unit {
  let mut int_arg_idx = 0
  let mut float_arg_idx = 0
  let mut stack_offset = 0
  for i, ty in func.signature.params {
    let vreg : @machv.VReg = { id: i, class: class_for_type(ty) }
    out.push_param(vreg)
    let (location, next_int, next_float, next_stack_offset) = signature_param_location(
      ty,
      int_arg_idx,
      float_arg_idx,
      stack_offset,
      uses_call_conv_layout~,
      call_conv_layout~,
    )
    out.add_param_location(location)
    out.add_param_preg(abi_location_preg(location))
    int_arg_idx = next_int
    float_arg_idx = next_float
    stack_offset = next_stack_offset
  }
  if stack_offset > 0 {
    out.set_int_stack_params(stack_offset / 8)
  }
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  let mut return_area_offset = 0
  for result_ty in func.signature.results {
    out.add_result(class_for_type(result_ty))
    let (location, next_int, next_float, next_return_area_offset) = signature_result_location(
      result_ty,
      int_result_idx,
      float_result_idx,
      return_area_offset,
      uses_call_conv_layout~,
      call_conv_layout~,
    )
    out.add_result_location(location)
    int_result_idx = next_int
    float_result_idx = next_float
    return_area_offset = next_return_area_offset
  }
  if return_area_offset > 0 {
    out.set_return_area({ size: return_area_offset, align: 16 })
  }
}

///|
fn preg_with_class(preg : @machv.PReg, class : @machv.RegClass) -> @machv.PReg {
  { index: preg.index, class }
}

///|
fn add_fixed_constraint(
  inst : @machv.Instruction,
  operand_index : Int,
  preg : @machv.PReg,
) -> Unit {
  inst.add_constraint({ operand_index, allowed_regs: [preg] })
}

///|
fn add_call_abi_constraints(
  out : @machv.AbstractFunction,
  inst : @machv.Instruction,
  args : Array[@milkir.Value],
  results : Array[@milkir.Value],
) -> Unit {
  let abi = abi_policy()
  let mut int_arg_idx = 0
  let mut float_arg_idx = 0
  let mut arg_stack_offset = 0
  for operand_index, arg in args {
    match class_for_type(arg.ty) {
      Int =>
        if int_arg_idx < abi.int_argument_regs.length() {
          inst.add_abi_arg_location(Reg(abi.int_argument_regs[int_arg_idx]))
          add_fixed_constraint(
            inst,
            operand_index,
            abi.int_argument_regs[int_arg_idx],
          )
          int_arg_idx = int_arg_idx + 1
        } else {
          let (_, align) = abi_stack_size_align(arg.ty)
          arg_stack_offset = align_to(arg_stack_offset, align)
          let location = abi_stack_location(arg.ty, arg_stack_offset)
          inst.add_abi_arg_location(location)
          arg_stack_offset = arg_stack_offset +
            @machv.abi_location_stack_size(location)
          int_arg_idx = int_arg_idx + 1
        }
      Float32 | Float64 | Vector =>
        if float_arg_idx < abi.float_argument_regs.length() {
          let class = class_for_type(arg.ty)
          inst.add_abi_arg_location(
            Reg(preg_with_class(abi.float_argument_regs[float_arg_idx], class)),
          )
          add_fixed_constraint(
            inst,
            operand_index,
            preg_with_class(abi.float_argument_regs[float_arg_idx], class),
          )
          float_arg_idx = float_arg_idx + 1
        } else {
          let (_, align) = abi_stack_size_align(arg.ty)
          arg_stack_offset = align_to(arg_stack_offset, align)
          let location = abi_stack_location(arg.ty, arg_stack_offset)
          inst.add_abi_arg_location(location)
          arg_stack_offset = arg_stack_offset +
            @machv.abi_location_stack_size(location)
          float_arg_idx = float_arg_idx + 1
        }
    }
  }
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  let mut return_area_offset = 0
  for result_index, result in results {
    let operand_index = args.length() + result_index
    match class_for_type(result.ty) {
      Int =>
        if int_result_idx < abi.int_return_regs.length() {
          inst.add_abi_result_location(Reg(abi.int_return_regs[int_result_idx]))
          add_fixed_constraint(
            inst,
            operand_index,
            abi.int_return_regs[int_result_idx],
          )
          int_result_idx = int_result_idx + 1
        } else {
          let (_, align) = abi_stack_size_align(result.ty)
          return_area_offset = align_to(return_area_offset, align)
          let location = abi_return_area_location(result.ty, return_area_offset)
          inst.add_abi_result_location(location)
          return_area_offset = return_area_offset +
            @machv.abi_location_stack_size(location)
          int_result_idx = int_result_idx + 1
        }
      Float32 | Float64 | Vector =>
        if float_result_idx < abi.float_return_regs.length() {
          let class = class_for_type(result.ty)
          inst.add_abi_result_location(
            Reg(preg_with_class(abi.float_return_regs[float_result_idx], class)),
          )
          add_fixed_constraint(
            inst,
            operand_index,
            preg_with_class(abi.float_return_regs[float_result_idx], class),
          )
          float_result_idx = float_result_idx + 1
        } else {
          let (_, align) = abi_stack_size_align(result.ty)
          return_area_offset = align_to(return_area_offset, align)
          let location = abi_return_area_location(result.ty, return_area_offset)
          inst.add_abi_result_location(location)
          return_area_offset = return_area_offset +
            @machv.abi_location_stack_size(location)
          float_result_idx = float_result_idx + 1
        }
    }
  }
  let outgoing_stack_size = align_to(arg_stack_offset, 16)
  if outgoing_stack_size > 0 {
    inst.set_stack_effect(CallFrame(outgoing_stack_size))
    out.update_max_outgoing_args_size(outgoing_stack_size)
  }
  for preg in abi.caller_saved_regs {
    inst.add_clobber(preg)
  }
}

///|
fn add_callptr_abi_constraints(
  out : @machv.AbstractFunction,
  inst : @machv.Instruction,
  args : Array[@milkir.Value],
  _results : Array[@milkir.Value],
  call_conv_layout : @abi.CallConventionLayout,
) -> Unit {
  guard args.length() >= 2 else { return }
  inst.add_abi_arg_location(Reg(int_reg(int_reg_index(Scratch2))))
  add_fixed_constraint(inst, 0, int_reg(int_reg_index(Scratch2)))
  let context_arg = machv_preg(call_conv_layout.context_arg)
  inst.add_abi_arg_location(Reg(context_arg))
  add_fixed_constraint(inst, 1, context_arg)
  let user_arg_gprs = machv_pregs(call_conv_layout.user_arg_gprs)
  let user_arg_fprs = machv_pregs(call_conv_layout.arg_fprs)
  let ret_gprs = machv_pregs(call_conv_layout.ret_gprs)
  let ret_fprs = machv_pregs(call_conv_layout.ret_fprs)
  let mut int_arg_idx = 0
  let mut float_arg_idx = 0
  let mut arg_stack_offset = 0
  for arg_index in 2..<args.length() {
    let arg = args[arg_index]
    match class_for_type(arg.ty) {
      Int =>
        if int_arg_idx < user_arg_gprs.length() {
          inst.add_abi_arg_location(Reg(user_arg_gprs[int_arg_idx]))
          add_fixed_constraint(inst, arg_index, user_arg_gprs[int_arg_idx])
          int_arg_idx = int_arg_idx + 1
        } else {
          let (_, align) = abi_stack_size_align(arg.ty)
          arg_stack_offset = align_to(arg_stack_offset, align)
          let location = abi_stack_location(arg.ty, arg_stack_offset)
          inst.add_abi_arg_location(location)
          arg_stack_offset = arg_stack_offset +
            @machv.abi_location_stack_size(location)
          int_arg_idx = int_arg_idx + 1
        }
      Float32 | Float64 | Vector =>
        if float_arg_idx < user_arg_fprs.length() {
          let class = class_for_type(arg.ty)
          inst.add_abi_arg_location(
            Reg(preg_with_class(user_arg_fprs[float_arg_idx], class)),
          )
          add_fixed_constraint(
            inst,
            arg_index,
            preg_with_class(user_arg_fprs[float_arg_idx], class),
          )
          float_arg_idx = float_arg_idx + 1
        } else {
          let (_, align) = abi_stack_size_align(arg.ty)
          arg_stack_offset = align_to(arg_stack_offset, align)
          let location = abi_stack_location(arg.ty, arg_stack_offset)
          inst.add_abi_arg_location(location)
          arg_stack_offset = arg_stack_offset +
            @machv.abi_location_stack_size(location)
          float_arg_idx = float_arg_idx + 1
        }
    }
  }
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  let mut return_area_offset = 0
  for result in _results {
    match class_for_type(result.ty) {
      Int =>
        if int_result_idx < ret_gprs.length() {
          inst.add_abi_result_location(Reg(ret_gprs[int_result_idx]))
          int_result_idx = int_result_idx + 1
        } else {
          let (_, align) = abi_stack_size_align(result.ty)
          return_area_offset = align_to(return_area_offset, align)
          let location = abi_return_area_location(result.ty, return_area_offset)
          inst.add_abi_result_location(location)
          return_area_offset = return_area_offset +
            @machv.abi_location_stack_size(location)
          int_result_idx = int_result_idx + 1
        }
      Float32 | Float64 | Vector =>
        if float_result_idx < ret_fprs.length() {
          let class = class_for_type(result.ty)
          inst.add_abi_result_location(
            Reg(preg_with_class(ret_fprs[float_result_idx], class)),
          )
          float_result_idx = float_result_idx + 1
        } else {
          let (_, align) = abi_stack_size_align(result.ty)
          return_area_offset = align_to(return_area_offset, align)
          let location = abi_return_area_location(result.ty, return_area_offset)
          inst.add_abi_result_location(location)
          return_area_offset = return_area_offset +
            @machv.abi_location_stack_size(location)
          float_result_idx = float_result_idx + 1
        }
    }
  }
  let outgoing_stack_size = align_to(arg_stack_offset, 16)
  if outgoing_stack_size > 0 {
    inst.set_stack_effect(CallFrame(outgoing_stack_size))
    out.update_max_outgoing_args_size(outgoing_stack_size)
  }
  for preg in abi_policy().caller_saved_regs {
    inst.add_clobber(preg)
  }
}

///|
fn intcc_to_machv(cc : @milkir.IntCC) -> @machv.Cond {
  match cc {
    Eq => Eq
    Ne => Ne
    Slt => Lt
    Sle => Le
    Sgt => Gt
    Sge => Ge
    Ult => Ult
    Ule => Ule
    Ugt => Ugt
    Uge => Uge
  }
}

///|
fn floatcc_to_machv(cc : @milkir.FloatCC) -> @machv.Cond {
  match cc {
    Eq => Eq
    Ne => Ne
    Lt => Mi
    Le => Ule
    Gt => Gt
    Ge => Ge
  }
}

///|
fn mem_type_for_type(ty : @milkir.Type) -> @machv.MemType {
  match ty {
    I32 => MemI32
    I64 => MemI64
    F32 => MemF32
    F64 => MemF64
    V128 => MemV128
    Ptr | Ref | CallableRef | OpaqueRef => MemPtr
  }
}

///|
fn find_iconst(func : @milkir.Function, value : @milkir.Value) -> Int64? {
  for block in func.blocks {
    for inst in block.instructions {
      if inst.results.length() == 1 && inst.results[0].id == value.id {
        if inst.opcode is Iconst(offset) {
          return Some(offset)
        }
        return None
      }
    }
  }
  None
}

///|
fn const_offset_arg(
  func : @milkir.Function,
  args : Array[@milkir.Value],
  index : Int,
) -> Int {
  if index < args.length() {
    match find_iconst(func, args[index]) {
      Some(offset) => offset.to_int()
      None => 0
    }
  } else {
    0
  }
}

///|
fn opcode_for(opcode : @milkir.Opcode) -> @machv.Opcode {
  match opcode {
    Iadd => IntAdd
    Isub => IntSub
    Imul => IntMul
    IcmpEq => IntCmp(Eq)
    Icmp(cc) => IntCmp(intcc_to_machv(cc))
    Fadd => FloatAdd
    Fsub => FloatSub
    Fmul => FloatMul
    Umulh => IntMulHigh(false)
    Smulh => IntMulHigh(true)
    Sdiv => IntDiv(true)
    Udiv => IntDiv(false)
    Srem => IntRem(true)
    Urem => IntRem(false)
    Band => IntAnd
    Bor => IntOr
    Bxor => IntXor
    Bnot => IntNot
    Ishl => IntShl
    Sshr => IntShr(true)
    Ushr => IntShr(false)
    Rotl => IntRotl
    Rotr => IntRotr
    Clz => IntClz
    Ctz => IntCtz
    Popcnt => IntPopcnt
    Fdiv => FloatDiv
    Fmin => FloatMin
    Fmax => FloatMax
    Fcmp(cc) => FloatCmp(floatcc_to_machv(cc))
    Fneg => FloatNeg
    Fabs => FloatAbs
    Fsqrt => FloatSqrt
    Fceil => FloatCeil
    Ffloor => FloatFloor
    Ftrunc => FloatTrunc
    Fnearest => FloatNearest
    Ireduce => Ireduce
    Sextend => Sextend
    Uextend => Uextend
    Fpromote => Fpromote
    Fdemote => Fdemote
    FcvtToSint => FcvtToSint
    FcvtToUint => FcvtToUint
    FcvtToSintSat => FcvtToSintSat
    FcvtToUintSat => FcvtToUintSat
    SintToFcvt => SintToFcvt
    UintToFcvt => UintToFcvt
    Bitcast => Bitcast
    Sextend8 => Sextend8
    Sextend16 => Sextend16
    Sextend32 => Sextend32
    Select => Select
    Copy => Move
    Load => LoadMemory(MemI64, 0)
    Store => StoreMemory(MemI64, 0)
    LoadPtr(ty) => LoadPtr(mem_type_for_type(ty), 0)
    LoadPtrNarrow(_, bits, signed) => LoadPtrNarrow(bits, signed, 0)
    StorePtr(ty) => StorePtr(mem_type_for_type(ty), 0)
    StorePtrNarrow(bits) => StorePtrNarrow(bits, 0)
    StackAddr(slot) => StackAddr(slot.id)
    Iconst(value) => IntConst(value)
    Fconst(value) => FloatConst(value)
    Call(symbol) => Call(symbol.name)
    CallIndirect(_) => CallIndirect
    CallPtr(params, results) => CallPtr(params, results)
    Trap(reason) => Trap(default_trap_payload(reason))
    Custom(name) => Custom(name)
    _ => Custom(to_repr(opcode).to_string())
  }
}

///|
fn lower_int_rem(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  inst : @milkir.Inst,
  signed : Bool,
) -> Unit {
  // TODO(aarch64_target): lower i64 remainder to SDIV/UDIV + MSUB once MachV
  // has a structured fused multiply-subtract opcode. This correctness-first
  // expansion intentionally uses generic MachV arithmetic today.
  let quotient = out.new_vreg(Int)
  let product = out.new_vreg(Int)
  let div = out.new_inst(IntDiv(signed))
  div.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  div.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  div.add_operand(@machv.Operand::def(Virtual(quotient)))
  block.append(div)
  let mul = out.new_inst(IntMul)
  mul.add_operand(@machv.Operand::use_reg(Virtual(quotient)))
  mul.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  mul.add_operand(@machv.Operand::def(Virtual(product)))
  block.append(mul)
  let sub = out.new_inst(IntSub)
  sub.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  sub.add_operand(@machv.Operand::use_reg(Virtual(product)))
  add_defs(sub, inst.results)
  block.append(sub)
}

///|
fn append_int_const(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  value : Int64,
) -> @machv.VReg {
  let dst = out.new_vreg(Int)
  let load = out.new_inst(IntConst(value))
  load.add_operand(@machv.Operand::def(Virtual(dst)))
  block.append(load)
  dst
}

///|
fn append_int_binop(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  opcode : @machv.Opcode,
  lhs : @machv.Reg,
  rhs : @machv.Reg,
) -> @machv.VReg {
  let dst = out.new_vreg(Int)
  let op = out.new_inst(opcode)
  op.add_operand(@machv.Operand::use_reg(lhs))
  op.add_operand(@machv.Operand::use_reg(rhs))
  op.add_operand(@machv.Operand::def(Virtual(dst)))
  block.append(op)
  dst
}

///|
fn append_int_binop_result(
  block : @machv.Block,
  out : @machv.AbstractFunction,
  opcode : @machv.Opcode,
  lhs : @machv.Reg,
  rhs : @machv.Reg,
  results : Array[@milkir.Value],
) -> Unit {
  let op = out.new_inst(opcode)
  op.add_operand(@machv.Operand::use_reg(lhs))
  op.add_operand(@machv.Operand::use_reg(rhs))
  add_defs(op, results)
  block.append(op)
}

///|
fn lower_int_popcnt(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Unit {
  guard inst.args.length() == 1 && inst.results.length() == 1 else { return }
  let input : @machv.Reg = if inst.args[0].ty == I32 {
    let mask32 = append_int_const(out, block, 0xffffffffL)
    let masked = append_int_binop(
      out,
      block,
      IntAnd,
      reg_for_value(inst.args[0]),
      Virtual(mask32),
    )
    Virtual(masked)
  } else {
    reg_for_value(inst.args[0])
  }
  let one = append_int_const(out, block, 1L)
  let mask1 = append_int_const(out, block, 0x5555555555555555L)
  let half = append_int_binop(out, block, IntShr(false), input, Virtual(one))
  let half_masked = append_int_binop(
    out,
    block,
    IntAnd,
    Virtual(half),
    Virtual(mask1),
  )
  let step1 = append_int_binop(out, block, IntSub, input, Virtual(half_masked))

  let two = append_int_const(out, block, 2L)
  let mask2 = append_int_const(out, block, 0x3333333333333333L)
  let low2 = append_int_binop(
    out,
    block,
    IntAnd,
    Virtual(step1),
    Virtual(mask2),
  )
  let shifted2 = append_int_binop(
    out,
    block,
    IntShr(false),
    Virtual(step1),
    Virtual(two),
  )
  let high2 = append_int_binop(
    out,
    block,
    IntAnd,
    Virtual(shifted2),
    Virtual(mask2),
  )
  let step2 = append_int_binop(
    out,
    block,
    IntAdd,
    Virtual(low2),
    Virtual(high2),
  )

  let four = append_int_const(out, block, 4L)
  let mask4 = append_int_const(out, block, 0x0f0f0f0f0f0f0f0fL)
  let shifted4 = append_int_binop(
    out,
    block,
    IntShr(false),
    Virtual(step2),
    Virtual(four),
  )
  let sum4 = append_int_binop(
    out,
    block,
    IntAdd,
    Virtual(step2),
    Virtual(shifted4),
  )
  let step3 = append_int_binop(
    out,
    block,
    IntAnd,
    Virtual(sum4),
    Virtual(mask4),
  )

  let byte_sum = append_int_const(out, block, 0x0101010101010101L)
  let product = append_int_binop(
    out,
    block,
    IntMul,
    Virtual(step3),
    Virtual(byte_sum),
  )
  let final_shift = append_int_const(
    out,
    block,
    if inst.args[0].ty == I32 {
      24L
    } else {
      56L
    },
  )
  append_int_binop_result(
    block,
    out,
    IntShr(false),
    Virtual(product),
    Virtual(final_shift),
    inst.results,
  )
}

///|
fn lower_int_rotl(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Unit {
  // TODO(aarch64_target): make rotate-left a target combine once MachV has
  // explicit value-width metadata. AArch64 variable rotate masks the count, so
  // rotl(x, n) is encoded as rorv(x, 0 - n) for the current 64-bit path.
  let zero = out.new_vreg(Int)
  let neg_count = out.new_vreg(Int)
  let zero_const = out.new_inst(IntConst(0L))
  zero_const.add_operand(@machv.Operand::def(Virtual(zero)))
  block.append(zero_const)
  let negate = out.new_inst(IntSub)
  negate.add_operand(@machv.Operand::use_reg(Virtual(zero)))
  negate.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[1])))
  negate.add_operand(@machv.Operand::def(Virtual(neg_count)))
  block.append(negate)
  let rotr = out.new_inst(IntRotr)
  rotr.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
  rotr.add_operand(@machv.Operand::use_reg(Virtual(neg_count)))
  add_defs(rotr, inst.results)
  block.append(rotr)
}

///|
fn lower_fconst(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  inst : @milkir.Inst,
  value : Double,
) -> Unit {
  guard inst.results.length() == 1 else { return }
  let bits = match inst.results[0].ty {
    F32 => value.reinterpret_as_int64() & 0xffffffffL
    F64 => value.reinterpret_as_int64()
    _ => abort("aarch64_target: fconst result must be f32 or f64")
  }
  let raw = out.new_vreg(Int)
  let load = out.new_inst(IntConst(bits))
  load.add_operand(@machv.Operand::def(Virtual(raw)))
  block.append(load)
  let cast = out.new_inst(Bitcast)
  cast.add_operand(@machv.Operand::use_reg(Virtual(raw)))
  add_defs(cast, inst.results)
  block.append(cast)
}

///|
fn lower_float_select(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  inst : @milkir.Inst,
) -> Bool {
  guard inst.args.length() == 3 && inst.results.length() == 1 else {
    return false
  }
  match inst.results[0].ty {
    F32 | F64 => {
      let true_bits = out.new_vreg(Int)
      let false_bits = out.new_vreg(Int)
      let selected_bits = out.new_vreg(Int)
      let true_cast = out.new_inst(Bitcast)
      true_cast.add_operand(
        @machv.Operand::use_reg(reg_for_value(inst.args[1])),
      )
      true_cast.add_operand(@machv.Operand::def(Virtual(true_bits)))
      block.append(true_cast)
      let false_cast = out.new_inst(Bitcast)
      false_cast.add_operand(
        @machv.Operand::use_reg(reg_for_value(inst.args[2])),
      )
      false_cast.add_operand(@machv.Operand::def(Virtual(false_bits)))
      block.append(false_cast)
      let select = out.new_inst(Select)
      select.add_operand(@machv.Operand::use_reg(reg_for_value(inst.args[0])))
      select.add_operand(@machv.Operand::use_reg(Virtual(true_bits)))
      select.add_operand(@machv.Operand::use_reg(Virtual(false_bits)))
      select.add_operand(@machv.Operand::def(Virtual(selected_bits)))
      block.append(select)
      let result_cast = out.new_inst(Bitcast)
      result_cast.add_operand(@machv.Operand::use_reg(Virtual(selected_bits)))
      add_defs(result_cast, inst.results)
      block.append(result_cast)
      true
    }
    _ => false
  }
}

///|
fn load_mem_type(inst : @milkir.Inst) -> @machv.MemType {
  guard inst.results.length() == 1 else { return MemI64 }
  mem_type_for_type(inst.results[0].ty)
}

///|
fn store_mem_type(inst : @milkir.Inst) -> @machv.MemType {
  guard inst.args.length() >= 2 else { return MemI64 }
  mem_type_for_type(inst.args[1].ty)
}

///|
fn lower_inst(
  func : @milkir.Function,
  out : @machv.AbstractFunction,
  block : @machv.Block,
  inst : @milkir.Inst,
  call_conv_layout? : @abi.CallConventionLayout? = None,
) -> Unit {
  match inst.opcode {
    Srem => {
      lower_int_rem(out, block, inst, true)
      return
    }
    Urem => {
      lower_int_rem(out, block, inst, false)
      return
    }
    Popcnt => {
      lower_int_popcnt(out, block, inst)
      return
    }
    Rotl => {
      lower_int_rotl(out, block, inst)
      return
    }
    Fconst(value) => {
      lower_fconst(out, block, inst, value)
      return
    }
    Select => if lower_float_select(out, block, inst) { return }
    CallPtr(_, _) => {
      let call_conv = require_call_conv_layout(call_conv_layout)
      let lowered = out.new_inst(opcode_for(inst.opcode))
      add_uses(lowered, inst.args)
      add_callptr_abi_constraints(
        out,
        lowered,
        inst.args,
        inst.results,
        call_conv,
      )
      block.append(lowered)
      add_call_conv_result_moves(out, block, lowered, inst.results)
      return
    }
    _ => ()
  }
  let lowered = match inst.opcode {
    LoadPtr(ty) => {
      let offset = const_offset_arg(func, inst.args, 1)
      out.new_inst(LoadPtr(mem_type_for_type(ty), offset))
    }
    LoadPtrNarrow(_, bits, signed) => {
      let offset = const_offset_arg(func, inst.args, 1)
      out.new_inst(LoadPtrNarrow(bits, signed, offset))
    }
    StorePtr(ty) => {
      let offset = const_offset_arg(func, inst.args, 2)
      out.new_inst(StorePtr(mem_type_for_type(ty), offset))
    }
    StorePtrNarrow(bits) => {
      let offset = const_offset_arg(func, inst.args, 2)
      out.new_inst(StorePtrNarrow(bits, offset))
    }
    Load => out.new_inst(LoadMemory(load_mem_type(inst), 0))
    Store => out.new_inst(StoreMemory(store_mem_type(inst), 0))
    _ => out.new_inst(opcode_for(inst.opcode))
  }
  match inst.opcode {
    LoadPtr(_) | LoadPtrNarrow(_, _, _) => {
      if inst.args.length() > 0 {
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[0])),
        )
      }
      if inst.args.length() > 1 && find_iconst(func, inst.args[1]) is None {
        // TODO(aarch64_target): lower non-constant pointer offsets to extended
        // register-offset addressing instead of keeping the offset as a generic use.
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[1])),
        )
      }
      add_defs(lowered, inst.results)
    }
    StorePtr(_) | StorePtrNarrow(_) => {
      if inst.args.length() > 0 {
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[0])),
        )
      }
      if inst.args.length() > 1 {
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[1])),
        )
      }
      if inst.args.length() > 2 && find_iconst(func, inst.args[2]) is None {
        // TODO(aarch64_target): lower non-constant pointer offsets to extended
        // register-offset addressing instead of keeping the offset as a generic use.
        lowered.add_operand(
          @machv.Operand::use_reg(reg_for_value(inst.args[2])),
        )
      }
      add_defs(lowered, inst.results)
    }
    _ => {
      add_uses(lowered, inst.args)
      add_defs(lowered, inst.results)
      if inst.opcode is Call(_) {
        add_call_abi_constraints(out, lowered, inst.args, inst.results)
      } else if inst.opcode is CallPtr(_, _) {
        add_callptr_abi_constraints(
          out,
          lowered,
          inst.args,
          inst.results,
          require_call_conv_layout(call_conv_layout),
        )
      } else if inst.opcode is CallIndirect(_) {
        // TODO(aarch64_target): lower generic indirect calls once MilkIR carries
        // target-independent callee/table ABI metadata.
      }
    }
  }
  // TODO(aarch64_target): expand selected AArch64 machine operations, target
  // constraints, and legalization for non-trivial memory ops.
  block.append(lowered)
  if inst.opcode is Call(_) {
    add_call_return_area_loads(out, block, lowered, inst.results)
  }
}

///|
fn lower_terminator(
  out : @machv.AbstractFunction,
  block : @machv.Block,
  terminator : @milkir.Terminator,
  block_map : Array[(Int, Int)],
  uses_call_conv_layout? : Bool = false,
) -> Unit {
  match terminator {
    Return(values) => {
      add_return_moves(out, block, values, uses_call_conv_layout~)
      block.set_terminator(TermReturn([]))
    }
    Jump(target, values) =>
      block.set_terminator(
        TermJump(map_block_id(block_map, target), regs_for_values(values)),
      )
    Branch(cond, true_target, true_args, false_target, false_args) =>
      block.set_terminator(
        TermBranch(
          reg_for_value(cond),
          map_block_id(block_map, true_target),
          regs_for_values(true_args),
          map_block_id(block_map, false_target),
          regs_for_values(false_args),
        ),
      )
    TrapExit(reason) =>
      block.set_terminator(TermTrap(default_trap_payload(reason)))
    Brz(cond, true_target, false_target) =>
      block.set_terminator(
        TermBranchZero(
          reg_for_value(cond),
          false,
          true,
          map_block_id(block_map, true_target),
          [],
          map_block_id(block_map, false_target),
          [],
        ),
      )
    Brnz(cond, true_target, false_target) =>
      block.set_terminator(
        TermBranchZero(
          reg_for_value(cond),
          true,
          true,
          map_block_id(block_map, true_target),
          [],
          map_block_id(block_map, false_target),
          [],
        ),
      )
    BrTable(index, targets, default_target) =>
      block.set_terminator(
        TermBrTable(
          reg_for_value(index),
          targets.map(fn(target) { map_block_id(block_map, target) }),
          map_block_id(block_map, default_target),
        ),
      )
    Trap(reason) => block.set_terminator(TermTrap(default_trap_payload(reason)))
  }
}

///|
fn default_trap_payload(_reason : String) -> Int {
  0
}

///|
fn map_block_id(block_map : Array[(Int, Int)], old_id : Int) -> Int {
  for entry in block_map {
    let (from, to) = entry
    if from == old_id {
      return to
    }
  }
  abort("aarch64_target: unknown MilkIR block target \{old_id}")
}

///|
fn lower_function_with_abi(
  func : @milkir.Function,
  uses_call_conv_layout : Bool,
  call_conv_layout? : @abi.CallConventionLayout? = None,
) -> @machv.AbstractFunction {
  let out = @machv.AbstractFunction::new(func.name)
  out.next_vreg_id = func.next_value_id
  add_function_signature(func, out, uses_call_conv_layout~, call_conv_layout~)
  for slot in func.stack_slots {
    out.new_stack_slot(slot.size, slot.align) |> ignore
  }
  let block_map : Array[(Int, Int)] = []
  for milk_block in func.blocks {
    let block = out.new_block()
    block_map.push((milk_block.id, block.id))
    for item in milk_block.params {
      let (param, _) = item
      block.add_param(vreg_for_value(param))
    }
  }
  for i, milk_block in func.blocks {
    let block = out.blocks[i]
    for inst in milk_block.instructions {
      lower_inst(func, out, block, inst, call_conv_layout~)
    }
    if milk_block.terminator is Some(terminator) {
      lower_terminator(
        out,
        block,
        terminator,
        block_map,
        uses_call_conv_layout~,
      )
    }
  }
  out
}

///|
pub fn lower_function(func : @milkir.Function) -> @machv.AbstractFunction {
  lower_function_with_abi(func, false)
}

///|
pub fn lower_function_with_call_conv(
  func : @milkir.Function,
  call_conv_layout : @abi.CallConventionLayout,
) -> @machv.AbstractFunction {
  lower_function_with_abi(func, true, call_conv_layout=Some(call_conv_layout))
}
