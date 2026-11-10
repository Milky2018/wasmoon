///|
#derive(Eq)
priv enum AllocationAdmission {
  Acquire(Int32)
  New(Int32, Bool)
}

///|
priv struct AllocationAdmissionEdit {
  operations : Map[Int32, AllocationAdmission]
  restore : () -> Unit
}

///|
fn AllocationAdmission::opcode(self : AllocationAdmission) -> @milkir.ExtOp {
  let (name, type_) = match self {
    Acquire(type_) => ("native_acquire_struct_admission", type_)
    New(type_, false) => ("native_admitted_struct_new", type_)
    New(type_, true) => ("native_admitted_struct_new_default", type_)
  }
  ExtOp(@wasm_milkir.WASM_DIALECT, name, [type_])
}

///|
fn decode_allocation_admission(op : @milkir.ExtOp) -> AllocationAdmission? {
  guard op.immediates is [type_] && type_ >= 0 else { return None }
  let operation : AllocationAdmission = match op.opcode {
    "native_acquire_struct_admission" => Acquire(type_)
    "native_admitted_struct_new" => New(type_, false)
    "native_admitted_struct_new_default" => New(type_, true)
    _ => return None
  }
  if op == operation.opcode() {
    Some(operation)
  } else {
    None
  }
}

///|
/// Only admitted allocations refresh their cell after a collecting fallback.
/// Calls, polls and arbitrary stores can invalidate its instance metadata.
fn preserves_allocation_admission(opcode : @milkir.Opcode) -> Bool {
  if opcode is Ext(extension, _) &&
    (
      decode_allocation_admission(extension) is Some(_) ||
      decode_projection(extension) is Some(_)
    ) {
    return true
  }
  match opcode {
    Memory(Load(_) | LoadNarrow(_, _, _)) => true
    _ => {
      let effect = @effects.analyze(opcode)
      effect.preserves_checked_references() && !effect.may_collect
    }
  }
}

///|
/// Independent must-analysis checks token origin, exact local type and every
/// path, including a barrier on a side entry or a previous loop iteration.
fn allocation_admission_error(function : @milkir.Function) -> String? {
  let origins : Map[Int32, (Int32, Int32)] = Map([])
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) &&
        decode_allocation_admission(op) is Some(Acquire(type_)) &&
        inst.results is [value] {
        origins[value.id] = (origins.length(), type_)
      }
    }
  }
  let cfg = @milkir.CFG::build(function)
  let outputs = Array::makei(cfg.size, _ => Array::make(origins.length(), true))
  fn incoming(block : Int32) -> Array[Bool] {
    let predecessors = cfg.get_predecessors(block)
    if block == 0 || predecessors.is_empty() {
      return Array::make(origins.length(), false)
    }
    let state = outputs[predecessors[0]].copy()
    for predecessor in predecessors[1:] {
      for bit in 0..<state.length() {
        state[bit] = state[bit] && outputs[predecessor][bit]
      }
    }
    state
  }
  fn transfer(inst : @milkir.Inst, state : Array[Bool]) -> Unit {
    if inst.opcode is Ext(op, _) &&
      decode_allocation_admission(op) is Some(Acquire(_)) &&
      inst.results is [value] &&
      origins.get(value.id) is Some((bit, _)) {
      state[bit] = true
    } else if inst.opcode is Ext(op, _) &&
      decode_allocation_admission(op) is Some(New(_, _)) {
      let retained = match inst.args.last() {
        Some(value) => origins.get(value.id).map(origin => origin.0)
        None => None
      }
      for bit in 0..<state.length() {
        if retained != Some(bit) {
          state[bit] = false
        }
      }
    } else if !preserves_allocation_admission(inst.opcode) {
      state.fill(false)
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for block in function.blocks {
      let state = incoming(block.id)
      for id in function.block_instruction_ids(block) {
        transfer(function.instruction_by_id(id).unwrap(), state)
      }
      if state != outputs[block.id] {
        outputs[block.id] = state
        changed = true
      }
    }
  }
  for block in function.blocks {
    let state = incoming(block.id)
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) &&
        decode_allocation_admission(op) is Some(New(type_, _)) {
        guard inst.args.last() is Some(token) &&
          origins.get(token.id) is Some((bit, source_type)) &&
          source_type == type_ &&
          state[bit] else {
          return Some(
            "instruction \{id}: missing live same-type allocation admission",
          )
        }
      }
      transfer(inst, state)
    }
  }
  None
}

