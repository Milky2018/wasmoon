///|
priv struct RegisterClobberPoints {
  points : Array[ProgramPoint]
  keys : Array[Int64]
}

///|
priv struct RegisterClobberIndex {
  by_register : Array[RegisterClobberPoints]
}

///|
#valtype
priv struct OptionalProgramPoint {
  present : Bool
  point : ProgramPoint
}

///|
fn no_program_point() -> OptionalProgramPoint {
  { present: false, point: ProgramPoint(-1, -1), }
}

///|
fn some_program_point(point : ProgramPoint) -> OptionalProgramPoint {
  { present: true, point, }
}

///|
priv struct PhysicalRegisterIndex {
  stride : Int
  indexes : Array[Int]
}

///|
fn physical_register_class_index(class : RegClass) -> Int {
  match class {
    Int => 0
    Float => 1
    Vector => 2
  }
}

///|
fn PhysicalRegisterIndex::for_session(
  session : AllocationSession,
  registers : Array[PhysicalReg],
) -> PhysicalRegisterIndex {
  let mut max_id = -1
  for register in registers {
    max_id = max_id.max(register.id)
  }
  // Real ISAs use compact register ids. Keep malformed or unconventional
  // embeddings from turning an external id into an unbounded allocation.
  let stride = if max_id >= 0 && max_id <= 255 { max_id + 1 } else { 0 }
  reset_dense_array(session.physical_register_indexes, stride * 3, -1)
  let index : PhysicalRegisterIndex = {
    stride,
    indexes: session.physical_register_indexes,
  }
  if stride > 0 {
    for register_index, register in registers {
      if register.id >= 0 {
        index.indexes[physical_register_class_index(register.class) * stride +
        register.id] = register_index
      }
    }
  }
  index
}

///|
fn PhysicalRegisterIndex::find(
  self : PhysicalRegisterIndex,
  registers : Array[PhysicalReg],
  register : PhysicalReg,
) -> Int? {
  if self.stride > 0 && register.id >= 0 && register.id < self.stride {
    let index = self.indexes[physical_register_class_index(register.class) *
      self.stride +
      register.id]
    if index >= 0 {
      return Some(index)
    }
    return None
  }
  register_index(registers, register)
}

///|
fn RegisterClobberIndex::new(register_count : Int) -> RegisterClobberIndex {
  let by_register : Array[RegisterClobberPoints] = []
  for _ in 0..<register_count {
    by_register.push({ points: [], keys: [], })
  }
  { by_register, }
}

///|
fn RegisterClobberIndex::reset(
  self : RegisterClobberIndex,
  register_count : Int,
) -> Unit {
  while self.by_register.length() < register_count {
    self.by_register.push({ points: [], keys: [], })
  }
  for register in self.by_register {
    register.points.clear()
    register.keys.clear()
  }
}

///|
fn[F : FunctionView] build_register_clobber_index(
  function : F,
  environment : MachineEnv,
  block_order : Array[Int],
  register_indexes : PhysicalRegisterIndex,
  index? : RegisterClobberIndex = RegisterClobberIndex::new(0),
) -> RegisterClobberIndex {
  index.reset(environment.allocatable_regs.length())
  fn record(
    index : RegisterClobberIndex,
    register_indexes : PhysicalRegisterIndex,
    registers : Array[PhysicalReg],
    reg : PhysicalReg,
    point : ProgramPoint,
  ) -> Unit {
    if register_indexes.find(registers, reg) is Some(register) {
      index.by_register[register].points.push(point)
    }
  }
  for block in 0..<function.block_count() {
    for instruction_index, instruction in function.block_instructions(block) {
      // A clobber happens after Early operands and before Late operands. Place
      // it at the Early boundary: ranges ending in an Early use may occupy the
      // register, Late definitions start after it, and live-through ranges
      // cross it. Recording the clobber at the Late point made a split spill
      // gap end exactly on an open intersection boundary and allowed the gap
      // to be recolored into the clobbered register.
      let point = ProgramPoint(block, instruction_index * 2)
      for clobber in function.instruction_clobbers(instruction) {
        record(
          index,
          register_indexes,
          environment.allocatable_regs,
          clobber,
          point,
        )
      }
      for operand in function.instruction_operands(instruction) {
        if operand.timing is Early && operand.constraint is FixedReg(reg) {
          record(
            index,
            register_indexes,
            environment.allocatable_regs,
            reg,
            operand_program_point(block, instruction_index, operand.timing),
          )
        }
      }
      for operand in function.instruction_operands(instruction) {
        if operand.timing is Late && operand.constraint is FixedReg(reg) {
          record(
            index,
            register_indexes,
            environment.allocatable_regs,
            reg,
            operand_program_point(block, instruction_index, operand.timing),
          )
        }
      }
    }
  }
  let mut block_order_is_monotonic = true
  for block in 1..<function.block_count() {
    if program_point_block_order(ProgramPoint(block - 1, 0), block_order) >
      program_point_block_order(ProgramPoint(block, 0), block_order) {
      block_order_is_monotonic = false
      break
    }
  }
  for clobbers in index.by_register {
    if !block_order_is_monotonic {
      clobbers.points.sort_by(fn(left, right) {
        left.compare_with_order(right, block_order)
      })
    }
    for point in clobbers.points {
      clobbers.keys.push(ordered_program_point_key(point, block_order))
    }
  }
  index
}

