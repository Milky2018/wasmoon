///|
pub struct StackSlot {
  priv owner : Ref[Unit]
  priv id : Int
}

///|
fn StackSlot::new(owner : Ref[Unit], id : Int) -> StackSlot {
  { owner, id, }
}

///|
pub impl Eq for StackSlot with fn equal(self, other) {
  physical_equal(self.owner, other.owner) && self.id == other.id
}

///|
pub impl Debug for StackSlot with fn to_repr(self) {
  Repr::literal("stack\{self.id}")
}

///|
priv struct StackSlotData {
  ty : ValueType
  size : Int
  alignment : Int
}

///|
pub(all) enum Location {
  Register(PhysicalReg)
  Stack(StackSlot)
} derive(Eq)

///|
pub impl Debug for Location with fn to_repr(self) {
  match self {
    Register(reg) => Repr(reg)
    Stack(slot) => Repr(slot)
  }
}

///|
pub(all) enum EditKind {
  Spill(value~ : Value, reg~ : PhysicalReg, slot~ : StackSlot)
  Reload(value~ : Value, slot~ : StackSlot, reg~ : PhysicalReg)
  Move(value~ : Value, from~ : PhysicalReg, to~ : PhysicalReg)
  EdgeMove(
    source~ : Block,
    successor_index~ : Int,
    value~ : Value,
    from~ : Location,
    to~ : Location
  )
} derive(Eq, Debug)

///|
/// Read-only summary of the transfers introduced by register allocation.
pub struct AllocationStatistics {
  spill_slots : Int
  spills : Int
  reloads : Int
  reg_moves : Int
  spill_to_spill : Int
} derive(Eq, Debug)

///|
pub struct Edit {
  point : ProgramPoint?
  kind : EditKind
}

///|
pub fn Edit::point(self : Edit) -> ProgramPoint? {
  self.point
}

///|
pub fn Edit::kind(self : Edit) -> EditKind {
  self.kind
}

///|
pub fn Edit::spill(
  point : ProgramPoint,
  value : Value,
  reg : PhysicalReg,
  slot : StackSlot,
) -> Edit {
  { point: Some(point), kind: Spill(value~, reg~, slot~), }
}

///|
pub fn Edit::reload(
  point : ProgramPoint,
  value : Value,
  slot : StackSlot,
  reg : PhysicalReg,
) -> Edit {
  { point: Some(point), kind: Reload(value~, slot~, reg~), }
}

///|
pub fn Edit::register_move(
  point : ProgramPoint,
  value : Value,
  from : PhysicalReg,
  to : PhysicalReg,
) -> Edit {
  { point: Some(point), kind: Move(value~, from~, to~), }
}

///|
pub fn Edit::edge_move(
  source : Block,
  successor_index : Int,
  value : Value,
  from : Location,
  to : Location,
) -> Edit {
  {
    point: None,
    kind: EdgeMove(source~, successor_index~, value~, from~, to~),
  }
}

///|
priv struct SafepointRootLocation {
  instruction : Instruction
  value : Value
  location : Location
}

///|
pub struct Allocation {
  priv source_owner : Ref[Unit]
  priv owner : Ref[Unit]
  priv function_name : String
  priv source_value_count : Int
  priv source_block_count : Int
  priv source_instruction_count : Int
  priv value_types : Array[ValueType]
  priv operand_counts : Array[Int]
  priv operand_values : Array[Array[Value]]
  priv value_locations : Array[Location?]
  priv operand_locations : Array[Array[Location?]]
  priv stack_slots : Array[StackSlotData]
  priv edits : Array[Edit]
  priv before_edits : Array[Array[Edit]]
  priv after_edits : Array[Array[Edit]]
  priv edge_edits : Map[(Int, Int), Array[Edit]]
  priv safepoint_roots : Array[SafepointRootLocation]
}

///|
pub fn[Inst] Allocation::for_function(function : Function[Inst]) -> Allocation {
  let operand_counts : Array[Int] = []
  let operand_values : Array[Array[Value]] = []
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    let count = function.instruction_operand_count(instruction)
    operand_counts.push(count)
    operand_values.push(
      Array::makei(count, operand_index => {
        function.instruction_operand_at(instruction, operand_index).unwrap().value
      }),
    )
  }
  let value_types = Array::makei(function.value_count(), index => {
    function.value_type(function.value_at(index).unwrap()).unwrap()
  })
  {
    source_owner: function.owner,
    owner: Ref(()),
    function_name: function.name(),
    source_value_count: function.value_count(),
    source_block_count: function.block_count(),
    source_instruction_count: function.instruction_count(),
    value_types,
    operand_counts,
    operand_values,
    value_locations: Array::make(function.value_count(), None),
    operand_locations: operand_counts.map(count => Array::make(count, None)),
    stack_slots: [],
    edits: [],
    before_edits: Array::makei(function.instruction_count(), _ => []),
    after_edits: Array::makei(function.instruction_count(), _ => []),
    edge_edits: Map([]),
    safepoint_roots: [],
  }
}

