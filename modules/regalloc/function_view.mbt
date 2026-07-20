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
  fn entry_values(Self) -> Array[VirtualReg]
  fn block_count(Self) -> Int
  fn block_id_at(Self, Int) -> Int
  fn block_parameters(Self, Int) -> Array[VirtualReg]
  fn block_instructions(Self, Int) -> Array[Int]
  fn block_successors(Self, Int) -> Array[Int]
  fn edge_arguments(Self, Int, Int) -> Array[VirtualReg]
  fn instruction_operands(Self, Int) -> Array[Operand]
  fn instruction_clobbers(Self, Int) -> Array[PhysicalReg]
}

///|
/// Physical-register policy supplied by the embedding target.
pub struct MachineEnv {
  allocatable_regs : Array[PhysicalReg]
  scratch_regs : Array[PhysicalReg]
}

///|
pub fn MachineEnv::new(
  allocatable_regs : Array[PhysicalReg],
  scratch_regs : Array[PhysicalReg],
) -> MachineEnv {
  {
    allocatable_regs: allocatable_regs.copy(),
    scratch_regs: scratch_regs.copy(),
  }
}

///|
pub fn MachineEnv::allocatable_regs(self : MachineEnv) -> Array[PhysicalReg] {
  self.allocatable_regs.copy()
}

///|
pub fn MachineEnv::scratch_regs(self : MachineEnv) -> Array[PhysicalReg] {
  self.scratch_regs.copy()
}
