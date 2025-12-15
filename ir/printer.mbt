// IR Printer - Pretty prints IR in a readable text format
// Similar to Cranelift's textual IR format

///|
/// Print a type
fn format_type(ty : Type) -> String {
  match ty {
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
    FuncRef => "funcref"
    ExternRef => "externref"
  }
}

///|
/// Print a value reference
fn format_value(v : Value) -> String {
  "v\{v.id}"
}

///|
/// Print an integer comparison code
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
/// Print a float comparison code
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
/// Print an opcode with its operands
fn format_opcode(opcode : Opcode, operands : Array[Value]) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    // Constants
    Iconst(n) => "iconst \{n}"
    Fconst(n) => "fconst \{n}"

    // Integer arithmetic
    Iadd => "iadd \{ops}"
    Isub => "isub \{ops}"
    Imul => "imul \{ops}"
    Sdiv => "sdiv \{ops}"
    Udiv => "udiv \{ops}"
    Srem => "srem \{ops}"
    Urem => "urem \{ops}"

    // Bitwise operations
    Band => "band \{ops}"
    Bor => "bor \{ops}"
    Bxor => "bxor \{ops}"
    Bnot => "bnot \{ops}"
    Ishl => "ishl \{ops}"
    Sshr => "sshr \{ops}"
    Ushr => "ushr \{ops}"
    Rotl => "rotl \{ops}"
    Rotr => "rotr \{ops}"

    // Bit counting
    Clz => "clz \{ops}"
    Ctz => "ctz \{ops}"
    Popcnt => "popcnt \{ops}"

    // Comparisons
    Icmp(cc) => "icmp.\{format_intcc(cc)} \{ops}"

    // Floating point arithmetic
    Fadd => "fadd \{ops}"
    Fsub => "fsub \{ops}"
    Fmul => "fmul \{ops}"
    Fdiv => "fdiv \{ops}"
    Fmin => "fmin \{ops}"
    Fmax => "fmax \{ops}"

    // Floating point comparisons
    Fcmp(cc) => "fcmp.\{format_floatcc(cc)} \{ops}"

    // Floating point unary
    Fneg => "fneg \{ops}"
    Fabs => "fabs \{ops}"
    Fsqrt => "fsqrt \{ops}"
    Fceil => "fceil \{ops}"
    Ffloor => "ffloor \{ops}"
    Ftrunc => "ftrunc \{ops}"
    Fnearest => "fnearest \{ops}"

    // Conversions
    Ireduce => "ireduce \{ops}"
    Sextend => "sextend \{ops}"
    Uextend => "uextend \{ops}"
    Fpromote => "fpromote \{ops}"
    Fdemote => "fdemote \{ops}"
    FcvtToSint => "fcvt_to_sint \{ops}"
    FcvtToUint => "fcvt_to_uint \{ops}"
    SintToFcvt => "sint_to_fcvt \{ops}"
    UintToFcvt => "uint_to_fcvt \{ops}"
    Bitcast => "bitcast \{ops}"

    // Memory operations
    Load(ty, offset) => "load.\{format_type(ty)} \{ops} +\{offset}"
    Store(ty, offset) => "store.\{format_type(ty)} \{ops} +\{offset}"
    // Narrow load operations (8/16/32-bit with sign/zero extension)
    Load8S(ty, offset) => "load8_s.\{format_type(ty)} \{ops} +\{offset}"
    Load8U(ty, offset) => "load8_u.\{format_type(ty)} \{ops} +\{offset}"
    Load16S(ty, offset) => "load16_s.\{format_type(ty)} \{ops} +\{offset}"
    Load16U(ty, offset) => "load16_u.\{format_type(ty)} \{ops} +\{offset}"
    Load32S(offset) => "load32_s \{ops} +\{offset}"
    Load32U(offset) => "load32_u \{ops} +\{offset}"
    // Narrow store operations (8/16/32-bit)
    Store8(offset) => "store8 \{ops} +\{offset}"
    Store16(offset) => "store16 \{ops} +\{offset}"
    Store32(offset) => "store32 \{ops} +\{offset}"

    // Memory management
    MemoryGrow(max_pages) =>
      match max_pages {
        Some(max) => "memory_grow \{ops} max=\{max}"
        None => "memory_grow \{ops}"
      }
    MemorySize => "memory_size"

    // Misc
    Select => "select \{ops}"
    Copy => "copy \{ops}"

    // Table operations
    TableGet(idx) => "table_get \{idx} \{ops}"
    TableSet(idx) => "table_set \{idx} \{ops}"

    // Function calls
    Call(idx) => "call \{idx}(\{ops})"
    CallIndirect(type_idx, table_idx) =>
      "call_indirect type=\{type_idx} table=\{table_idx}(\{ops})"
  }
}

