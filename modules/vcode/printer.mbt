///|
fn constraint_text(constraint : AllocationConstraint) -> String {
  match constraint {
    AnyReg => "any"
    AnyLocation => "any-location"
    FixedReg(reg) => "fixed(\{Repr(reg)})"
  }
}

///|
fn timing_text(timing : OperandTiming) -> String {
  match timing {
    Early => "early"
    Late => "late"
  }
}

///|
fn operand_text(operand : Operand, tied_to : Int?) -> String {
  let preference = match operand.preference {
    Some(reg) => "(prefer=\{Repr(reg)})"
    None => ""
  }
  let constraint = match tied_to {
    Some(index) => "tied(\{index})"
    None => constraint_text(operand.constraint)
  }
  "\{Repr(operand.value)}:\{constraint}\{preference}@\{timing_text(operand.timing)}"
}

///|
pub fn[Inst : Debug] Function::summary(self : Function[Inst]) -> String {
  let mut output = "vcode \{self.name}("
  for index, parameter in self.parameters {
    if index > 0 {
      output += ", "
    }
    output += "\{Repr(parameter)}:\{value_type_text(self.values[parameter.id].ty)}"
  }
  output += ")"
  let result_types = self.result_types()
  if !result_types.is_empty() {
    output += " -> ("
    for index, ty in result_types {
      if index > 0 {
        output += ", "
      }
      output += value_type_text(ty)
    }
    output += ")"
  }
  output += "\n"
  for block in self.layout {
    output += "block\{block.id}"
    let parameters = self.blocks[block.id].parameters
    if parameters.length() > 0 {
      output += "("
      for index, parameter in parameters {
        if index > 0 {
          output += ", "
        }
        output += "\{Repr(parameter)}:\{value_type_text(self.values[parameter.id].ty)}"
      }
      output += ")"
    }
    output += ":\n"
    let instructions = self.blocks[block.id].body.copy()
    match self.blocks[block.id].terminator {
      Some(terminator) => instructions.push(terminator)
      None => ()
    }
    for instruction in instructions {
      let data = self.instructions[instruction.id]
      output += "  i\{instruction.id} \{Repr(data.inst)}"
      let operands = self.instruction_operands(instruction)
      let uses = operands.filter(operand => operand.role == Use)
      let defs = operands.filter(operand => operand.role == Def)
      if uses.length() > 0 {
        output += " uses=["
        for index, operand in uses {
          if index > 0 {
            output += ", "
          }
          output += operand_text(operand, None)
        }
        output += "]"
      }
      if defs.length() > 0 {
        output += " defs=["
        for index, operand in defs {
          if index > 0 {
            output += ", "
          }
          let mut tied_to = None
          if operand.tie_id >= 0 {
            for operand_index, candidate in operands {
              if candidate.role == Use && candidate.tie_id == operand.tie_id {
                tied_to = Some(operand_index)
              }
            }
          }
          output += operand_text(operand, tied_to)
        }
        output += "]"
      }
      let clobbers = self.instruction_clobbers(instruction)
      if clobbers.length() > 0 {
        output += " clobbers=["
        for index, reg in clobbers {
          if index > 0 {
            output += ", "
          }
          output += Repr(reg).to_string()
        }
        output += "]"
      }
      for edge in data.successors {
        output += " -> block\{edge.target.id}("
        for index, argument in edge.arguments {
          if index > 0 {
            output += ", "
          }
          output += Repr(argument).to_string()
        }
        output += ")"
      }
      let metadata = data.metadata
      if metadata.source is Some(source) {
        output += " source=\{Repr(source)}"
      }
      if metadata.trap is Some(trap) {
        output += " trap=\{Repr(trap)}"
      }
      if metadata.safepoint is Some(safepoint) {
        output += " safepoint=\{Repr(safepoint)}"
      }
      if !metadata.live_gc_roots.is_empty() {
        output += " roots=\{Repr(metadata.live_gc_roots)}"
      }
      if metadata.symbol is Some(symbol) {
        output += " symbol=\{Repr(symbol)}"
      }
      if metadata.stack_map is Some(stack_map) {
        output += " stack-map=\{stack_map.id}:\{stack_map.argument_root_count}"
      }
      output += "\n"
    }
  }
  output
}

///|
fn Allocation::slot_text(self : Allocation, slot : StackSlot) -> String {
  let data = self.stack_slots[slot.id]
  "stack\{slot.id}:\{value_type_text(data.ty)}(size=\{data.size}, align=\{data.alignment})"
}

///|
fn Allocation::location_text(self : Allocation, location : Location) -> String {
  match location {
    Register(reg) => Repr(reg).to_string()
    Stack(slot) => self.slot_text(slot)
  }
}

///|
fn Allocation::dense_location_text(
  self : Allocation,
  location : AllocationLocation,
) -> String {
  match location.register() {
    Some(reg) => Repr(reg).to_string()
    None =>
      self.slot_text(
        StackSlot::new(self.owner, location.spill_index().unwrap()),
      )
  }
}

///|
fn dense_location_repr(location : AllocationLocation) -> String {
  match location.register() {
    Some(reg) => Repr(reg).to_string()
    None => "stack\{location.spill_index().unwrap()}"
  }
}

///|
pub fn Allocation::summary(self : Allocation) -> String {
  let mut output = "allocation \{self.function_name}\n"
  for index, location in self.value_locations {
    match location {
      Some(location) =>
        output += "  v\{index}:\{value_type_text(self.value_types[index])} -> \{self.dense_location_text(location)}\n"
      None => ()
    }
  }
  for instruction_index, locations in self.operand_locations {
    for operand_index, location in locations {
      match location {
        Some(location) =>
          output += "  i\{instruction_index} operand\{operand_index} -> \{dense_location_repr(location)}\n"
        None => ()
      }
    }
  }
  for edit in self.edits {
    match edit.kind {
      Reload(value~, slot~, reg~) =>
        output += "  \{Repr(edit.point.unwrap())}: reload \{Repr(value)} stack\{slot.id} -> \{Repr(reg)}\n"
      Spill(value~, reg~, slot~) =>
        output += "  \{Repr(edit.point.unwrap())}: spill \{Repr(value)} \{Repr(reg)} -> stack\{slot.id}\n"
      Move(value~, from~, to~) =>
        output += "  \{Repr(edit.point.unwrap())}: move \{Repr(value)} \{Repr(from)} -> \{Repr(to)}\n"
      EdgeMove(source~, successor_index~, value~, from~, to~) =>
        output += "  edge(block\{source.id}, \{successor_index}): move \{Repr(value)} \{self.location_text(from)} -> \{self.location_text(to)}\n"
    }
  }
  for root in self.safepoint_roots {
    output += "  i\{root.instruction.id} root \{Repr(root.value)} -> "
    output += match root.location.register() {
      Some(reg) => Repr(reg).to_string()
      None => "stack\{root.location.spill_index().unwrap()}"
    }
    output += "\n"
  }
  output
}
