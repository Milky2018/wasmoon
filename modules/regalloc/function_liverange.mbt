///|
fn operand_program_point(
  block : Int,
  instruction : Int,
  timing : OperandTiming,
) -> ProgramPoint {
  let phase = match timing {
    Early => 0
    Late => 1
  }
  ProgramPoint(block, instruction * 2 + phase)
}

///|
fn[F : FunctionView] function_block_use_defs(
  function : F,
  block : Int,
) -> (Array[VirtualReg], Array[VirtualReg]) {
  let uses : Array[VirtualReg] = []
  let defs = function.block_parameters(block)
  if block == 0 {
    for value in function.entry_values() {
      add_vreg(defs, value)
    }
  }
  for instruction in function.block_instructions(block) {
    for operand in function.instruction_operands(instruction) {
      match operand.role {
        Use =>
          if !contains_vreg(defs, operand.vreg) {
            add_vreg(uses, operand.vreg)
          }
        Def => add_vreg(defs, operand.vreg)
        UseDef => {
          if !contains_vreg(defs, operand.vreg) {
            add_vreg(uses, operand.vreg)
          }
          add_vreg(defs, operand.vreg)
        }
      }
    }
  }
  for successor in 0..<function.block_successors(block).length() {
    for argument in function.edge_arguments(block, successor) {
      if !contains_vreg(defs, argument) {
        add_vreg(uses, argument)
      }
    }
  }
  (uses, defs)
}

///|
fn[F : FunctionView] compute_function_live_sets(function : F) -> DenseLiveSets {
  let use_defs : Array[LiveSetUseDef] = []
  let definitions : Array[ProgramPoint?] = Array::make(
    function.value_count(),
    None,
  )
  let uses : Array[Array[ProgramPoint]] = []
  for _ in 0..<function.value_count() {
    uses.push([])
  }
  let successors : Array[Array[Int]] = []
  let block_ids : Array[Int] = []
  for block in 0..<function.block_count() {
    let (block_uses, block_defs) = function_block_use_defs(function, block)
    for value in block_uses {
      uses[value.id].push(ProgramPoint(block, -1))
    }
    for value in block_defs {
      if definitions[value.id] is None {
        definitions[value.id] = Some(ProgramPoint(block, -1))
      }
    }
    for instruction_index, instruction in function.block_instructions(block) {
      for operand in function.instruction_operands(instruction) {
        if operand.role is Use || operand.role is UseDef {
          uses[operand.vreg.id].push(
            operand_program_point(block, instruction_index, operand.timing),
          )
        }
        if operand.role is Def || operand.role is UseDef {
          if definitions[operand.vreg.id] is None {
            definitions[operand.vreg.id] = Some(
              operand_program_point(block, instruction_index, operand.timing),
            )
          }
        }
      }
    }
    let edge_point = (function.block_instructions(block).length() - 1) * 2
    for successor in 0..<function.block_successors(block).length() {
      for argument in function.edge_arguments(block, successor) {
        uses[argument.id].push(ProgramPoint(block, edge_point))
      }
    }
    block_ids.push(block)
    successors.push(function.block_successors(block))
  }
  for value in 0..<function.value_count() {
    if definitions[value] is Some(_) || !uses[value].is_empty() {
      use_defs.push({
        vreg_id: value,
        def_point: definitions[value],
        is_entry_param_def: false,
        use_points: uses[value],
      })
    }
  }
  compute_live_sets_from_use_defs(
    function.block_count(),
    function.value_count(),
    build_dense_successor_edges(block_ids, successors),
    use_defs,
  )
}