///|
fn Allocation::owns_value(self : Allocation, value : Value) -> Bool {
  physical_equal(self.source_owner, value.owner) &&
  value.id >= 0 &&
  value.id < self.source_value_count
}

///|
fn Allocation::owns_instruction(
  self : Allocation,
  instruction : Instruction,
) -> Bool {
  physical_equal(self.source_owner, instruction.owner) &&
  instruction.id >= 0 &&
  instruction.id < self.source_instruction_count
}

///|
fn Allocation::owns_block(self : Allocation, block : Block) -> Bool {
  physical_equal(self.source_owner, block.owner) &&
  block.id >= 0 &&
  block.id < self.source_block_count
}

///|
fn Allocation::owns_slot(self : Allocation, slot : StackSlot) -> Bool {
  physical_equal(self.owner, slot.owner) &&
  slot.id >= 0 &&
  slot.id < self.stack_slots.length()
}

///|
pub fn Allocation::source_instruction_count(self : Allocation) -> Int {
  self.source_instruction_count
}

///|
pub fn Allocation::create_stack_slot(
  self : Allocation,
  ty : ValueType,
  size : Int,
  alignment : Int,
) -> StackSlot {
  let slot = StackSlot::new(self.owner, self.stack_slots.length())
  self.stack_slots.push({ ty, size, alignment, })
  slot
}

///|
pub fn Allocation::stack_slot_count(self : Allocation) -> Int {
  self.stack_slots.length()
}

///|
pub fn Allocation::stack_slot_at(self : Allocation, index : Int) -> StackSlot? {
  if index >= 0 && index < self.stack_slots.length() {
    Some(StackSlot::new(self.owner, index))
  } else {
    None
  }
}

///|
pub fn Allocation::stack_slot_type(
  self : Allocation,
  slot : StackSlot,
) -> ValueType? {
  if self.owns_slot(slot) {
    Some(self.stack_slots[slot.id].ty)
  } else {
    None
  }
}

///|
pub fn Allocation::stack_slot_size(self : Allocation, slot : StackSlot) -> Int? {
  if self.owns_slot(slot) {
    Some(self.stack_slots[slot.id].size)
  } else {
    None
  }
}

///|
pub fn Allocation::stack_slot_alignment(
  self : Allocation,
  slot : StackSlot,
) -> Int? {
  if self.owns_slot(slot) {
    Some(self.stack_slots[slot.id].alignment)
  } else {
    None
  }
}

///|
pub fn Allocation::assign_value(
  self : Allocation,
  value : Value,
  location : Location,
) -> Bool {
  if !self.owns_value(value) ||
    !self.location_matches(location, self.value_types[value.id]) {
    return false
  }
  self.value_locations[value.id] = Some(location)
  true
}

///|
/// Return the value's default transfer home.
///
/// A verified segmented allocation may keep the newest value in an
/// instruction- or edge-specific location until an edit returns it here.
pub fn Allocation::value_location(
  self : Allocation,
  value : Value,
) -> Location? {
  if self.owns_value(value) {
    self.value_locations[value.id]
  } else {
    None
  }
}

///|
pub fn Allocation::assign_operand_location(
  self : Allocation,
  instruction : Instruction,
  operand_index : Int,
  location : Location,
) -> Bool {
  if !self.owns_instruction(instruction) ||
    operand_index < 0 ||
    operand_index >= self.operand_counts[instruction.id] {
    return false
  }
  let value = self.operand_values[instruction.id][operand_index]
  if !self.location_matches(location, self.value_types[value.id]) {
    return false
  }
  self.operand_locations[instruction.id][operand_index] = Some(location)
  true
}

///|
pub fn Allocation::assign_operand(
  self : Allocation,
  instruction : Instruction,
  operand_index : Int,
  reg : PhysicalReg,
) -> Bool {
  self.assign_operand_location(instruction, operand_index, Register(reg))
}

