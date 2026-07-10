///|
pub suberror VerifyError {
  MissingTerminator(block_id~ : Int)
  EmptyFunction
  UndefinedValue(value_id~ : Int)
  InvalidBlockTarget(block_id~ : Int)
  ArityMismatch(message~ : String)
  TypeMismatch(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for VerifyError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn Function::verify(self : Function) -> Unit raise VerifyError {
  if self.blocks.is_empty() {
    raise EmptyFunction
  }
  let blocks : Array[Block?] = Array::make(self.next_block_id, None)
  for block in self.blocks {
    blocks[block.id] = Some(block)
  }
  let defined : @hashmap.HashMap[Int, Type] = HashMap([])
  for item in self.params {
    let (param, ty) = item
    defined.set(param.id, ty)
  }
  for block in self.blocks {
    for item in block.params {
      let (param, ty) = item
      defined.set(param.id, ty)
    }
    for inst in block.instructions {
      verify_inst(inst, defined)
      for result in inst.results {
        defined.set(result.id, result.ty)
      }
    }
    if block.terminator is None {
      raise MissingTerminator(block_id=block.id)
    } else if block.terminator is Some(term) {
      verify_terminator(term, defined, blocks, self.results)
    }
  }
}

///|
fn verify_defined(
  value : Value,
  defined : @hashmap.HashMap[Int, Type],
) -> Unit raise VerifyError {
  match defined.get(value.id) {
    None => raise UndefinedValue(value_id=value.id)
    Some(defined_type) =>
      if value.ty != defined_type {
        raise TypeMismatch(
          message="value \{value.id} has type \{value.ty}, but its definition has type \{defined_type}",
        )
      }
  }
}

///|
fn require_arity(
  actual : Int,
  expected : Int,
  context : String,
) -> Unit raise VerifyError {
  if actual != expected {
    raise ArityMismatch(
      message="\{context} expects \{expected} operands, got \{actual}",
    )
  }
}

///|
fn require_same_type(
  a : Value,
  b : Value,
  context : String,
) -> Unit raise VerifyError {
  if a.ty != b.ty {
    raise TypeMismatch(message="\{context} operands have mismatched types")
  }
}

///|
fn require_block(
  block_id : Int,
  blocks : Array[Block?],
) -> Block raise VerifyError {
  if block_id < 0 || block_id >= blocks.length() {
    raise InvalidBlockTarget(block_id~)
  }
  match blocks[block_id] {
    Some(block) => block
    None => raise InvalidBlockTarget(block_id~)
  }
}

///|
fn verify_block_args(
  block_id : Int,
  args : Array[Value],
  blocks : Array[Block?],
  defined : @hashmap.HashMap[Int, Type],
  edge : String,
) -> Unit raise VerifyError {
  let block = require_block(block_id, blocks)
  for arg in args {
    verify_defined(arg, defined)
  }
  if args.length() != block.params.length() {
    raise ArityMismatch(
      message="\{edge} to block \{block_id} expects \{block.params.length()} arguments, got \{args.length()}",
    )
  }
  for i, arg in args {
    let (_, expected_type) = block.params[i]
    if arg.ty != expected_type {
      raise TypeMismatch(
        message="\{edge} to block \{block_id} argument \{i} has type \{arg.ty}, expected \{expected_type}",
      )
    }
  }
}

///|
fn verify_i32(value : Value, context : String) -> Unit raise VerifyError {
  if value.ty != I32 {
    raise TypeMismatch(message="\{context} must be i32, got \{value.ty}")
  }
}

///|
fn verify_inst(
  inst : Inst,
  defined : @hashmap.HashMap[Int, Type],
) -> Unit raise VerifyError {
  for arg in inst.args {
    verify_defined(arg, defined)
  }
  match inst.opcode {
    Iconst(_) | Fconst(_) | StackAddr(_) =>
      require_arity(inst.args.length(), 0, "constant")
    Iadd
    | Isub
    | Imul
    | Umulh
    | Smulh
    | Sdiv
    | Udiv
    | Srem
    | Urem
    | Band
    | Bor
    | Bxor
    | Ishl
    | Sshr
    | Ushr
    | Rotl
    | Rotr => {
      require_arity(inst.args.length(), 2, "binary")
      require_same_type(inst.args[0], inst.args[1], "binary")
    }
    Bnot
    | Clz
    | Ctz
    | Popcnt
    | Fneg
    | Fabs
    | Fsqrt
    | Fceil
    | Ffloor
    | Ftrunc
    | Fnearest
    | Ireduce
    | Sextend
    | Uextend
    | Fpromote
    | Fdemote
    | FcvtToSint
    | FcvtToUint
    | FcvtToSintSat
    | FcvtToUintSat
    | SintToFcvt
    | UintToFcvt
    | Bitcast
    | Sextend8
    | Sextend16
    | Sextend32
    | Copy
    | Trap(_) => require_arity(inst.args.length(), 1, "unary")
    Icmp(_) | IcmpEq | Fcmp(_) => {
      require_arity(inst.args.length(), 2, "compare")
      require_same_type(inst.args[0], inst.args[1], "compare")
      if inst.results.length() == 1 && inst.results[0].ty != I32 {
        raise TypeMismatch(message="compare result must be i32")
      }
    }
    Fadd | Fsub | Fmul | Fdiv | Fmin | Fmax => {
      require_arity(inst.args.length(), 2, "float binary")
      require_same_type(inst.args[0], inst.args[1], "float binary")
    }
    Select => require_arity(inst.args.length(), 3, "select")
    Load => require_arity(inst.args.length(), 1, "load")
    Store => require_arity(inst.args.length(), 2, "store")
    LoadPtr(_) =>
      if inst.args.length() < 1 {
        raise ArityMismatch(message="load_ptr expects at least 1 operand")
      }
    LoadPtrNarrow(_, _, _) =>
      if inst.args.length() < 1 {
        raise ArityMismatch(
          message="load_ptr_narrow expects at least 1 operand",
        )
      }
    StorePtr(_) =>
      if inst.args.length() < 2 {
        raise ArityMismatch(message="store_ptr expects at least 2 operands")
      }
    StorePtrNarrow(_) =>
      if inst.args.length() < 2 {
        raise ArityMismatch(
          message="store_ptr_narrow expects at least 2 operands",
        )
      }
    Call(_) | CallIndirect(_) | CallPtr(_, _) | Custom(_) => ()
    _ => ()
  }
}

///|
fn verify_terminator(
  term : Terminator,
  defined : @hashmap.HashMap[Int, Type],
  blocks : Array[Block?],
  result_types : Array[Type],
) -> Unit raise VerifyError {
  match term {
    Return(values) => {
      for value in values {
        verify_defined(value, defined)
      }
      if values.length() != result_types.length() {
        raise ArityMismatch(
          message="return expects \{result_types.length()} values, got \{values.length()}",
        )
      }
      for i, value in values {
        let expected_type = result_types[i]
        if value.ty != expected_type {
          raise TypeMismatch(
            message="return value \{i} has type \{value.ty}, expected \{expected_type}",
          )
        }
      }
    }
    Jump(target, values) =>
      verify_block_args(target, values, blocks, defined, "jump")
    Branch(cond, true_target, true_args, false_target, false_args) => {
      verify_defined(cond, defined)
      verify_i32(cond, "branch condition")
      verify_block_args(true_target, true_args, blocks, defined, "branch")
      verify_block_args(false_target, false_args, blocks, defined, "branch")
    }
    Brz(cond, true_target, false_target)
    | Brnz(cond, true_target, false_target) => {
      verify_defined(cond, defined)
      verify_i32(cond, "branch condition")
      verify_block_args(true_target, [], blocks, defined, "branch")
      verify_block_args(false_target, [], blocks, defined, "branch")
    }
    BrTable(index, targets, default_target) => {
      verify_defined(index, defined)
      verify_i32(index, "branch table index")
      for target in targets {
        verify_block_args(target, [], blocks, defined, "branch table")
      }
      verify_block_args(default_target, [], blocks, defined, "branch table")
    }
    Trap(_) | TrapExit(_) => ()
  }
}