///|
fn[F : FunctionView] build_function_range_fragments(
  ranges : LiveRangeSet,
  function : F,
  live_out : Array[Array[Int]],
) -> Unit {
  for block in 0..<function.block_count() {
    let instructions = function.block_instructions(block)
    let block_start = ProgramPoint(block, -1)
    let block_end = ProgramPoint(block, instructions.length() * 2)
    let open_ends : Map[Int, ProgramPoint] = Map([])
    for value in live_out[block] {
      open_ends[value] = block_end
    }
    if !instructions.is_empty() {
      let edge_point = ProgramPoint(block, (instructions.length() - 1) * 2)
      for successor in 0..<function.block_successors(block).length() {
        for argument in function.edge_arguments(block, successor) {
          if open_ends.get(argument.id) is None {
            open_ends[argument.id] = edge_point
          }
        }
      }
    }
    let mut instruction_index = instructions.length()
    while instruction_index > 0 {
      instruction_index = instruction_index - 1
      let operands = function.instruction_operands(
        instructions[instruction_index],
      )
      for timing in [Late, Early] {
        for operand in operands {
          if operand.timing == timing &&
            (operand.role is Def || operand.role is UseDef) {
            let point = operand_program_point(block, instruction_index, timing)
            match open_ends.get(operand.vreg.id) {
              Some(end) => {
                add_live_range_fragment(ranges, operand.vreg, point, end)
                open_ends.remove(operand.vreg.id)
              }
              None =>
                add_live_range_fragment(ranges, operand.vreg, point, point)
            }
          }
        }
        for operand in operands {
          if operand.timing == timing &&
            (operand.role is Use || operand.role is UseDef) {
            let point = operand_program_point(block, instruction_index, timing)
            if open_ends.get(operand.vreg.id) is None {
              open_ends[operand.vreg.id] = point
            }
          }
        }
      }
    }
    for parameter in function.block_parameters(block) {
      match open_ends.get(parameter.id) {
        Some(end) => {
          add_live_range_fragment(ranges, parameter, block_start, end)
          open_ends.remove(parameter.id)
        }
        None =>
          add_live_range_fragment(ranges, parameter, block_start, block_start)
      }
    }
    if block == 0 {
      for parameter in function.entry_values() {
        match open_ends.get(parameter.id) {
          Some(end) => {
            add_live_range_fragment(ranges, parameter, block_start, end)
            open_ends.remove(parameter.id)
          }
          None =>
            add_live_range_fragment(ranges, parameter, block_start, block_start)
        }
      }
    }
    for value_id, end in open_ends {
      add_live_range_fragment(
        ranges,
        { id: value_id, class: function.value_class(value_id) },
        block_start,
        end,
      )
    }
  }
  for range in ranges.ranges {
    range.sort_ranges(ranges.block_order)
  }
}

///|
fn[F : FunctionView] build_function_live_ranges(function : F) -> LiveRangeSet {
  let block_order = Array::make(function.block_count(), 0)
  for block in 0..<function.block_count() {
    block_order[block] = block
  }
  let ranges = LiveRangeSet::LiveRangeSet(block_order)
  for block in 0..<function.block_count() {
    for instruction_index, instruction in function.block_instructions(block) {
      for operand in function.instruction_operands(instruction) {
        find_or_create_live_range(ranges, operand.vreg).add_use(
          UsePosition::UsePosition(
            operand_program_point(block, instruction_index, operand.timing),
            use_kind_of_role(operand.role),
            operand.constraint,
          ).with_tie(operand.tie_id),
        )
      }
    }
    for parameter in function.block_parameters(block) {
      find_or_create_live_range(ranges, parameter).add_use(
        UsePosition(ProgramPoint(block, -1), LiveDef, AnyReg),
      )
    }
    if block == 0 {
      for parameter in function.entry_values() {
        find_or_create_live_range(ranges, parameter).add_use(
          UsePosition(ProgramPoint(block, -1), LiveDef, AnyReg),
        )
      }
    }
  }
  let live_sets = compute_function_live_sets(function)
  build_function_range_fragments(ranges, function, live_sets.live_out)
  ranges.ranges.sort_by(fn(a, b) {
    match (a.start(), b.start()) {
      (Some(lhs), Some(rhs)) => {
        let by_point = lhs.compare_with_order(rhs, ranges.block_order)
        if by_point != 0 {
          by_point
        } else {
          a.vreg.id - b.vreg.id
        }
      }
      (None, Some(_)) => 1
      (Some(_), None) => -1
      (None, None) => a.vreg.id - b.vreg.id
    }
  })
  ranges
}
