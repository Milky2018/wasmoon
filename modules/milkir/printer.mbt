///|
fn format_value(value : Value) -> String {
  "v\{value.id}"
}

///|
fn format_intcc(cc : IntCC) -> String {
  match cc {
    Eq => "eq"
    Ne => "ne"
    Slt => "slt"
    Sle => "sle"
    Sgt => "sgt"
    Sge => "sge"
    Ult => "ult"
    Ule => "ule"
    Ugt => "ugt"
    Uge => "uge"
  }
}

///|
fn format_floatcc(cc : FloatCC) -> String {
  match cc {
    Eq => "eq"
    Ne => "ne"
    Lt => "lt"
    Le => "le"
    Gt => "gt"
    Ge => "ge"
  }
}

///|
fn format_opcode(
  opcode : Opcode,
  operands : Array[Value],
  result_ty : Type?,
) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    Iconst(n) => "iconst \{n}"
    Fconst(n) =>
      if result_ty is Some(F32) {
        let bits = n.reinterpret_as_int64().to_int()
        "fconst \{Float::reinterpret_from_int(bits)}"
      } else {
        "fconst \{n}"
      }
    Iadd => "iadd \{ops}"
    Isub => "isub \{ops}"
    Imul => "imul \{ops}"
    Umulh => "umulh \{ops}"
    Smulh => "smulh \{ops}"
    Sdiv => "sdiv \{ops}"
    Udiv => "udiv \{ops}"
    Srem => "srem \{ops}"
    Urem => "urem \{ops}"
    Band => "band \{ops}"
    Bor => "bor \{ops}"
    Bxor => "bxor \{ops}"
    Bnot => "bnot \{ops}"
    Ishl => "ishl \{ops}"
    Sshr => "sshr \{ops}"
    Ushr => "ushr \{ops}"
    Rotl => "rotl \{ops}"
    Rotr => "rotr \{ops}"
    Clz => "clz \{ops}"
    Ctz => "ctz \{ops}"
    Popcnt => "popcnt \{ops}"
    Icmp(cc) => "icmp.\{format_intcc(cc)} \{ops}"
    IcmpEq => "icmp.eq \{ops}"
    Fadd => "fadd \{ops}"
    Fsub => "fsub \{ops}"
    Fmul => "fmul \{ops}"
    Fdiv => "fdiv \{ops}"
    Fmin => "fmin \{ops}"
    Fmax => "fmax \{ops}"
    Fcmp(cc) => "fcmp.\{format_floatcc(cc)} \{ops}"
    Fneg => "fneg \{ops}"
    Fabs => "fabs \{ops}"
    Fsqrt => "fsqrt \{ops}"
    Fceil => "fceil \{ops}"
    Ffloor => "ffloor \{ops}"
    Ftrunc => "ftrunc \{ops}"
    Fnearest => "fnearest \{ops}"
    Ireduce => "ireduce \{ops}"
    Sextend => "sextend \{ops}"
    Uextend => "uextend \{ops}"
    Fpromote => "fpromote \{ops}"
    Fdemote => "fdemote \{ops}"
    FcvtToSint => "fcvt_to_sint \{ops}"
    FcvtToUint => "fcvt_to_uint \{ops}"
    FcvtToSintSat => "fcvt_to_sint_sat \{ops}"
    FcvtToUintSat => "fcvt_to_uint_sat \{ops}"
    SintToFcvt => "sint_to_fcvt \{ops}"
    UintToFcvt => "uint_to_fcvt \{ops}"
    Bitcast => "bitcast \{ops}"
    Sextend8 => "sextend8 \{ops}"
    Sextend16 => "sextend16 \{ops}"
    Sextend32 => "sextend32 \{ops}"
    Select => "select \{ops}"
    Copy => "copy \{ops}"
    Load => "load \{ops}"
    Store => "store \{ops}"
    LoadPtr(ty) => "load_ptr.\{ty} \{ops}"
    LoadPtrNarrow(result_ty, bits, signed) => {
      let suffix = if signed { "s" } else { "u" }
      "load_ptr\{bits}\{suffix}.\{result_ty} \{ops}"
    }
    StorePtr(ty) => "store_ptr.\{ty} \{ops}"
    StorePtrNarrow(bits) => "store_ptr\{bits} \{ops}"
    StackAddr(slot) => "stack_addr slot=\{slot.id}"
    Call(symbol) => "call \{symbol.name}(\{ops})"
    CallIndirect(_) => "call_indirect(\{ops})"
    CallPtr(num_args, num_results) =>
      "call_ptr(\{num_args}) -> \{num_results} (\{ops})"
    Trap(reason) => "trap \"\{reason}\""
    Custom(name) => "\{name} \{ops}"
  }
}