///|
pub fn Allocation::operand_location(
  self : Allocation,
  instruction : Instruction,
  operand_index : Int,
) -> Location? {
  if !self.owns_instruction(instruction) ||
    operand_index < 0 ||
    operand_index >= self.operand_counts[instruction.id] {
    return None
  }
  self.operand_locations[instruction.id][operand_index]
}

///|
pub fn Allocation::add_edit(self : Allocation, edit : Edit) -> Bool {
  let valid = match edit.kind {
    Spill(value~, reg~, slot~) | Reload(value~, slot~, reg~) =>
      self.owns_value(value) &&
      self.owns_slot(slot) &&
      reg_class_for_value_type(self.value_types[value.id]) == reg.class &&
      self.stack_slots[slot.id].ty == self.value_types[value.id] &&
      edit.point is Some(point) &&
      physical_equal(point.owner, self.source_owner) &&
      self.owns_instruction(point.instruction)
    Move(value~, from~, to~) =>
      self.owns_value(value) &&
      from.class == reg_class_for_value_type(self.value_types[value.id]) &&
      to.class == from.class &&
      edit.point is Some(point) &&
      physical_equal(point.owner, self.source_owner) &&
      self.owns_instruction(point.instruction)
    EdgeMove(source~, successor_index~, value~, from~, to~) =>
      physical_equal(source.owner, self.source_owner) &&
      source.id >= 0 &&
      source.id < self.source_block_count &&
      successor_index >= 0 &&
      self.owns_value(value) &&
      self.location_matches(from, self.value_types[value.id]) &&
      self.location_matches(to, self.value_types[value.id])
  }
  if !valid {
    return false
  }
  self.edits.push(edit)
  match edit.kind {
    EdgeMove(source~, successor_index~, ..) => {
      let key = (source.id, successor_index)
      match self.edge_edits.get(key) {
        Some(edits) => edits.push(edit)
        None => self.edge_edits[key] = [edit]
      }
    }
    _ =>
      if edit.point is Some(point) {
        match point.placement {
          Before => self.before_edits[point.instruction.id].push(edit)
          After => self.after_edits[point.instruction.id].push(edit)
        }
      }
  }
  true
}

///|
/// Returns the allocation edits scheduled at one instruction point.
///
/// The returned view is read-only and remains valid while this allocation is
/// not mutated. Target emitters should query this index instead of scanning
/// `edits()` for every instruction.
pub fn Allocation::edits_at(
  self : Allocation,
  instruction : Instruction,
  placement : PointPlacement,
) -> ArrayView[Edit] {
  if !self.owns_instruction(instruction) {
    let empty : Array[Edit] = []
    return empty[:]
  }
  match placement {
    Before => self.before_edits[instruction.id][:]
    After => self.after_edits[instruction.id][:]
  }
}

///|
/// Returns the allocation edits scheduled for one outgoing CFG edge.
///
/// The returned view is read-only and remains valid while this allocation is
/// not mutated. Target emitters should query this index instead of scanning
/// `edits()` for every edge.
pub fn Allocation::edge_edits_at(
  self : Allocation,
  source : Block,
  successor_index : Int,
) -> ArrayView[Edit] {
  if !self.owns_block(source) || successor_index < 0 {
    let empty : Array[Edit] = []
    return empty[:]
  }
  match self.edge_edits.get((source.id, successor_index)) {
    Some(edits) => edits[:]
    None => {
      let empty : Array[Edit] = []
      empty[:]
    }
  }
}

///|
pub fn Allocation::add_safepoint_root(
  self : Allocation,
  instruction : Instruction,
  value : Value,
  location : Location,
) -> Bool {
  if !self.owns_instruction(instruction) ||
    !self.owns_value(value) ||
    !self.location_matches(location, self.value_types[value.id]) {
    return false
  }
  self.safepoint_roots.push({ instruction, value, location, })
  true
}

///|
pub fn Allocation::edits(self : Allocation) -> Array[Edit] {
  self.edits.copy()
}

///|
pub fn Allocation::edit_count(self : Allocation) -> Int {
  self.edits.length()
}

///|
pub fn Allocation::statistics(self : Allocation) -> AllocationStatistics {
  let mut spills = 0
  let mut reloads = 0
  let mut reg_moves = 0
  let mut spill_to_spill = 0
  for edit in self.edits {
    match edit.kind {
      Spill(..) => spills = spills + 1
      Reload(..) => reloads = reloads + 1
      Move(..) => reg_moves = reg_moves + 1
      EdgeMove(from~, to~, ..) =>
        match (from, to) {
          (Register(_), Stack(_)) => spills = spills + 1
          (Stack(_), Register(_)) => reloads = reloads + 1
          (Register(_), Register(_)) => reg_moves = reg_moves + 1
          (Stack(_), Stack(_)) => spill_to_spill = spill_to_spill + 1
        }
    }
  }
  {
    spill_slots: self.stack_slots.length(),
    spills,
    reloads,
    reg_moves,
    spill_to_spill,
  }
}

