///|
fn constraint_text(constraint : OperandConstraint) -> String {
  match constraint {
    Any => "any"
    Fixed(reg) => "fixed(\{to_repr(reg)})"
    TiedTo(index) => "tied(\{index})"
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
fn operand_text(operand : Operand) -> String {
  "\{to_repr(operand.value)}:\{constraint_text(operand.constraint)}@\{timing_text(operand.timing)}"
}

///|
pub fn[Inst : Debug] Function::summary(self : Function[Inst]) -> String {
  let mut output = "vcode \{self.name}("
  for index, parameter in self.parameters {
    if index > 0 {
      output += ", "
    }
    output += "\{to_repr(parameter)}:\{value_type_text(self.values[parameter.id].ty)}"
  }
  output += ")\n"
  for block in self.layout {
    output += "block\{block.id}"
    let parameters = self.blocks[block.id].parameters
    if parameters.length() > 0 {
      output += "("
      for index, parameter in parameters {
        if index > 0 {
          output += ", "
        }
        output += "\{to_repr(parameter)}:\{value_type_text(self.values[parameter.id].ty)}"
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
      output += "  i\{instruction.id} \{to_repr(data.inst)}"
      let operands = self.instruction_operands(instruction)
      let uses = operands.filter(operand => operand.role == Use)
      let defs = operands.filter(operand => operand.role == Def)
      if uses.length() > 0 {
        output += " uses=["
        for index, operand in uses {
          if index > 0 {
            output += ", "
          }
          output += operand_text(operand)
        }
        output += "]"
      }
      if defs.length() > 0 {
        output += " defs=["
        for index, operand in defs {
          if index > 0 {
            output += ", "
          }
          output += operand_text(operand)
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
          output += to_repr(reg).to_string()
        }
        output += "]"
      }
      for edge in data.successors {
        output += " -> block\{edge.target.id}("
        for index, argument in edge.arguments {
          if index > 0 {
            output += ", "
          }
          output += to_repr(argument).to_string()
        }
        output += ")"
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
    Register(reg) => to_repr(reg).to_string()
    Stack(slot) => self.slot_text(slot)
  }
}

///|
pub fn Allocation::summary(self : Allocation) -> String {
  let mut output = "allocation \{self.function_name}\n"
  for index, location in self.value_locations {
    match location {
      Some(location) =>
        output += "  v\{index}:\{value_type_text(self.value_types[index])} -> \{self.location_text(location)}\n"
      None => ()
    }
  }
  for instruction_index, locations in self.operand_locations {
    for operand_index, location in locations {
      match location {
        Some(reg) =>
          output += "  i\{instruction_index} operand\{operand_index} -> \{to_repr(reg)}\n"
        None => ()
      }
    }
  }
  for edit in self.edits {
    match edit.kind {
      Reload(value~, slot~, reg~) =>
        output += "  \{to_repr(edit.point.unwrap())}: reload \{to_repr(value)} stack\{slot.id} -> \{to_repr(reg)}\n"
      Spill(value~, reg~, slot~) =>
        output += "  \{to_repr(edit.point.unwrap())}: spill \{to_repr(value)} \{to_repr(reg)} -> stack\{slot.id}\n"
      Move(value~, from~, to~) =>
        output += "  \{to_repr(edit.point.unwrap())}: move \{to_repr(value)} \{to_repr(from)} -> \{to_repr(to)}\n"
      EdgeMove(source~, successor_index~, value~, from~, to~) =>
        output += "  edge(block\{source.id}, \{successor_index}): move \{to_repr(value)} \{self.location_text(from)} -> \{self.location_text(to)}\n"
    }
  }
  for root in self.safepoint_roots {
    output += "  i\{root.instruction.id} root \{to_repr(root.value)} -> "
    output += match root.location {
      Register(reg) => to_repr(reg).to_string()
      Stack(slot) => "stack\{slot.id}"
    }
    output += "\n"
  }
  output
}