///|
fn format_inst(inst : Inst) -> String {
  let result_ty = if inst.results.length() > 0 {
    Some(inst.results[0].ty)
  } else {
    None
  }
  let opcode = format_opcode(inst.opcode, inst.args, result_ty)
  if inst.results.is_empty() {
    opcode
  } else if inst.results.length() == 1 {
    let result = inst.results[0]
    "\{format_value(result)}:\{result.ty} = \{opcode}"
  } else {
    let results = inst.results
      .map(fn(result) { "\{format_value(result)}:\{result.ty}" })
      .join(", ")
    "(\{results}) = \{opcode}"
  }
}

///|
fn format_terminator(term : Terminator) -> String {
  match term {
    Jump(target, args) => {
      let args_str = args.map(format_value).join(", ")
      if args.length() > 0 {
        "jump block\{target}(\{args_str})"
      } else {
        "jump block\{target}"
      }
    }
    Branch(cond, true_target, true_args, false_target, false_args) => {
      let true_str = true_args.map(format_value).join(", ")
      let false_str = false_args.map(format_value).join(", ")
      "branch \{format_value(cond)}, block\{true_target}(\{true_str}), block\{false_target}(\{false_str})"
    }
    Brz(cond, then_block, else_block) =>
      "brz \{format_value(cond)}, block\{then_block}, block\{else_block}"
    Brnz(cond, then_block, else_block) =>
      "brnz \{format_value(cond)}, block\{then_block}, block\{else_block}"
    BrTable(index, targets, default_target) => {
      let targets_str = targets.map(fn(target) { "block\{target}" }).join(", ")
      "br_table \{format_value(index)}, [\{targets_str}], block\{default_target}"
    }
    Return(values) => {
      let values_str = values.map(format_value).join(", ")
      if values.is_empty() {
        "return"
      } else {
        "return \{values_str}"
      }
    }
    TrapExit(reason) => "trap \"\{reason}\""
  }
}

///|
fn format_block(block : Block) -> String {
  let sb = StringBuilder::new()
  if block.params.length() > 0 {
    let params = block.params
      .map(fn(value) { "\{format_value(value)}:\{value.ty}" })
      .join(", ")
    sb.write_string("block\{block.id}(\{params}):\n")
  } else {
    sb.write_string("block\{block.id}:\n")
  }
  for inst in block.instructions {
    sb.write_string("    ")
    sb.write_string(format_inst(inst))
    sb.write_string("\n")
  }
  if block.terminator is Some(term) {
    sb.write_string("    ")
    sb.write_string(format_terminator(term))
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
pub fn Function::print(self : Function) -> String {
  let sb = StringBuilder::new()
  let params : Array[String] = []
  for i, ty in self.signature.params {
    params.push("v\{i}:\{ty}")
  }
  let params_text = params.join(", ")
  let results = self.signature.results.map(fn(ty) { ty.to_string() }).join(", ")
  sb.write_string("function \{self.name}(\{params_text})")
  if self.signature.results.length() > 0 {
    sb.write_string(" -> ")
    if self.signature.results.length() == 1 {
      sb.write_string(results)
    } else {
      sb.write_string("(\{results})")
    }
  }
  sb.write_string(" {\n")
  for block in self.blocks {
    sb.write_string(format_block(block))
  }
  sb.write_string("}\n")
  sb.to_string()
}

///|
pub fn IRBuilder::print(self : IRBuilder) -> String {
  self.func.print()
}