///|
fn RegisterClobberIndex::first_intersection(
  self : RegisterClobberIndex,
  register : Int,
  segment_ids : Array[Int],
  segments : RegisterAllocationIndex,
) -> OptionalProgramPoint {
  guard !segment_ids.is_empty() else { return no_program_point() }
  let clobbers = self.by_register[register]
  let mut lo = 0
  let mut hi = clobbers.points.length()
  let first_segment = segment_ids[0]
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if clobbers.keys[mid] < segments.starts[first_segment] {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  let mut segment_index = 0
  while lo < clobbers.points.length() && segment_index < segment_ids.length() {
    let segment = segment_ids[segment_index]
    if clobbers.keys[lo] < segments.starts[segment] {
      lo = lo + 1
    } else if clobbers.keys[lo] < segments.ends[segment] {
      return some_program_point(clobbers.points[lo])
    } else {
      segment_index = segment_index + 1
    }
  }
  no_program_point()
}

///|
fn find_scratch_reg(
  environment : MachineEnv,
  class : RegClass,
  used : Array[PhysicalReg],
) -> PhysicalReg? {
  for reg in environment.operand_scratch_regs {
    if reg.class == class && !used.contains(reg) {
      return Some(reg)
    }
  }
  None
}

///|
fn add_use_transfer(
  plan : AllocationPlan,
  instruction : Int,
  operand : Operand,
  home : Location,
  selected : Location,
) -> Unit {
  if home == selected {
    return
  }
  plan.add_edit({
    value: operand.vreg,
    from: home,
    to: selected,
    position: Before(instruction),
  })
}

///|
/// Values keep one home for their complete live range, so live-through CFG
/// edges need no transfer. Only SSA block arguments can change value identity
/// and therefore location at an edge.
fn[F : FunctionView] assign_edge_transfers(
  plan : AllocationPlan,
  function : F,
) -> Unit raise VerifyError {
  for block_index in 0..<function.block_count() {
    let successors = function.block_successors(block_index)
    for successor_index, target in successors {
      let arguments = function.edge_arguments(block_index, successor_index)
      let parameters = function.block_parameters(target)
      for argument_index, argument in arguments {
        if argument_index >= parameters.length() {
          break
        }
        let parameter = parameters[argument_index]
        guard plan.value_location(argument.id) is Some(from) else {
          raise Unassigned(vreg=argument)
        }
        guard plan.value_location(parameter.id) is Some(to) else {
          raise Unassigned(vreg=parameter)
        }
        if from != to {
          plan.add_edit({
            value: argument,
            from,
            to,
            position: Edge(
              source_block=function.block_id_at(block_index),
              successor_index~,
            ),
          })
        }
      }
    }
  }
}

///|
fn[F : FunctionView] verify_operand_preferences(
  function : F,
  environment : MachineEnv,
) -> Unit raise VerifyError {
  for block in 0..<function.block_count() {
    for instruction in function.block_instructions(block) {
      for operand in function.instruction_operands(instruction) {
        if operand.preference is Some(preferred) &&
          (
            preferred.class != operand.vreg.class ||
            !environment.allocatable_regs.contains(preferred)
          ) {
          raise InvalidPreference(vreg=operand.vreg, preferred~)
        }
      }
    }
  }
}

///|
/// The phases proper: everything from the first `enter_phase` onwards.
///
/// Split out so the terminating event can be attached to every way this
/// returns. A single body cannot express that — MoonBit has no `finally`,
/// and a `raise` runs straight past a trailing call.
fn[F : FunctionView] run_allocation_phases(
  function : F,
  environment : MachineEnv,
  session : AllocationSession,
  config : RegallocConfig,
) -> AllocationPlan raise VerifyError {
  let plan = allocate_bundle_plan(function, environment, session, config)
  config.enter_phase(Some(EditResolution))
  resolve_instruction_edits(plan, environment)
  if config.verify() {
    config.enter_phase(Some(Verification))
    verify_function_allocation(function, environment, plan)
  }
  plan
}

///|
/// Allocate directly from a read-only machine-function view.
///
/// The observer sees `Some(phase)` as each phase begins and exactly one
/// `None` once the last one ends, *including when allocation fails*. A raise
/// used to skip that `None`, leaving whoever was measuring with a phase that
/// never ended — `Verification` most often, since verifying the finished
/// plan is both the likeliest raise and the last phase to open.
pub fn[F : FunctionView] allocate_function(
  function : F,
  environment : MachineEnv,
  config? : RegallocConfig = RegallocConfig(),
) -> AllocationPlan raise VerifyError {
  AllocationSession::new().allocate_function(function, environment, config~)
}

///|
/// Allocate one function while retaining scratch capacity for the next serial
/// call on this session.
pub fn[F : FunctionView] AllocationSession::allocate_function(
  self : AllocationSession,
  function : F,
  environment : MachineEnv,
  config? : RegallocConfig = RegallocConfig(),
) -> AllocationPlan raise VerifyError {
  let plan = {
    errdefer config.enter_phase(None)
    config.enter_phase(Some(InputValidation))
    verify_operand_preferences(function, environment)
    run_allocation_phases(function, environment, self, config)
  }
  config.enter_phase(None)
  plan
}
