///|
fn Type::to_milkir(self : Type) -> @milkir.Type {
  match self {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    FuncRef | ExternRef => Ref
  }
}

///|
fn IntCC::to_milkir(self : IntCC) -> @milkir.IntCC {
  match self {
    Eq => Eq
    Ne => Ne
    Slt => Slt
    Sle => Sle
    Sgt => Sgt
    Sge => Sge
    Ult => Ult
    Ule => Ule
    Ugt => Ugt
    Uge => Uge
  }
}

///|
fn FloatCC::to_milkir(self : FloatCC) -> @milkir.FloatCC {
  match self {
    Eq => Eq
    Ne => Ne
    Lt => Lt
    Le => Le
    Gt => Gt
    Ge => Ge
  }
}

///|
fn custom_opcode_name(opcode : Opcode) -> String {
  "wasmoon." + @types.compact_show_repr(to_repr(opcode).to_string())
}

///|
fn Opcode::to_milkir(self : Opcode) -> @milkir.Opcode {
  match self {
    Iconst(n) => Iconst(n)
    Fconst(n) => Fconst(n)
    Iadd => Iadd
    Isub => Isub
    Imul => Imul
    Umulh => Umulh
    Smulh => Smulh
    Sdiv => Sdiv
    Udiv => Udiv
    Srem => Srem
    Urem => Urem
    Band => Band
    Bor => Bor
    Bxor => Bxor
    Bnot => Bnot
    Ishl => Ishl
    Sshr => Sshr
    Ushr => Ushr
    Rotl => Rotl
    Rotr => Rotr
    Clz => Clz
    Ctz => Ctz
    Popcnt => Popcnt
    Icmp(cc) => Icmp(cc.to_milkir())
    Fadd => Fadd
    Fsub => Fsub
    Fmul => Fmul
    Fdiv => Fdiv
    Fmin => Fmin
    Fmax => Fmax
    Fcmp(cc) => Fcmp(cc.to_milkir())
    Fneg => Fneg
    Fabs => Fabs
    Fsqrt => Fsqrt
    Fceil => Fceil
    Ffloor => Ffloor
    Ftrunc => Ftrunc
    Fnearest => Fnearest
    Ireduce => Ireduce
    Sextend => Sextend
    Uextend => Uextend
    Fpromote => Fpromote
    Fdemote => Fdemote
    FcvtToSint => FcvtToSint
    FcvtToUint => FcvtToUint
    FcvtToSintSat => FcvtToSintSat
    FcvtToUintSat => FcvtToUintSat
    SintToFcvt => SintToFcvt
    UintToFcvt => UintToFcvt
    Bitcast => Bitcast
    Sextend8 => Sextend8
    Sextend16 => Sextend16
    Sextend32 => Sextend32
    Select => Select
    Copy => Copy
    LoadPtr(ty) => LoadPtr(ty.to_milkir())
    StorePtr(ty) => StorePtr(ty.to_milkir())
    Call(idx) => Call(@milkir.ExternalSymbol::new("wasm.func.\{idx}"))
    CallPtr(num_args, num_results) => CallPtr(num_args, num_results)
    opcode => Custom(custom_opcode_name(opcode))
  }
}

///|
fn Value::to_milkir_with_context(
  self : Value,
  drop_legacy_vmctx : Bool,
  overrides : @hashmap.HashMap[Int, @milkir.Type],
) -> @milkir.Value {
  let id = if drop_legacy_vmctx { self.id - 1 } else { self.id }
  let ty = match overrides.get(self.id) {
    Some(ty) => ty
    None => self.ty.to_milkir()
  }
  { id, ty }
}

