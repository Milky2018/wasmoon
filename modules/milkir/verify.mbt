///|
pub suberror VerifyError {
  MissingTerminator(block_id~ : Int)
  EmptyFunction
  UndefinedValue(value_id~ : Int)
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
  let defined : @hashmap.HashMap[Int, Type] = HashMap([])
  for i, ty in self.signature.params {
    defined.set(i, ty)
  }
  for block in self.blocks {
    for param in block.params {
      defined.set(param.id, param.ty)
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
      verify_terminator(term, defined)
    }
  }
}

///|
fn verify_defined(
  value : Value,
  defined : @hashmap.HashMap[Int, Type],
) -> Unit raise VerifyError {
  if !defined.contains(value.id) {
    raise UndefinedValue(value_id=value.id)
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
    StorePtr(_) =>
      if inst.args.length() < 2 {
        raise ArityMismatch(message="store_ptr expects at least 2 operands")
      }
    Call(_) | CallIndirect(_) | CallPtr(_, _) | Custom(_) => ()
  }
}

///|
fn verify_terminator(
  term : Terminator,
  defined : @hashmap.HashMap[Int, Type],
) -> Unit raise VerifyError {
  match term {
    Return(values) | Jump(_, values) =>
      for value in values {
        verify_defined(value, defined)
      }
    Branch(cond, _, true_args, _, false_args) => {
      verify_defined(cond, defined)
      for value in true_args {
        verify_defined(value, defined)
      }
      for value in false_args {
        verify_defined(value, defined)
      }
    }
    Brz(cond, _, _) | Brnz(cond, _, _) => verify_defined(cond, defined)
    BrTable(index, _, _) => verify_defined(index, defined)
    TrapExit(_) => ()
  }
}
