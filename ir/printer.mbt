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
/// result_ty is needed for Fconst to correctly decode F32 bit-packed constants
fn format_opcode(
  opcode : Opcode,
  operands : Array[Value],
  result_ty : Type?,
) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    // Constants
    Iconst(n) => "iconst \{n}"
    Fconst(n) =>
      // For F32, the bits are packed in the lower 32 bits of the Double
      if result_ty is Some(F32) {
        let f32_bits = n.reinterpret_as_int64().to_int()
        let f32_val = Float::reinterpret_from_int(f32_bits)
        "fconst \{f32_val}"
      } else {
        "fconst \{n}"
      }

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
    FcvtToSintSat => "fcvt_to_sint_sat \{ops}"
    FcvtToUintSat => "fcvt_to_uint_sat \{ops}"
    SintToFcvt => "sint_to_fcvt \{ops}"
    UintToFcvt => "uint_to_fcvt \{ops}"
    Bitcast => "bitcast \{ops}"

    // In-place sign extension
    Sextend8 => "sextend8 \{ops}"
    Sextend16 => "sextend16 \{ops}"
    Sextend32 => "sextend32 \{ops}"

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
    MemoryFill => "memory_fill \{ops}"
    MemoryCopy => "memory_copy \{ops}"

    // Misc
    Select => "select \{ops}"
    Copy => "copy \{ops}"

    // Table operations
    TableGet(idx) => "table_get \{idx} \{ops}"
    TableSet(idx) => "table_set \{idx} \{ops}"
    TableSize(idx) => "table_size \{idx}"
    TableGrow(idx) => "table_grow \{idx} \{ops}"

    // Global operations
    GlobalGet(idx) => "global_get \{idx}"
    GlobalSet(idx) => "global_set \{idx} \{ops}"

    // Function calls
    Call(idx) => "call \{idx}(\{ops})"
    CallIndirect(type_idx, table_idx) =>
      "call_indirect type=\{type_idx} table=\{table_idx}(\{ops})"
    CallRef(type_idx) => "call_ref type=\{type_idx}(\{ops})"
    ReturnCall(idx) => "return_call \{idx}(\{ops})"
    ReturnCallIndirect(type_idx, table_idx) =>
      "return_call_indirect type=\{type_idx} table=\{table_idx}(\{ops})"
    ReturnCallRef(type_idx) => "return_call_ref type=\{type_idx}(\{ops})"

    // Raw pointer operations (for trampolines)
    LoadPtr(ty) => "load_ptr.\{ty} \{ops}"
    StorePtr(ty) => "store_ptr.\{ty} \{ops}"
    CallPtr(num_args, num_results) =>
      "call_ptr(\{num_args}) -> \{num_results} (\{ops})"

    // GC operations - struct
    StructNew(type_idx) => "struct.new \{type_idx}(\{ops})"
    StructNewDefault(type_idx) => "struct.new_default \{type_idx}"
    StructGet(type_idx, field_idx) =>
      "struct.get \{type_idx} \{field_idx} \{ops}"
    StructGetS(type_idx, field_idx) =>
      "struct.get_s \{type_idx} \{field_idx} \{ops}"
    StructGetU(type_idx, field_idx) =>
      "struct.get_u \{type_idx} \{field_idx} \{ops}"
    StructSet(type_idx, field_idx) =>
      "struct.set \{type_idx} \{field_idx} \{ops}"

    // GC operations - array
    ArrayNew(type_idx) => "array.new \{type_idx}(\{ops})"
    ArrayNewDefault(type_idx) => "array.new_default \{type_idx}(\{ops})"
    ArrayNewFixed(type_idx, len) => "array.new_fixed \{type_idx} \{len}(\{ops})"
    ArrayGet(type_idx) => "array.get \{type_idx} \{ops}"
    ArrayGetS(type_idx) => "array.get_s \{type_idx} \{ops}"
    ArrayGetU(type_idx) => "array.get_u \{type_idx} \{ops}"
    ArraySet(type_idx) => "array.set \{type_idx} \{ops}"
    ArrayLen => "array.len \{ops}"
    ArrayFill(type_idx) => "array.fill \{type_idx} \{ops}"
    ArrayCopy(dst_type_idx, src_type_idx) =>
      "array.copy \{dst_type_idx} \{src_type_idx} \{ops}"

    // GC operations - i31
    I31New => "ref.i31 \{ops}"
    I31GetS => "i31.get_s \{ops}"
    I31GetU => "i31.get_u \{ops}"

    // GC operations - type checking/casting
    RefTest(type_idx, nullable) =>
      if nullable {
        "ref.test_null \{type_idx} \{ops}"
      } else {
        "ref.test \{type_idx} \{ops}"
      }
    RefCast(type_idx, nullable) =>
      if nullable {
        "ref.cast_null \{type_idx} \{ops}"
      } else {
        "ref.cast \{type_idx} \{ops}"
      }

    // GC operations - type conversions
    AnyConvertExtern => "any.convert_extern \{ops}"
    ExternConvertAny => "extern.convert_any \{ops}"
  }
}

///|
/// Print an instruction
fn format_inst(inst : Inst) -> String {
  let result_ty = inst.result.map(v => v.ty)
  let opcode_str = format_opcode(inst.opcode, inst.operands, result_ty)
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
