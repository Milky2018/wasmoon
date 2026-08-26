///|
priv struct EnvironmentFieldUseKey {
  field : EnvironmentField
  stability : EnvironmentFieldStability
  context : Value
} derive(Eq, Hash)

///|
pub struct EnvironmentFieldUseRegion {
  block : Block
  segment_index : Int
  occurrences : Array[Instruction]
} derive(Debug, Eq)

///|
pub struct EnvironmentFieldUseGroup {
  field : EnvironmentField
  stability : EnvironmentFieldStability
  context : Value
  occurrences : Array[Instruction]
  call_free_regions : Array[EnvironmentFieldUseRegion]
  context_use_count : Int
  can_replace_context_carrier : Bool
} derive(Debug, Eq)

///|
priv struct EnvironmentFieldUseGroupBuilder {
  field : EnvironmentField
  stability : EnvironmentFieldStability
  context : Value
  occurrences : Array[Instruction]
  call_free_regions : Array[EnvironmentFieldUseRegion]
}

///|
fn Function::environment_value_use_counts(self : Function) -> Array[Int] {
  let counts = Array::make(self.values.length(), 0)
  for data in self.instructions {
    if data.alive {
      for operand in data.operands {
        counts[operand.id] += 1
      }
      for root in data.metadata.live_gc_roots {
        counts[root.id] += 1
      }
    }
  }
  for block in self.blocks {
    if block.terminator is Some(record) {
      for value in terminator_values(record.kind) {
        counts[value.id] += 1
      }
      for root in record.metadata.live_gc_roots {
        counts[root.id] += 1
      }
    }
  }
  counts
}

///|
fn EnvironmentFieldUseGroupBuilder::record(
  self : EnvironmentFieldUseGroupBuilder,
  block : Block,
  segment_index : Int,
  instruction : Instruction,
) -> Unit {
  self.occurrences.push(instruction)
  if self.call_free_regions.last() is Some(region) &&
    region.block == block &&
    region.segment_index == segment_index {
    region.occurrences.push(instruction)
  } else {
    self.call_free_regions.push({
      block,
      segment_index,
      occurrences: [instruction],
    })
  }
}

///|
/// Analyze environment-field identity and use regions without selecting a
/// target materialization policy.
///
/// The input must already be verified. A call starts a new physical-pressure
/// segment, but does not change the semantic stability of a field.
pub fn Function::environment_field_use_groups(
  self : Function,
) -> Array[EnvironmentFieldUseGroup] {
  let use_counts = self.environment_value_use_counts()
  let group_indices : Map[EnvironmentFieldUseKey, Int] = Map([])
  let groups : Array[EnvironmentFieldUseGroupBuilder] = []
  for block in self.blocks() {
    let mut segment_index = 0
    for instruction in self.block_instructions(block) {
      let operation = self.instruction_operation(instruction).unwrap()
      if operation is Call(_) {
        segment_index += 1
        continue
      }
      guard operation is EnvironmentField(field, stability) &&
        self.instruction_operands(instruction) is [context] &&
        self.instruction_results(instruction) is [_] else {
        continue
      }
      let key = { field, stability, context, }
      let group_index = match group_indices.get(key) {
        Some(index) => index
        None => {
          let index = groups.length()
          groups.push({
            field,
            stability,
            context,
            occurrences: [],
            call_free_regions: [],
          })
          group_indices.set(key, index)
          index
        }
      }
      groups[group_index].record(block, segment_index, instruction)
    }
  }
  let entry = self.blocks()[0]
  groups.map(group => {
    let first_is_in_entry = group.occurrences
      .get(0)
      .map(instruction => {
        self.instructions[instruction.id].parent == Some(entry)
      })
      .unwrap_or(false)
    let context_use_count = use_counts[group.context.id]
    {
      field: group.field,
      stability: group.stability,
      context: group.context,
      occurrences: group.occurrences.copy(),
      call_free_regions: group.call_free_regions.map(region => {
        block: region.block,
        segment_index: region.segment_index,
        occurrences: region.occurrences.copy(),
      }),
      context_use_count,
      can_replace_context_carrier: group.stability == Stable &&
      first_is_in_entry &&
      context_use_count == group.occurrences.length(),
    }
  })
}