///|
/// The edit is private to native selection. Its stack cell holds a canonical
/// identity, never a payload address. Every collecting fallback invalidates and
/// reacquires it, so a root visitor cannot leave cached admission metadata stale.
fn prepare_allocation_admission(
  function : @milkir.Function,
  validation : @wasm_milkir.WasmValidationContext,
  sites : Map[Int32, Bool],
) -> AllocationAdmissionEdit? raise @milkir.VerifyError {
  if sites.is_empty() || function.blocks.length() > 256 {
    return None
  }
  let cfg = @milkir.CFG::build(function)
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
  }
  let operations : Map[Int32, AllocationAdmission] = Map([])
  let saved : Array[(@milkir.Inst, @milkir.Opcode, Array[@milkir.Value])] = []
  let preheaders : Map[Int32, Array[@milkir.Inst]] = Map([])
  let acquires : Array[@milkir.Inst] = []
  fn restore() -> Unit {
    for (inst, opcode, args) in saved {
      inst.set_opcode(opcode)
      inst.operands.clear()
      inst.operands.append(args)
    }
    for id, instructions in preheaders {
      blocks[id].set_instructions(instructions)
    }
    for inst in acquires {
      function.discard_inst(inst)
    }
  }
  errdefer restore()
  for loop_ in cfg.find_loops() {
    if loop_.blocks.length() > 80 || loop_.header == 0 {
      continue
    }
    let predecessors = cfg
      .get_predecessors(loop_.header)
      .filter(id => !loop_.contains(id))
    guard predecessors is [preheader] &&
      blocks[preheader].terminator is Some(Jump(target, _)) &&
      target == loop_.header else {
      continue
    }
    if loop_.blocks.any(id => {
        function
        .block_instruction_ids(blocks[id])
        .any(inst => {
          let opcode = function.instruction_by_id(inst).unwrap().opcode
          !preserves_allocation_admission(opcode) &&
          !(@wasm_milkir.decode_opcode(opcode)
          is Some(StructNew(_) | StructNewDefault(_)))
        })
      }) {
      continue
    }
    // Every collecting operation in this region must refresh the same cell.
    // A collector's root visitor may update runtime metadata before returning.
    let types : Map[Int32, Bool] = Map([])
    let mut complete = true
    for id in loop_.blocks {
      for inst_id in function.block_instruction_ids(blocks[id]) {
        let inst = function.instruction_by_id(inst_id).unwrap()
        if inst.opcode is Ext(op, _) && decode_projection(op) is Some(_) {
          continue
        }
        if @effects.analyze(inst.opcode).may_collect {
          match @wasm_milkir.decode_opcode(inst.opcode) {
            Some(StructNew(type_) | StructNewDefault(type_)) if sites.contains(
                inst_id,
              ) => {
              types[type_] = true
              if struct_allocation_layout(validation, type_) is None {
                complete = false
              }
            }
            _ => complete = false
          }
        }
      }
    }
    if !complete || types.length() != 1 {
      continue
    }
    let tokens : Map[Int32, @milkir.Value] = Map([])
    for block in function.blocks {
      if !loop_.contains(block.id) {
        continue
      }
      for id in function.block_instruction_ids(block).to_owned() {
        if !sites.contains(id) || operations.contains(id) {
          continue
        }
        let inst = function.instruction_by_id(id).unwrap()
        let (type_, default_) = match @wasm_milkir.decode_opcode(inst.opcode) {
          Some(StructNew(type_)) => (type_, false)
          Some(StructNewDefault(type_)) => (type_, true)
          _ => continue
        }
        guard validation.struct_fields(type_) is Some(fields) &&
          fields.length() <= 16 &&
          fields.all(field => {
            field_width(field, allow_callable_or_opaque=false) is Some(_)
          }) else {
          continue
        }
        let token = match tokens.get(type_) {
          Some(token) => token
          None => {
            let seed = blocks[preheader]
            if !preheaders.contains(preheader) {
              preheaders[preheader] = function
                .block_instruction_ids(seed)
                .map(id => function.instruction_by_id(id).unwrap())
            }
            let token = function.new_value(Ptr)
            let acquisition : AllocationAdmission = Acquire(type_)
            let acquire = function.new_inst(
              Ext(acquisition.opcode(), Signature([], [Ptr])),
              [],
              [token],
            )
            seed.append_inst(acquire)
            acquires.push(acquire)
            operations[acquire.id] = acquisition
            tokens[type_] = token
            token
          }
        }
        saved.push((inst, inst.opcode, inst.args.copy()))
        let allocation : AllocationAdmission = New(type_, default_)
        let args = inst.args.copy() + [token]
        inst.set_opcode(
          Ext(
            allocation.opcode(),
            Signature(args.map(value => value.ty), [Ref]),
          ),
        )
        inst.operands.clear()
        inst.operands.append(args)
        operations[id] = allocation
      }
    }
  }
  if operations.is_empty() {
    return None
  }
  if allocation_admission_error(function) is Some(error) {
    raise @milkir.VerifyError::unverifiable_instruction(error)
  }
  Some({ operations, restore, })
}