///|
pub fn Allocation::safepoint_roots(
  self : Allocation,
  instruction : Instruction,
) -> Array[(Value, Location)] {
  if !self.owns_instruction(instruction) {
    return []
  }
  let roots : Array[(Value, Location)] = []
  for root in self.safepoint_roots {
    if root.instruction == instruction {
      roots.push((root.value, root.location))
    }
  }
  roots
}

///|
pub suberror AllocationVerifyError {
  SelectedFailure(cause~ : VCodeVerifyError)
  SourceMismatch
  MissingValueLocation(value~ : Value)
  ForeignLocation(value~ : Value)
  LocationClassMismatch(value~ : Value)
  MissingOperandLocation(instruction~ : Instruction, operand~ : Int)
  OperandClassMismatch(instruction~ : Instruction, operand~ : Int)
  RegisterConstraintViolation(instruction~ : Instruction, operand~ : Int)
  FixedConstraintViolation(instruction~ : Instruction, operand~ : Int)
  TiedConstraintViolation(instruction~ : Instruction, operand~ : Int)
  Interference(left~ : Value, right~ : Value, location~ : Location)
  ClobberViolation(instruction~ : Instruction, value~ : Value)
  InvalidStackSlotLayout(slot~ : StackSlot)
  InvalidEdit(index~ : Int)
  MissingReload(instruction~ : Instruction, operand~ : Int)
  InvalidEdgeMove(index~ : Int)
  MissingSafepointRoot(instruction~ : Instruction, value~ : Value)
  UnexpectedSafepointRoot(instruction~ : Instruction, value~ : Value)
} derive(Eq, Debug)

///|
pub impl Show for AllocationVerifyError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
pub struct FrameLayout {
  priv source_owner : Ref[Unit]
  priv allocation_owner : Ref[Unit]
  priv source_slot_count : Int
  priv frame_size : Int
  priv alignment : Int
  priv slot_offsets : Array[Int?]
}

///|
pub fn[Inst] FrameLayout::new(
  function : Function[Inst],
  allocation : Allocation,
  frame_size : Int,
  alignment : Int,
) -> FrameLayout {
  {
    source_owner: function.owner,
    allocation_owner: allocation.owner,
    source_slot_count: allocation.stack_slot_count(),
    frame_size,
    alignment,
    slot_offsets: Array::make(allocation.stack_slot_count(), None),
  }
}

///|
pub fn FrameLayout::place_slot(
  self : FrameLayout,
  slot : StackSlot,
  offset : Int,
) -> Bool {
  if !physical_equal(self.allocation_owner, slot.owner) ||
    slot.id < 0 ||
    slot.id >= self.source_slot_count {
    return false
  }
  self.slot_offsets[slot.id] = Some(offset)
  true
}

///|
pub fn FrameLayout::frame_size(self : FrameLayout) -> Int {
  self.frame_size
}

///|
pub fn FrameLayout::alignment(self : FrameLayout) -> Int {
  self.alignment
}

///|
pub fn FrameLayout::slot_offset(self : FrameLayout, slot : StackSlot) -> Int? {
  if !physical_equal(self.allocation_owner, slot.owner) ||
    slot.id < 0 ||
    slot.id >= self.source_slot_count {
    return None
  }
  self.slot_offsets[slot.id]
}

///|
pub suberror FrameVerifyError {
  AllocationFailure(cause~ : AllocationVerifyError)
  SourceMismatch
  InvalidFrameSize(size~ : Int)
  InvalidFrameAlignment(alignment~ : Int)
  MissingStackSlot(slot~ : StackSlot)
  MisalignedStackSlot(slot~ : StackSlot)
  OverlappingStackSlots(left~ : StackSlot, right~ : StackSlot)
  StackSlotOutOfFrame(slot~ : StackSlot)
} derive(Eq, Debug)

///|
pub impl Show for FrameVerifyError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
pub suberror EmissionVerifyError {
  FrameFailure(cause~ : FrameVerifyError)
} derive(Eq, Debug)

///|
pub impl Show for EmissionVerifyError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}