///|
/// Print an instruction
fn format_inst(inst : Inst) -> String {
  let opcode_str = format_opcode(inst.opcode, inst.operands)
  if inst.result is Some(r) {
    // Check for extra results (multi-value returns)
    if inst.extra_results.length() > 0 {
      let all_results = [format_value(r) + ":" + format_type(r.ty)]
      for extra in inst.extra_results {
        all_results.push(format_value(extra) + ":" + format_type(extra.ty))
      }
      let results_str = all_results.join(", ")
      "(\{results_str}) = \{opcode_str}"
    } else {
      "\{format_value(r)}:\{format_type(r.ty)} = \{opcode_str}"
    }
  } else {
    opcode_str
  }
}

///|
/// Print a terminator
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
    Brz(cond, then_block, else_block) =>
      "brz \{format_value(cond)}, block\{then_block}, block\{else_block}"
    Brnz(cond, then_block, else_block) =>
      "brnz \{format_value(cond)}, block\{then_block}, block\{else_block}"
    BrTable(index, targets, default_target) => {
      let targets_str = targets.map(fn(t) { "block\{t}" }).join(", ")
      "br_table \{format_value(index)}, [\{targets_str}], block\{default_target}"
    }
    Return(values) => {
      let vals_str = values.map(format_value).join(", ")
      if values.length() > 0 {
        "return \{vals_str}"
      } else {
        "return"
      }
    }
    Trap(reason) => "trap \"\{reason}\""
  }
}

///|
/// Print a basic block
fn format_block(block : Block) -> String {
  let sb = StringBuilder::new()
  // Block header with parameters
  if block.params.length() > 0 {
    let params_str = block.params
      .map(fn(p) {
        let (v, ty) = p
        "\{format_value(v)}:\{format_type(ty)}"
      })
      .join(", ")
    sb.write_string("block\{block.id}(\{params_str}):\n")
  } else {
    sb.write_string("block\{block.id}:\n")
  }
  // Instructions
  for inst in block.instructions {
    sb.write_string("    \{format_inst(inst)}\n")
  }
  // Terminator
  match block.terminator {
    Some(term) => sb.write_string("    \{format_terminator(term)}\n")
    None => sb.write_string("    ; (no terminator)\n")
  }
  sb.to_string()
}

///|
/// Print a function
pub fn Function::print(self : Function) -> String {
  let sb = StringBuilder::new()
  // Function signature
  let params_str = self.params
    .map(fn(p) {
      let (v, ty) = p
      "\{format_value(v)}:\{format_type(ty)}"
    })
    .join(", ")
  let results_str = self.results.map(format_type).join(", ")
  if self.results.length() > 0 {
    sb.write_string(
      "function \{self.name}(\{params_str}) -> \{results_str} {\n",
    )
  } else {
    sb.write_string("function \{self.name}(\{params_str}) {\n")
  }
  // Blocks
  for block in self.blocks {
    sb.write_string(format_block(block))
  }
  sb.write_string("}\n")
  sb.to_string()
}

///|
/// Print using IRBuilder
pub fn IRBuilder::print(self : IRBuilder) -> String {
  self.func.print()
}
