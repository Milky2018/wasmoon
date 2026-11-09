///|
fn following_reference_read(
  function : @milkir.Function,
  id : Int32,
  view : @milkir.Value,
) -> Bool {
  let inst = function.instruction_by_id(id).unwrap()
  inst.opcode is Ext(field, _) &&
  decode_projection(field) is Some(FieldData(_, _, _, 1, true)) &&
  inst.args is [base] &&
  base.id == view.id
}

///|
priv struct InlineProjectionSites {
  eligible : Map[Int32, Bool]
  reserved_struct : Int32?
}

///|
/// Recognize the frontend's fixed VMContext slot loads. A loop-carried
/// value or a field of a GC object is not a fixed context slot.
fn fixed_context_reference(
  function : @milkir.Function,
  reference : @milkir.Value,
) -> Bool {
  let mut value = reference
  for ty in [@milkir.Type::Ref, I64, I64] {
    guard function.defining_inst(value) is Some(load) &&
      load.opcode == Memory(Load(ty)) &&
      load.args is [base, offset] &&
      function.defining_inst(offset) is Some(constant) &&
      constant.opcode is Scalar(IntConst(_)) else {
      return false
    }
    value = base
  }
  function.params.get(0) is Some(parameter) && parameter.0.id == value.id
}

///|
/// A code-size and locality heuristic only. Polls may still reenter, and the
/// selected view still checks every key and keeps its complete slow path.
fn loop_has_read_only_context(
  function : @milkir.Function,
  loop_ : @milkir.Loop,
) -> Bool {
  function.blocks.all(block => {
    !loop_.contains(block.id) ||
    function
    .block_instruction_ids(block)
    .all(id => {
      let opcode = function.instruction_by_id(id).unwrap().opcode
      if opcode is Ext(op, _) &&
        (
          decode_projection(op) is Some(_) ||
          decode_cached_poll(op) is Some(_) ||
          @wasm_milkir.decode(op) is Some(SafepointPoll(_, _, _, _))
        ) {
        true
      } else {
        let effects = @effects.analyze(opcode)
        effects.write is None && !effects.allocation
      }
    })
  })
}

///|
/// Expand bounded loops and small acyclic accessors. Larger CFGs retain
/// shared accessors to bound code growth.
fn inline_projection_sites(
  function : @milkir.Function,
  reserve_struct~ : Bool = false,
  reuse_only~ : Bool = false,
) -> InlineProjectionSites {
  let sites : Map[Int32, Bool] = Map([])
  let empty = { eligible: sites, reserved_struct: None, }
  if function.blocks.length() > 64 {
    return empty
  }
  let candidates : Array[(Int32, Int32, Bool, @milkir.Value)] = []
  for block in function.blocks {
    let ids = function.block_instruction_ids(block)
    for i in 0..<ids.length() {
      let id = ids[i]
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) &&
        decode_projection(op) is Some(StructData(_) | ArrayData(0)) &&
        inst.args is [reference] {
        let reference_read = reserve_struct &&
          decode_projection(op) is Some(StructData(_)) &&
          i + 1 < ids.length() &&
          inst.results is [view] &&
          following_reference_read(function, ids[i + 1], view)
        candidates.push((block.id, id, reference_read, reference))
      }
    }
  }
  if candidates.is_empty() {
    return empty
  }
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  // Small acyclic accessors can be called repeatedly by an outer loop. Bound
  // their expansion independently of local loop detection and allocator work.
  let small_accessor = !reuse_only &&
    function.blocks.length() <= 12 &&
    candidates.length() <= 3 &&
    loops.is_empty() &&
    function.blocks.fold(init=0, fn(total, block) {
      total + block.instruction_count()
    }) <=
    64
  let mut reserved_struct = None
  let mut smallest_loop = function.blocks.length() + 1
  let read_only_loops = if reuse_only {
    loops.map(loop_ => loop_has_read_only_context(function, loop_))
  } else {
    []
  }
  for (block, id, reference_read, reference) in candidates {
    let fixed_slot = reuse_only && fixed_context_reference(function, reference)
    let invariant_param = reuse_only &&
      function.params.any(parameter => parameter.0.id == reference.id)
    let mut in_loop = false
    for index, loop_ in loops {
      if loop_.contains(block) &&
        (
          !reuse_only ||
          invariant_param ||
          (fixed_slot && read_only_loops[index])
        ) {
        in_loop = true
        // Traversal order often reaches outer loops first. Reserve one of
        // the existing slots for a reference load in the smallest loop.
        if reference_read && loop_.blocks.length() < smallest_loop {
          reserved_struct = Some(id)
          smallest_loop = loop_.blocks.length()
        }
      }
    }
    if small_accessor || in_loop {
      sites[id] = true
    }
  }
  { eligible: sites, reserved_struct, }
}