///|
fn Terminator::to_milkir(
  self : Terminator,
  drop_legacy_vmctx : Bool,
  overrides : @hashmap.HashMap[Int, @milkir.Type],
) -> @milkir.Terminator {
  match self {
    Jump(target, args) =>
      Jump(
        target,
        args.map(fn(value) {
          value.to_milkir_with_context(drop_legacy_vmctx, overrides)
        }),
      )
    Brz(cond, true_target, false_target) =>
      Brz(
        cond.to_milkir_with_context(drop_legacy_vmctx, overrides),
        true_target,
        false_target,
      )
    Brnz(cond, true_target, false_target) =>
      Brnz(
        cond.to_milkir_with_context(drop_legacy_vmctx, overrides),
        true_target,
        false_target,
      )
    BrTable(index, targets, default_target) =>
      BrTable(
        index.to_milkir_with_context(drop_legacy_vmctx, overrides),
        targets,
        default_target,
      )
    Return(values) =>
      Return(
        values.map(fn(value) {
          value.to_milkir_with_context(drop_legacy_vmctx, overrides)
        }),
      )
    Trap(reason) => TrapExit(reason)
  }
}

///|
fn Inst::to_milkir(
  self : Inst,
  id : Int,
  drop_legacy_vmctx : Bool,
  overrides : @hashmap.HashMap[Int, @milkir.Type],
) -> @milkir.Inst {
  @milkir.Inst::new(
    id,
    self.opcode.to_milkir(),
    self.operands.map(fn(value) {
      value.to_milkir_with_context(drop_legacy_vmctx, overrides)
    }),
    self.results.map(fn(value) {
      value.to_milkir_with_context(drop_legacy_vmctx, overrides)
    }),
  )
}

///|
fn Function::default_milkir_signature(self : Function) -> @milkir.Signature {
  @milkir.Signature::new(
    self.params.map(fn(param) {
      let (_, ty) = param
      ty.to_milkir()
    }),
    self.results.map(fn(ty) { ty.to_milkir() }),
  )
}

///|
fn Function::param_type_overrides(
  self : Function,
  signature : @milkir.Signature,
  drop_legacy_vmctx : Bool,
) -> @hashmap.HashMap[Int, @milkir.Type] {
  let overrides : @hashmap.HashMap[Int, @milkir.Type] = HashMap([])
  let old_start = if drop_legacy_vmctx { 1 } else { 0 }
  let available = self.params.length() - old_start
  let n = if available < signature.params.length() {
    available
  } else {
    signature.params.length()
  }
  for i in 0..<n {
    let (value, _) = self.params[i + old_start]
    overrides.set(value.id, signature.params[i])
  }
  overrides
}

///|
fn Function::max_value_id(self : Function) -> Int {
  let mut max_id = -1
  for param in self.params {
    let (value, _) = param
    if value.id > max_id {
      max_id = value.id
    }
  }
  for block in self.blocks {
    for param in block.params {
      let (value, _) = param
      if value.id > max_id {
        max_id = value.id
      }
    }
    for inst in block.instructions {
      for value in inst.results {
        if value.id > max_id {
          max_id = value.id
        }
      }
    }
  }
  max_id
}

///|
fn Function::drops_legacy_vmctx(
  self : Function,
  signature : @milkir.Signature,
) -> Bool {
  self.params.length() > 0 &&
  signature.params.length() + 1 == self.params.length()
}

///|
pub fn Function::to_milkir_with_signature(
  self : Function,
  signature : @milkir.Signature,
) -> @milkir.Function {
  let drop_legacy_vmctx = self.drops_legacy_vmctx(signature)
  let overrides = self.param_type_overrides(signature, drop_legacy_vmctx)
  let out = @milkir.Function::new(self.name, signature)
  let mut inst_id = 0
  for block in self.blocks {
    let out_block = @milkir.Block::new(
      block.id,
      block.params.map(fn(param) {
        let (value, _) = param
        value.to_milkir_with_context(drop_legacy_vmctx, overrides)
      }),
    )
    for inst in block.instructions {
      out_block.append_inst(
        inst.to_milkir(inst_id, drop_legacy_vmctx, overrides),
      )
      inst_id = inst_id + 1
    }
    if block.terminator is Some(term) {
      out_block.set_terminator(term.to_milkir(drop_legacy_vmctx, overrides))
    }
    out.blocks.push(out_block)
  }
  out.next_inst_id = inst_id
  out.next_block_id = self.next_block_id
  out.next_value_id = if drop_legacy_vmctx {
    self.max_value_id()
  } else {
    self.max_value_id() + 1
  }
  out
}

///|
pub fn Function::to_milkir(self : Function) -> @milkir.Function {
  self.to_milkir_with_signature(self.default_milkir_signature())
}
