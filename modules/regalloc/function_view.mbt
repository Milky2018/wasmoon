///|
/// Read-only machine-function input consumed by register allocation.
///
/// Values and instructions have stable dense ids. Blocks passed to CFG methods
/// are dense layout indices; `block_id_at` maps them to the embedding's stable
/// block id for diagnostics and edge edits. The allocator may retain derived
/// liveness data, but does not retain the view.
pub(open) trait FunctionView {
  fn value_count(Self) -> Int
  fn value_class(Self, Int) -> RegClass
  fn value_spill_size(Self, Int) -> Int
  fn value_spill_alignment(Self, Int) -> Int
  fn values_share_spill_slot(Self, Int, Int) -> Bool
  fn entry_values(Self) -> ArrayView[VirtualReg]
  fn block_count(Self) -> Int
  fn block_id_at(Self, Int) -> Int
  fn block_parameters(Self, Int) -> ArrayView[VirtualReg]
  fn block_instructions(Self, Int) -> ArrayView[Int]
  fn block_successors(Self, Int) -> ArrayView[Int]
  fn edge_arguments(Self, Int, Int) -> ArrayView[VirtualReg]
  fn instruction_operands(Self, Int) -> ArrayView[Operand]
  fn instruction_clobbers(Self, Int) -> ArrayView[PhysicalReg]
}

///|
/// Physical-register policy supplied by the embedding target.
///
/// `scratch_regs` resolve allocator-inserted edits. The operand scratch subset
/// may additionally hold unconstrained instruction operands; targets may
/// restrict that subset when their emitter reserves scratch registers for local
/// expansion. Fixed-operand registers are reserved from both scratch roles and become
/// legal only when an instruction explicitly names one with `FixedReg`.
pub struct MachineEnv {
  allocatable_regs : Array[PhysicalReg]
  scratch_regs : Array[PhysicalReg]
  operand_scratch_regs : Array[PhysicalReg]
  fixed_operand_regs : Array[PhysicalReg]
}

///|
pub fn MachineEnv::new(
  allocatable_regs : Array[PhysicalReg],
  scratch_regs : Array[PhysicalReg],
) -> MachineEnv {
  {
    allocatable_regs: allocatable_regs.copy(),
    scratch_regs: scratch_regs.copy(),
    operand_scratch_regs: scratch_regs.copy(),
    fixed_operand_regs: [],
  }
}

///|
/// Select the reserved scratch registers that may hold instruction operands.
/// Edit resolution continues to use the full scratch-register set.
pub fn MachineEnv::with_operand_scratch_regs(
  self : MachineEnv,
  operand_scratch_regs : Array[PhysicalReg],
) -> MachineEnv {
  { ..self, operand_scratch_regs: operand_scratch_regs.copy(), }
}

///|
/// Declare reserved registers that may be used only by matching `FixedReg`
/// instruction operands.
///
/// These registers are not value homes or allocator-chosen scratches. A fixed
/// operand may still require an explicit edit that moves its value into the
/// named register at the instruction boundary.
pub fn MachineEnv::with_fixed_operand_regs(
  self : MachineEnv,
  fixed_operand_regs : Array[PhysicalReg],
) -> MachineEnv {
  { ..self, fixed_operand_regs: fixed_operand_regs.copy(), }
}

///|
pub fn MachineEnv::allocatable_regs(self : MachineEnv) -> Array[PhysicalReg] {
  self.allocatable_regs.copy()
}

///|
pub fn MachineEnv::scratch_regs(self : MachineEnv) -> Array[PhysicalReg] {
  self.scratch_regs.copy()
}

///|
pub fn MachineEnv::operand_scratch_regs(
  self : MachineEnv,
) -> Array[PhysicalReg] {
  self.operand_scratch_regs.copy()
}

///|
pub fn MachineEnv::fixed_operand_regs(self : MachineEnv) -> Array[PhysicalReg] {
  self.fixed_operand_regs.copy()
}
