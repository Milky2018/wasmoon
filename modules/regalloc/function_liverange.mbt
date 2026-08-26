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
fn[F : FunctionView] collect_function_liveness(
  function : F,
  ranges : LiveRangeSet,
) -> DenseLiveSets {
  let block_defs : Array[SparseVRegSet] = []
  let live_in : Array[SparseVRegSet] = []
  let successors : Array[Array[Int]] = []
  let block_ids : Array[Int] = []
  for block in 0..<function.block_count() {
    let definitions = SparseVRegSet::new()
    let uses = SparseVRegSet::new()
    let block_start = ProgramPoint(block, -1)
    for value in function.block_parameters(block) {
      definitions.set(value.id, true)
      find_or_create_live_range(ranges, value).add_use(
        UsePosition(block_start, LiveDef, AnyReg),
      )
    }
    if block == 0 {
      for value in function.entry_values() {
        definitions.set(value.id, true)
        find_or_create_live_range(ranges, value).add_use(
          UsePosition(block_start, LiveDef, AnyReg),
        )
      }
    }
    let instructions = function.block_instructions(block)
    for instruction_index, instruction in instructions {
      for operand in function.instruction_operands(instruction) {
        let point = operand_program_point(
          block,
          instruction_index,
          operand.timing,
        )
        find_or_create_live_range(ranges, operand.vreg).add_use(
          UsePosition(point, use_kind_of_role(operand.role), operand.constraint)
          .with_preference(operand.preference)
          .with_tie(operand.tie_id),
        )
        if operand.role is Use {
          if !definitions.contains(operand.vreg.id) {
            uses.set(operand.vreg.id, true)
          }
        }
        if operand.role is Def || operand.role is UseDef {
          definitions.set(operand.vreg.id, true)
        }
      }
    }
    let block_successors = function.block_successors(block)
    for successor in 0..<block_successors.length() {
      for argument in function.edge_arguments(block, successor) {
        if !definitions.contains(argument.id) {
          uses.set(argument.id, true)
        }
      }
    }
    block_defs.push(definitions)
    live_in.push(uses)
    block_ids.push(block)
    successors.push(block_successors)
  }
  propagate_live_sets(
    function.block_count(),
    build_dense_successor_edges(block_ids, successors),
    block_defs,
    live_in,
  )
}

///|
fn[F : FunctionView] build_function_range_fragments(
  ranges : LiveRangeSet,
  function : F,
  live_out : Array[Array[Int]],
) -> Unit {
  let open_ends : Array[ProgramPoint?] = Array::make(
    function.value_count(),
    None,
  )
  let open_values : Array[Int] = []
  for block in 0..<function.block_count() {
    let instructions = function.block_instructions(block)
    let block_start = ProgramPoint(block, -1)
    let block_end = ProgramPoint(block, instructions.length() * 2)
    for value in live_out[block] {
      if open_ends[value] is None {
        open_values.push(value)
      }
      open_ends[value] = Some(block_end)
    }
    if !instructions.is_empty() {
      let edge_point = ProgramPoint(block, (instructions.length() - 1) * 2)
      for successor in 0..<function.block_successors(block).length() {
        for argument in function.edge_arguments(block, successor) {
          if open_ends[argument.id] is None {
            open_values.push(argument.id)
            open_ends[argument.id] = Some(edge_point)
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
            match open_ends[operand.vreg.id] {
              Some(end) => {
                add_live_range_fragment(ranges, operand.vreg, point, end)
                open_ends[operand.vreg.id] = None
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
            if open_ends[operand.vreg.id] is None {
              open_values.push(operand.vreg.id)
              open_ends[operand.vreg.id] = Some(point)
            }
          }
        }
      }
    }
    for parameter in function.block_parameters(block) {
      match open_ends[parameter.id] {
        Some(end) => {
          add_live_range_fragment(ranges, parameter, block_start, end)
          open_ends[parameter.id] = None
        }
        None =>
          add_live_range_fragment(ranges, parameter, block_start, block_start)
      }
    }
    if block == 0 {
      for parameter in function.entry_values() {
        match open_ends[parameter.id] {
          Some(end) => {
            add_live_range_fragment(ranges, parameter, block_start, end)
            open_ends[parameter.id] = None
          }
          None =>
            add_live_range_fragment(ranges, parameter, block_start, block_start)
        }
      }
    }
    for value_id in open_values {
      if open_ends[value_id] is Some(end) {
        add_live_range_fragment(
          ranges,
          { id: value_id, class: function.value_class(value_id), },
          block_start,
          end,
        )
        open_ends[value_id] = None
      }
    }
    open_values.clear()
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
  let live_sets = collect_function_liveness(function, ranges)
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
