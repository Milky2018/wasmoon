// IR to MachV lowering
// Converts high-level SSA IR to low-level MachV representation
//
// This is the instruction selection phase that:
// 1. Maps IR values to virtual registers
// 2. Converts IR opcodes to MachV opcodes
// 3. Handles control flow translation
// 4. Performs pattern matching for AArch64-specific instructions

///|
/// Lowering context - tracks state during IR to MachV conversion
struct LoweringContext {
  ir_func : @milkir.Function
  machv_func : @machv.Function
  isa : @isa.ISA
  abi_settings : @abi.ABISettings
  embedding_reg_roles : @abi.EmbeddingRegRoles
  embedding_context_layout : @abi.EmbeddingContextLayout?
  call_conv_layout : @abi.CallConventionLayout?
  external_helper_symbols : Map[String, String]
  trap_payload_resolver : (String) -> Int
  extension_lowerer : ((
    LoweringContext,
    @milkir.Inst,
    @block.MachVBlock,
    @milkir.ExtOp,
  ) -> Bool)?
  num_imports : Int
  // Dense map from IR Value id to @abi.VReg (Cranelift SecondaryMap style).
  value_map_dense : Array[@abi.VReg?]
  // Map from IR Block id to MachV block id
  block_map : Map[Int, Int]
  // Map from IR Value id to stack param index (for params >= 8)
  stack_param_map : Map[Int, (Int, @abi.RegClass)]
  // Cache of embedding-context-derived pointers keyed by extension-defined id.
  // Cleared at block boundaries and invalidated at call sites.
  context_pointer_cache : Map[Int, @abi.VReg]
  // Icmp result value IDs exclusively used by Select/branch and fused in lowering.
  fused_icmps_dense : Array[Bool]
  // Values that should not be lowered because they are subsumed by fused lowering.
  skipped_values_dense : Array[Bool]
  // Use counts for IR values (dense table, Cranelift SecondaryMap-style).
  use_counts : Array[Int]
  // Value-id keyed defining instruction table (dense, Cranelift-style).
  def_inst_table : Array[@milkir.Inst?]
}

///|
fn function_params_for_lowering(
  ir_func : @milkir.Function,
) -> Array[(@milkir.Value, @milkir.Type)] {
  if ir_func.params.length() > 0 {
    return ir_func.params
  }
  let params : Array[(@milkir.Value, @milkir.Type)] = []
  for i, ty in ir_func.signature.params {
    let value : @milkir.Value = { id: i, ty }
    params.push((value, ty))
  }
  params
}

///|
pub fn LoweringContext::new(
  ir_func : @milkir.Function,
  isa : @isa.ISA,
  abi_settings : @abi.ABISettings,
  embedding_reg_roles : @abi.EmbeddingRegRoles,
  embedding_context_layout : @abi.EmbeddingContextLayout?,
  call_conv_layout : @abi.CallConventionLayout?,
  external_helper_symbols : Map[String, String],
  trap_payload_resolver : (String) -> Int,
  extension_lowerer : ((
    LoweringContext,
    @milkir.Inst,
    @block.MachVBlock,
    @milkir.ExtOp,
  ) -> Bool)?,
  num_imports : Int,
) -> LoweringContext {
  let use_counts = compute_use_counts(ir_func)
  let def_inst_table : Array[@milkir.Inst?] = []
  fn ensure_def_slot(table : Array[@milkir.Inst?], value_id : Int) -> Unit {
    if value_id < 0 {
      return
    }
    while table.length() <= value_id {
      table.push(None)
    }
  }
  for block in ir_func.blocks {
    for inst in block.instructions {
      if inst.first_result() is Some(result) {
        ensure_def_slot(def_inst_table, result.id)
        def_inst_table[result.id] = Some(inst)
      }
    }
  }
  {
    ir_func,
    machv_func: @machv.Function::new(ir_func.name),
    isa,
    abi_settings,
    embedding_reg_roles,
    embedding_context_layout,
    call_conv_layout,
    external_helper_symbols,
    trap_payload_resolver,
    extension_lowerer,
    num_imports,
    value_map_dense: Array::make(ir_func.next_value_id, None),
    block_map: {},
    stack_param_map: {},
    context_pointer_cache: {},
    fused_icmps_dense: Array::make(ir_func.next_value_id, false),
    skipped_values_dense: Array::make(ir_func.next_value_id, false),
    use_counts,
    def_inst_table,
  }
}

///|
fn LoweringContext::require_embedding_context_layout(
  self : LoweringContext,
) -> @abi.EmbeddingContextLayout {
  match self.embedding_context_layout {
    Some(layout) => layout
    None =>
      abort(
        "embedding context layout is required for context-specific lowering",
      )
  }
}

///|
pub fn LoweringContext::embedding_context_layout(
  self : LoweringContext,
) -> @abi.EmbeddingContextLayout {
  self.require_embedding_context_layout()
}

///|
fn LoweringContext::require_call_conv_layout(
  self : LoweringContext,
) -> @abi.CallConventionLayout {
  match self.call_conv_layout {
    Some(layout) => layout
    None =>
      abort("call convention layout is required for ABI-specific lowering")
  }
}

///|
pub fn LoweringContext::call_conv_layout(
  self : LoweringContext,
) -> @abi.CallConventionLayout {
  self.require_call_conv_layout()
}

///|
pub fn LoweringContext::machv_function(
  self : LoweringContext,
) -> @machv.Function {
  self.machv_func
}

///|
pub fn LoweringContext::abi_settings(
  self : LoweringContext,
) -> @abi.ABISettings {
  self.abi_settings
}

///|
pub fn LoweringContext::embedding_reg_roles(
  self : LoweringContext,
) -> @abi.EmbeddingRegRoles {
  self.embedding_reg_roles
}

///|
pub fn LoweringContext::num_imports(self : LoweringContext) -> Int {
  self.num_imports
}

///|
fn LoweringContext::trap_payload(
  self : LoweringContext,
  reason : String,
) -> Int {
  (self.trap_payload_resolver)(reason)
}

///|
fn LoweringContext::get_cached_vreg(
  self : LoweringContext,
  value_id : Int,
) -> @abi.VReg? {
  if value_id >= 0 && value_id < self.value_map_dense.length() {
    return self.value_map_dense[value_id]
  }
  None
}

///|
pub fn LoweringContext::set_cached_vreg(
  self : LoweringContext,
  value_id : Int,
  vreg : @abi.VReg,
) -> Unit {
  if value_id >= 0 {
    while self.value_map_dense.length() <= value_id {
      self.value_map_dense.push(None)
    }
    self.value_map_dense[value_id] = Some(vreg)
  }
}

///|
fn LoweringContext::is_skipped_value(
  self : LoweringContext,
  value_id : Int,
) -> Bool {
  if value_id >= 0 && value_id < self.skipped_values_dense.length() {
    self.skipped_values_dense[value_id]
  } else {
    false
  }
}

///|
fn LoweringContext::is_fused_icmp_result(
  self : LoweringContext,
  value_id : Int,
) -> Bool {
  if value_id >= 0 && value_id < self.fused_icmps_dense.length() {
    self.fused_icmps_dense[value_id]
  } else {
    false
  }
}

///|
pub fn LoweringContext::use_count(
  self : LoweringContext,
  value_id : Int,
) -> Int {
  use_count(self.use_counts, value_id)
}

///|
pub fn LoweringContext::cached_context_pointer(
  self : LoweringContext,
  key : Int,
) -> @abi.VReg? {
  self.context_pointer_cache.get(key)
}

///|
pub fn LoweringContext::cache_context_pointer(
  self : LoweringContext,
  key : Int,
  vreg : @abi.VReg,
) -> Unit {
  self.context_pointer_cache.set(key, vreg)
}

///|
/// Invalidate cached embedding-context-derived pointers in lowering context.
pub fn invalidate_context_pointer_cache(ctx : LoweringContext) -> Unit {
  ctx.context_pointer_cache.clear()
}

///|
/// Materialize `base + offset` for address lowering.
///
/// Cranelift's AArch64 `amode_add` lowering emits this adjustment as part of
/// each amode construction rather than caching adjusted bases globally.
fn get_adjusted_base_with_offset(
  ctx : LoweringContext,
  block : @block.MachVBlock,
  base : @abi.VReg,
  offset : Int64,
) -> @abi.VReg {
  if offset == 0L {
    return base
  }
  let isa = ctx.isa
  let result = ctx.machv_func.new_vreg(Int)
  if offset > 0L && is_valid_add_sub_imm_for_isa(isa, offset) {
    let add_inst = @instr.MachVInst::new(AddImm(offset.to_int(), true))
    add_inst.add_def({ reg: Virtual(result) })
    add_inst.add_use(Virtual(base))
    block.add_inst(add_inst)
    return result
  }
  if offset < 0L && is_valid_add_sub_imm_for_isa(isa, -offset) {
    let sub_inst = @instr.MachVInst::new(SubImm((-offset).to_int(), true))
    sub_inst.add_def({ reg: Virtual(result) })
    sub_inst.add_use(Virtual(base))
    block.add_inst(sub_inst)
    return result
  }
  let imm_vreg = materialize_imm(ctx, block, offset)
  let add_inst = @instr.MachVInst::new(Add(true))
  add_inst.add_def({ reg: Virtual(result) })
  add_inst.add_use(Virtual(base))
  add_inst.add_use(Virtual(imm_vreg))
  block.add_inst(add_inst)
  result
}

///|
/// Materialize `index + offset` for register-offset addressing on AArch64.
///
/// V8's arm64 load/store lowering canonicalizes memory ops to `(base + index)`,
/// and keeps constant displacements on the index side when possible.
/// We mirror this for `uxtw`/unscaled addressing to reduce pressure on base
/// temporaries and improve generated shape for Wasm memory hot paths.
fn get_adjusted_regoff_index_with_offset(
  ctx : LoweringContext,
  block : @block.MachVBlock,
  index : @abi.VReg,
  ext : @instr.IndexExtend,
  shift : Int,
  offset : Int64,
) -> (@abi.VReg, @instr.IndexExtend)? {
  if offset == 0L {
    return Some((index, ext))
  }
  if shift != 0 {
    return None
  }
  // Keep extend-based addressing (`uxtw`/`sxtw`) untouched. Pre-adjusting the
  // index before the extend can change semantics via 32-bit wraparound.
  //
  // We only adjust already-64-bit index forms (`Ext::None`).
  let (is_i32_index, new_ext) = if ext is None {
    (false, @instr.IndexExtend::None)
  } else {
    return None
  }
  let isa = ctx.isa
  let result = ctx.machv_func.new_vreg(Int)
  if offset > 0L && is_valid_add_sub_imm_for_isa(isa, offset) {
    let add_inst = @instr.MachVInst::new(AddImm(offset.to_int(), !is_i32_index))
    add_inst.add_def({ reg: Virtual(result) })
    add_inst.add_use(Virtual(index))
    block.add_inst(add_inst)
    return Some((result, new_ext))
  }
  if offset < 0L && is_valid_add_sub_imm_for_isa(isa, -offset) {
    let sub_inst = @instr.MachVInst::new(
      SubImm((-offset).to_int(), !is_i32_index),
    )
    sub_inst.add_def({ reg: Virtual(result) })
    sub_inst.add_use(Virtual(index))
    block.add_inst(sub_inst)
    return Some((result, new_ext))
  }
  let imm_vreg = materialize_imm(ctx, block, offset)
  let add_inst = @instr.MachVInst::new(Add(!is_i32_index))
  add_inst.add_def({ reg: Virtual(result) })
  add_inst.add_use(Virtual(index))
  add_inst.add_use(Virtual(imm_vreg))
  block.add_inst(add_inst)
  Some((result, new_ext))
}

///|
/// Pre-compute values that should be skipped during lowering because they are subsumed
/// by a fused instruction selection rule.
///
/// This mirrors Cranelift ISLE lowering rules like:
/// - iadd x (ishl y (iconst k)) => add_shift
/// - iadd x (imul y z) => madd
/// - isub x (imul y z) => msub
fn compute_skipped_values(ctx : LoweringContext) -> Array[Bool] {
  let skipped_dense : Array[Bool] = Array::make(
    ctx.ir_func.next_value_id,
    false,
  )
  let addrmode_skipped_dense : Array[Bool] = Array::make(
    ctx.ir_func.next_value_id,
    false,
  )
  let addrmode_subsumed_counts : Array[Int] = Array::make(
    ctx.ir_func.next_value_id,
    0,
  )
  let is_amd64 = ctx.isa is AMD64
  let is_aarch64 = ctx.isa is AArch64
  let enable_subextend_fusion = true

  fn ensure_bool_slot(arr : Array[Bool], idx : Int) -> Unit {
    if idx < 0 {
      return
    }
    while arr.length() <= idx {
      arr.push(false)
    }
  }

  fn ensure_count_slot(arr : Array[Int], idx : Int) -> Unit {
    if idx < 0 {
      return
    }
    while arr.length() <= idx {
      arr.push(0)
    }
  }

  fn mark_skipped(value_id : Int) -> Unit {
    if value_id < 0 {
      return
    }
    ensure_bool_slot(skipped_dense, value_id)
    skipped_dense[value_id] = true
  }

  fn is_addrmode_skipped(value_id : Int) -> Bool {
    value_id >= 0 &&
    value_id < addrmode_skipped_dense.length() &&
    addrmode_skipped_dense[value_id]
  }

  fn mark_addrmode_subsumed_use(value_id : Int) -> Unit {
    if value_id < 0 {
      return
    }
    ensure_count_slot(addrmode_subsumed_counts, value_id)
    addrmode_subsumed_counts[value_id] = addrmode_subsumed_counts[value_id] + 1
  }

  // Pass 1: find address values that will be subsumed by load/store lowering.
  for block in ctx.ir_func.blocks {
    for inst in block.instructions {
      match inst.opcode {
        LoadPtr(ty) => {
          guard inst.operands.length() >= 1 else { continue }
          let base_value = inst.operands[0]
          let access_size = match ty {
            I32 | F32 => 4
            I64 | F64 | Ptr | Ref | FuncRef | ExternRef => 8
            V128 => 16
          }
          let explicit_offset = if inst.operands.length() > 1 {
            if find_defining_inst(ctx, inst.operands[1]) is Some(def_inst) &&
              def_inst.opcode is Iconst(off) {
              off
            } else {
              0L
            }
          } else {
            0L
          }
          let mut matched = false
          if (ty is I32 || ty is I64) &&
            match_addr_reg_offset(ctx, base_value, access_size)
            is Some((_, am_index, _, shift, subsumed, extra_offset, has_extra)) &&
            (!is_amd64 || (shift >= 0 && shift <= 3)) {
            let effective_offset = explicit_offset + extra_offset
            if (is_amd64 || effective_offset == 0L || has_extra) &&
              prefer_reg_offset_for_index(
                ctx, am_index, access_size, explicit_offset, extra_offset, has_extra,
              ) {
              mark_addrmode_subsumed_use(base_value.id)
              for value_id in subsumed {
                mark_addrmode_subsumed_use(value_id)
              }
              matched = true
            }
          }
          if !matched &&
            match_iadd_const(ctx, base_value) is Some((_, addr_offset)) {
            let combined = explicit_offset + addr_offset
            if is_valid_load_store_offset(ctx, combined, access_size) {
              mark_addrmode_subsumed_use(base_value.id)
            }
          }
        }
        StorePtr(ty) => {
          guard inst.operands.length() >= 2 else { continue }
          let base_value = inst.operands[0]
          let access_size = match ty {
            I32 | F32 => 4
            I64 | F64 | Ptr | Ref | FuncRef | ExternRef => 8
            V128 => 16
          }
          let explicit_offset = if inst.operands.length() > 2 {
            if find_defining_inst(ctx, inst.operands[2]) is Some(def_inst) &&
              def_inst.opcode is Iconst(off) {
              off
            } else {
              0L
            }
          } else {
            0L
          }
          let mut matched = false
          if (ty is I32 || ty is I64) &&
            match_addr_reg_offset(ctx, base_value, access_size)
            is Some((_, am_index, _, shift, subsumed, extra_offset, has_extra)) &&
            (!is_amd64 || (shift >= 0 && shift <= 3)) {
            let effective_offset = explicit_offset + extra_offset
            if (is_amd64 || effective_offset == 0L || has_extra) &&
              prefer_reg_offset_for_index(
                ctx, am_index, access_size, explicit_offset, extra_offset, has_extra,
              ) {
              mark_addrmode_subsumed_use(base_value.id)
              for value_id in subsumed {
                mark_addrmode_subsumed_use(value_id)
              }
              matched = true
            }
          }
          if !matched &&
            match_iadd_const(ctx, base_value) is Some((_, addr_offset)) {
            let combined = explicit_offset + addr_offset
            if is_valid_load_store_offset(ctx, combined, access_size) {
              mark_addrmode_subsumed_use(base_value.id)
            }
          }
        }
        LoadPtrNarrow(_, bits, _) => {
          guard inst.operands.length() >= 1 else { continue }
          let base_value = inst.operands[0]
          let access_size = bits / 8
          let explicit_offset = if inst.operands.length() > 1 {
            if find_defining_inst(ctx, inst.operands[1]) is Some(def_inst) &&
              def_inst.opcode is Iconst(off) {
              off
            } else {
              0L
            }
          } else {
            0L
          }
          let mut matched = false
          if (is_aarch64 || is_amd64) &&
            match_addr_reg_offset(ctx, base_value, access_size)
            is Some((_, am_index, _, shift, subsumed, extra_offset, has_extra)) &&
            (!is_amd64 || (shift >= 0 && shift <= 3)) {
            let effective_offset = explicit_offset + extra_offset
            if (is_amd64 || effective_offset == 0L || has_extra) &&
              prefer_reg_offset_for_index(
                ctx, am_index, access_size, explicit_offset, extra_offset, has_extra,
              ) {
              mark_addrmode_subsumed_use(base_value.id)
              for value_id in subsumed {
                mark_addrmode_subsumed_use(value_id)
              }
              matched = true
            }
          }
          if !matched &&
            match_iadd_const(ctx, base_value) is Some((_, addr_offset)) {
            let combined = explicit_offset + addr_offset
            if is_valid_load_store_offset(ctx, combined, access_size) {
              mark_addrmode_subsumed_use(base_value.id)
            }
          }
        }
        StorePtrNarrow(bits) => {
          guard inst.operands.length() >= 2 else { continue }
          let base_value = inst.operands[0]
          let access_size = bits / 8
          let explicit_offset = if inst.operands.length() > 2 {
            if find_defining_inst(ctx, inst.operands[2]) is Some(def_inst) &&
              def_inst.opcode is Iconst(off) {
              off
            } else {
              0L
            }
          } else {
            0L
          }
          let mut matched = false
          if (is_aarch64 || is_amd64) &&
            match_addr_reg_offset(ctx, base_value, access_size)
            is Some((_, am_index, _, shift, subsumed, extra_offset, has_extra)) &&
            (!is_amd64 || (shift >= 0 && shift <= 3)) {
            let effective_offset = explicit_offset + extra_offset
            if (is_amd64 || effective_offset == 0L || has_extra) &&
              prefer_reg_offset_for_index(
                ctx, am_index, access_size, explicit_offset, extra_offset, has_extra,
              ) {
              mark_addrmode_subsumed_use(base_value.id)
              for value_id in subsumed {
                mark_addrmode_subsumed_use(value_id)
              }
              matched = true
            }
          }
          if !matched &&
            match_iadd_const(ctx, base_value) is Some((_, addr_offset)) {
            let combined = explicit_offset + addr_offset
            if is_valid_load_store_offset(ctx, combined, access_size) {
              mark_addrmode_subsumed_use(base_value.id)
            }
          }
        }
        _ => ()
      }
    }
  }
  for value_id in 0..<addrmode_subsumed_counts.length() {
    let subsumed_count = addrmode_subsumed_counts[value_id]
    if subsumed_count > 0 &&
      use_count(ctx.use_counts, value_id) == subsumed_count {
      addrmode_skipped_dense[value_id] = true
    }
  }

  // Pass 2: skip single-use producers subsumed by fused instruction selection,
  // but avoid skipping them when their consumer value is itself addrmode-skipped.
  for block in ctx.ir_func.blocks {
    for inst in block.instructions {
      let is_i64 = inst.first_result() is Some(result) && result.ty is I64
      let is_shift_fusable_int = inst.first_result() is Some(result) &&
        (result.ty is I64 || result.ty is I32)
      match inst.opcode {
        Iadd => {
          if !is_shift_fusable_int {
            continue
          }
          if inst.first_result() is Some(r) && is_addrmode_skipped(r.id) {
            continue
          }
          // Mirror lower_iadd's fusion priority so we never skip both sides.
          // This matters for patterns like add(mul(a,b), mul(c,d)) where only one
          // multiply can be fused into a single MADD; the other must be materialized.
          let lhs = inst.operands[0]
          let rhs = inst.operands[1]
          if use_count(ctx.use_counts, rhs.id) == 1 &&
            match_mul_value(ctx, rhs) is Some(_) {
            mark_skipped(rhs.id)
            continue
          }
          if use_count(ctx.use_counts, lhs.id) == 1 &&
            match_mul_value(ctx, lhs) is Some(_) {
            mark_skipped(lhs.id)
            continue
          }
          if use_count(ctx.use_counts, rhs.id) == 1 &&
            match_shl_const_value(ctx, rhs) is Some(_) {
            mark_skipped(rhs.id)
            continue
          }
          if use_count(ctx.use_counts, lhs.id) == 1 &&
            match_shl_const_value(ctx, lhs) is Some(_) {
            mark_skipped(lhs.id)
            continue
          }
          if is_i64 &&
            use_count(ctx.use_counts, rhs.id) == 1 &&
            match_extend_i32_to_i64(ctx, rhs) is Some((_, ext)) &&
            !(ext is None) {
            mark_skipped(rhs.id)
            continue
          }
          if is_i64 &&
            use_count(ctx.use_counts, lhs.id) == 1 &&
            match_extend_i32_to_i64(ctx, lhs) is Some((_, ext)) &&
            !(ext is None) {
            mark_skipped(lhs.id)
            continue
          }
        }
        Isub => {
          if !is_shift_fusable_int {
            continue
          }
          if inst.first_result() is Some(r) && is_addrmode_skipped(r.id) {
            continue
          }
          let rhs = inst.operands[1]
          if use_count(ctx.use_counts, rhs.id) == 1 &&
            match_mul_value(ctx, rhs) is Some(_) {
            mark_skipped(rhs.id)
          }
          if use_count(ctx.use_counts, rhs.id) == 1 &&
            match_shl_const_value(ctx, rhs) is Some(_) {
            mark_skipped(rhs.id)
          }
          if enable_subextend_fusion &&
            is_i64 &&
            use_count(ctx.use_counts, rhs.id) == 1 &&
            match_extend_i32_to_i64(ctx, rhs) is Some((_, ext)) &&
            !(ext is None) {
            mark_skipped(rhs.id)
          }
        }
        Band | Bor | Bxor => {
          if !is_shift_fusable_int {
            continue
          }
          if inst.first_result() is Some(r) && is_addrmode_skipped(r.id) {
            continue
          }
          // Mirror lower_band/lower_bor/lower_bxor: fuse at most one shl const.
          let lhs = inst.operands[0]
          let rhs = inst.operands[1]
          // If this op will lower to a logical-immediate form (and/orr/eor immediate),
          // then no shift producer is subsumed. Skipping it would create an undefined vreg.
          let lhs_is_imm = match get_const_value(ctx, lhs) {
            Some(imm) =>
              @instr.aarch64_logic_imm_enc_bits(imm, is_i64) is Some(_)
            None => false
          }
          let rhs_is_imm = match get_const_value(ctx, rhs) {
            Some(imm) =>
              @instr.aarch64_logic_imm_enc_bits(imm, is_i64) is Some(_)
            None => false
          }
          if lhs_is_imm || rhs_is_imm {
            continue
          }
          if inst.opcode is Bor &&
            match_rotate_or_value(ctx, lhs, rhs, is_i64) is Some(_) {
            if use_count(ctx.use_counts, lhs.id) == 1 &&
              (
                match_shl_const_value(ctx, lhs) is Some(_) ||
                match_ushr_const_value(ctx, lhs) is Some(_)
              ) {
              mark_skipped(lhs.id)
            }
            if use_count(ctx.use_counts, rhs.id) == 1 &&
              (
                match_shl_const_value(ctx, rhs) is Some(_) ||
                match_ushr_const_value(ctx, rhs) is Some(_)
              ) {
              mark_skipped(rhs.id)
            }
            continue
          }
          if inst.opcode is Bor &&
            match_extr_or_value(ctx, lhs, rhs, is_i64) is Some(_) {
            if use_count(ctx.use_counts, lhs.id) == 1 &&
              (
                match_shl_const_value(ctx, lhs) is Some(_) ||
                match_ushr_const_value(ctx, lhs) is Some(_)
              ) {
              mark_skipped(lhs.id)
            }
            if use_count(ctx.use_counts, rhs.id) == 1 &&
              (
                match_shl_const_value(ctx, rhs) is Some(_) ||
                match_ushr_const_value(ctx, rhs) is Some(_)
              ) {
              mark_skipped(rhs.id)
            }
            continue
          }
          if use_count(ctx.use_counts, rhs.id) == 1 &&
            match_bnot_value(ctx, rhs) is Some(_) {
            mark_skipped(rhs.id)
            continue
          }
          if use_count(ctx.use_counts, lhs.id) == 1 &&
            match_bnot_value(ctx, lhs) is Some(_) {
            mark_skipped(lhs.id)
            continue
          }
          if use_count(ctx.use_counts, rhs.id) == 1 &&
            match_shl_const_value(ctx, rhs) is Some(_) {
            mark_skipped(rhs.id)
            continue
          }
          if use_count(ctx.use_counts, lhs.id) == 1 &&
            match_shl_const_value(ctx, lhs) is Some(_) {
            mark_skipped(lhs.id)
            continue
          }
        }
        _ => ()
      }
    }
  }
  for id in 0..<addrmode_skipped_dense.length() {
    if addrmode_skipped_dense[id] {
      ensure_bool_slot(skipped_dense, id)
      skipped_dense[id] = true
    }
  }
  skipped_dense
}

///|
/// Compute use counts for each IR value.
fn ensure_use_count_slot(use_counts : Array[Int], value_id : Int) -> Unit {
  if value_id < 0 {
    return
  }
  while use_counts.length() <= value_id {
    use_counts.push(0)
  }
}

///|
fn use_count(use_counts : Array[Int], value_id : Int) -> Int {
  if value_id >= 0 && value_id < use_counts.length() {
    use_counts[value_id]
  } else {
    0
  }
}

///|
/// Compute use counts for each IR value.
fn compute_use_counts(ir_func : @milkir.Function) -> Array[Int] {
  let use_counts : Array[Int] = []
  for block in ir_func.blocks {
    for inst in block.instructions {
      for op in inst.operands {
        ensure_use_count_slot(use_counts, op.id)
        use_counts[op.id] = use_counts[op.id] + 1
      }
    }
    // Also count uses in terminators
    if block.terminator is Some(term) {
      let term_uses = match term {
        Brz(cond, _, _) | Brnz(cond, _, _) => [cond]
        BrTable(index, _, _) => [index]
        Branch(cond, _, true_args, _, false_args) => {
          let values : Array[@milkir.Value] = [cond]
          for v in true_args {
            values.push(v)
          }
          for v in false_args {
            values.push(v)
          }
          values
        }
        Jump(_, args) | Return(args) => args
        Trap(_) | TrapExit(_) => []
      }
      for v in term_uses {
        ensure_use_count_slot(use_counts, v.id)
        use_counts[v.id] = use_counts[v.id] + 1
      }
    }
  }
  use_counts
}

///|
/// Compute which Icmp results are exclusively used by Select/branch and can be fused.
/// This allows lower_icmp to skip emitting redundant Cmp instructions.
fn compute_fused_icmps(
  ir_func : @milkir.Function,
  use_counts : Array[Int],
  def_inst_table : Array[@milkir.Inst?],
) -> Array[Bool] {
  fn is_single_use_icmp_result(
    use_counts : Array[Int],
    def_inst_table : Array[@milkir.Inst?],
    value : @milkir.Value,
  ) -> Bool {
    if use_count(use_counts, value.id) != 1 {
      return false
    }
    if value.id < 0 || value.id >= def_inst_table.length() {
      return false
    }
    match def_inst_table[value.id] {
      Some(def_inst) => def_inst.opcode is Icmp(_)
      None => false
    }
  }

  // Find Icmp results that have exactly one use in a Select or branch.
  let fused_dense : Array[Bool] = Array::make(ir_func.next_value_id, false)
  fn mark_fused(value_id : Int) -> Unit {
    if value_id < 0 {
      return
    }
    while fused_dense.length() <= value_id {
      fused_dense.push(false)
    }
    fused_dense[value_id] = true
  }
  for block in ir_func.blocks {
    for inst in block.instructions {
      // Check if this is a Select instruction
      if inst.opcode is Select {
        let cond = inst.operands[0]
        if is_single_use_icmp_result(use_counts, def_inst_table, cond) {
          mark_fused(cond.id)
        }
      }
    }
    match block.terminator {
      Some(Brz(cond, _, _)) | Some(Brnz(cond, _, _)) =>
        if is_single_use_icmp_result(use_counts, def_inst_table, cond) {
          mark_fused(cond.id)
        }
      _ => ()
    }
  }
  fused_dense
}

///|
/// Collect call result vregs, skipping all results if none are used.
pub fn collect_call_result_vregs(
  ctx : LoweringContext,
  inst : @milkir.Inst,
) -> Array[@abi.VReg] {
  let mut any_used = false
  for result in inst.all_results() {
    if use_count(ctx.use_counts, result.id) > 0 {
      any_used = true
      break
    }
  }
  let result_vregs : Array[@abi.VReg] = []
  if !any_used {
    return result_vregs
  }
  for result in inst.all_results() {
    result_vregs.push(ctx.get_vreg(result))
  }
  result_vregs
}

///|
/// Get or create a @abi.VReg for an IR Value
pub fn LoweringContext::get_vreg(
  self : LoweringContext,
  value : @milkir.Value,
) -> @abi.VReg {
  match self.get_cached_vreg(value.id) {
    Some(vreg) => vreg
    None => {
      let class = ir_type_to_reg_class(value.ty)
      let vreg = self.machv_func.new_vreg(class)
      self.set_cached_vreg(value.id, vreg)
      vreg
    }
  }
}

///|
/// Get @abi.VReg for an IR Value, generating LoadStackParam if it's a stack parameter
/// This should be used when lowering instructions that use values
pub fn LoweringContext::get_vreg_for_use(
  self : LoweringContext,
  value : @milkir.Value,
  block : @block.MachVBlock,
) -> @abi.VReg {
  if self.get_cached_vreg(value.id) is Some(vreg) {
    return vreg
  }

  // First check if it's a stack parameter
  if self.stack_param_map.get(value.id) is Some((offset, class)) {
    // Generate LoadStackParam instruction
    let result = self.machv_func.new_vreg(class)
    let inst = @instr.MachVInst::new(LoadStackParam(offset, class))
    inst.add_def({ reg: Virtual(result) })
    block.add_inst(inst)
    self.set_cached_vreg(value.id, result)
    result
  } else {
    // Materialize skipped pure defs on-demand. This prevents creating
    // undef virtual registers when an address-mode fusion path skipped a
    // producer that is still required by another lowered instruction.
    if self.is_skipped_value(value.id) &&
      find_defining_inst(self, value) is Some(def_inst) {
      lower_inst(self, def_inst, block)
      if self.get_cached_vreg(value.id) is Some(vreg) {
        return vreg
      }
    }
    // Fallback: keep previous behavior for values without visible defs
    // (e.g. malformed IR or future lowering cases).
    self.get_vreg(value)
  }
}

///|
/// Create a new @abi.VReg with the given class
pub fn LoweringContext::new_vreg(
  self : LoweringContext,
  class : @abi.RegClass,
) -> @abi.VReg {
  self.machv_func.new_vreg(class)
}

///|
/// Get MachV block id for an IR block id
fn LoweringContext::get_block_id(
  self : LoweringContext,
  ir_block_id : Int,
) -> Int {
  self.block_map.get(ir_block_id).unwrap()
}

///|
/// Convert IR Type to @abi.RegClass
pub fn ir_type_to_reg_class(ty : @milkir.Type) -> @abi.RegClass {
  match ty {
    I32 | I64 | Ptr | Ref | FuncRef | ExternRef => Int
    F32 => Float32
    F64 => Float64
    V128 => Vector // SIMD uses vector register class
  }
}

///|
/// Convert IR Type to MachV result kind.
fn ir_type_to_value_kind(ty : @milkir.Type) -> @machv.ValueKind {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    Ptr | Ref | FuncRef | ExternRef => Ptr
  }
}

///|
/// Convert IR Type to @instr.MemType
fn ir_type_to_mem_type(ty : @milkir.Type) -> @instr.MemType {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    // Reference types use 64-bit storage (0 as null)
    Ptr | Ref | FuncRef | ExternRef => I64
  }
}

// ============ Pattern Matching Helpers for AArch64 Instruction Selection ============

///|
/// Check if a value is defined by a shift-left instruction with a constant
/// Returns (shifted_value, shift_amount) if matched
/// The shift amount is masked according to MilkIR semantics:
/// - i32: amount & 31
/// - i64: amount & 63
fn match_shl_const_value(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> (@milkir.Value, Int)? {
  if find_defining_inst(ctx, value) is Some(inst) && inst.opcode is Ishl {
    // Check if shift amount is a constant
    let shift_operand = inst.operands[1]
    if find_defining_inst(ctx, shift_operand) is Some(shift_inst) &&
      shift_inst.opcode is Iconst(amount) {
      // Determine mask based on value type (i32 uses 31, i64 uses 63)
      let is_64 = value.ty is I64
      let mask = if is_64 { 63 } else { 31 }
      let shift_val = amount.to_int() & mask
      // shift_val is now guaranteed to be in valid range after masking
      return Some((inst.operands[0], shift_val))
    }
  }
  None
}

///|
/// Check if a value is defined by an unsigned shift-right with a constant.
/// Returns (shifted_value, shift_amount) if matched.
/// The shift amount is masked according to MilkIR semantics:
/// - i32: amount & 31
/// - i64: amount & 63
fn match_ushr_const_value(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> (@milkir.Value, Int)? {
  if find_defining_inst(ctx, value) is Some(inst) && inst.opcode is Ushr {
    let shift_operand = inst.operands[1]
    if find_defining_inst(ctx, shift_operand) is Some(shift_inst) &&
      shift_inst.opcode is Iconst(amount) {
      let is_64 = value.ty is I64
      let mask = if is_64 { 63 } else { 31 }
      let shift_val = amount.to_int() & mask
      return Some((inst.operands[0], shift_val))
    }
  }
  None
}

///|
/// Match rotate idiom encoded as OR of opposite-direction shifts:
/// - (x << a) | (x >> b)
/// - (x >> b) | (x << a)
/// where a + b == bitwidth.
///
/// Returns (x, rotr_amount=b) when matched.
fn match_rotate_or_value(
  ctx : LoweringContext,
  lhs : @milkir.Value,
  rhs : @milkir.Value,
  is_64 : Bool,
) -> (@milkir.Value, Int)? {
  let bits = if is_64 { 64 } else { 32 }

  fn match_one_side(
    ctx : LoweringContext,
    left : @milkir.Value,
    right : @milkir.Value,
    bits : Int,
  ) -> (@milkir.Value, Int)? {
    if match_shl_const_value(ctx, left) is Some((x, shl_amt)) &&
      match_ushr_const_value(ctx, right) is Some((y, shr_amt)) &&
      x.id == y.id &&
      shl_amt + shr_amt == bits {
      return Some((x, shr_amt))
    }
    None
  }

  if match_one_side(ctx, lhs, rhs, bits) is Some(m) {
    return Some(m)
  }
  if match_one_side(ctx, rhs, lhs, bits) is Some(m) {
    return Some(m)
  }
  None
}

///|
/// Match Cranelift AArch64 EXTR idiom encoded as OR of opposite-direction shifts:
/// - (x << a) | (y >> b)
/// - (y >> b) | (x << a)
/// where a + b == bitwidth.
///
/// Returns (x, y, b) for `extr x, y, #b`.
fn match_extr_or_value(
  ctx : LoweringContext,
  lhs : @milkir.Value,
  rhs : @milkir.Value,
  is_64 : Bool,
) -> (@milkir.Value, @milkir.Value, Int)? {
  let bits = if is_64 { 64 } else { 32 }

  fn match_one_side(
    ctx : LoweringContext,
    left : @milkir.Value,
    right : @milkir.Value,
    bits : Int,
  ) -> (@milkir.Value, @milkir.Value, Int)? {
    if match_shl_const_value(ctx, left) is Some((x, shl_amt)) &&
      match_ushr_const_value(ctx, right) is Some((y, shr_amt)) &&
      shl_amt + shr_amt == bits {
      return Some((x, y, shr_amt))
    }
    None
  }

  if match_one_side(ctx, lhs, rhs, bits) is Some(m) {
    return Some(m)
  }
  if match_one_side(ctx, rhs, lhs, bits) is Some(m) {
    return Some(m)
  }
  None
}

///|
/// Check if a value is defined by a multiply instruction
/// Returns (lhs, rhs) if matched
fn match_mul_value(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> (@milkir.Value, @milkir.Value)? {
  if find_defining_inst(ctx, value) is Some(inst) && inst.opcode is Imul {
    return Some((inst.operands[0], inst.operands[1]))
  }
  None
}

///|
/// Check if a value is defined by bitwise NOT.
/// Returns the inner operand if matched.
fn match_bnot_value(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> @milkir.Value? {
  if find_defining_inst(ctx, value) is Some(inst) && inst.opcode is Bnot {
    return Some(inst.operands[0])
  }
  None
}

///|
/// Check if a value is the constant 0
fn is_const_zero_value(ctx : LoweringContext, value : @milkir.Value) -> Bool {
  if resolve_iconst_value(ctx, value) is Some(v) {
    return v == 0L
  }
  false
}

///|
/// Resolve integer constants through trivial copy chains.
///
/// This mirrors Cranelift's preference for folding constants at use sites:
/// we avoid materializing extra `movz #0` when IR kept an intermediate `Copy`.
fn resolve_iconst_value(
  ctx : LoweringContext,
  value0 : @milkir.Value,
) -> Int64? {
  let mut value = value0
  for _ in 0..<8 {
    if find_defining_inst(ctx, value) is Some(inst) {
      match inst.opcode {
        Iconst(c) => return Some(c)
        Copy =>
          if inst.operands.length() > 0 {
            value = inst.operands[0]
            continue
          } else {
            return None
          }
        _ => return None
      }
    } else {
      return None
    }
  }
  None
}

///|
fn fits_i32_int64(value : Int64) -> Bool {
  value >= -2147483648L && value <= 2147483647L
}

///|
/// Check whether an ADD/SUB immediate is encodable for the selected ISA.
fn is_valid_add_sub_imm_for_isa(isa : @isa.ISA, value : Int64) -> Bool {
  match isa {
    AArch64 => is_valid_add_imm(value)
    AMD64 => fits_i32_int64(value)
  }
}

///|
/// Check whether a logical immediate form is worth selecting for current ISA.
///
/// AArch64 requires bitmask-immediate encodability.
/// AMD64 accepts this MachV form for all constants; its emitter materializes
/// the immediate as needed before selecting the final machine instruction shape.
fn is_valid_logic_imm_for_isa(
  isa : @isa.ISA,
  value : Int64,
  is_64 : Bool,
) -> Bool {
  match isa {
    AArch64 => @instr.aarch64_logic_imm_enc_bits(value, is_64) is Some(_)
    AMD64 => true
  }
}

///|
/// Check if a value is a constant and return the value if valid for ADD/SUB immediate
/// Returns Some(val) if the value is a constant in current ISA immediate range.
fn match_add_imm_value(ctx : LoweringContext, value : @milkir.Value) -> Int64? {
  let isa = ctx.isa
  if resolve_iconst_value(ctx, value) is Some(val) &&
    is_valid_add_sub_imm_for_isa(isa, val) {
    return Some(val)
  }
  None
}

///|
/// Check if a value is a constant whose negation is a valid ADD/SUB immediate.
/// Returns Some(-val) when val is a constant and -val is encodable for current ISA.
fn match_negated_add_imm_value(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> Int64? {
  let isa = ctx.isa
  if resolve_iconst_value(ctx, value) is Some(val) {
    let neg = -val
    if val < 0L && is_valid_add_sub_imm_for_isa(isa, neg) {
      return Some(neg)
    }
  }
  None
}

///|
/// Check if a value is iadd(base, iconst(offset)) and return (base, offset) if matched
/// Used for folding address calculations into load/store instructions
fn match_iadd_const(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> (@milkir.Value, Int64)? {
  if find_defining_inst(ctx, value) is Some(inst) && inst.opcode is Iadd {
    // Check if second operand is a constant
    if find_defining_inst(ctx, inst.operands[1]) is Some(const_inst) &&
      const_inst.opcode is Iconst(offset) {
      return Some((inst.operands[0], offset))
    }
    // Also check first operand (iadd is commutative)
    if find_defining_inst(ctx, inst.operands[0]) is Some(const_inst) &&
      const_inst.opcode is Iconst(offset) {
      return Some((inst.operands[1], offset))
    }
  }
  None
}

///|
/// Return the constant payload when `value` is defined by `Iconst`.
fn iconst_value(ctx : LoweringContext, value : @milkir.Value) -> Int64? {
  resolve_iconst_value(ctx, value)
}

///|
/// For plain `base + const_reg` address forms, prefer immediate-offset
/// load/store when encodable; otherwise keep reg-offset form.
fn prefer_reg_offset_for_index(
  ctx : LoweringContext,
  index : @milkir.Value,
  access_size : Int,
  explicit_offset : Int64,
  extra_offset : Int64,
  _has_extra : Bool,
) -> Bool {
  if iconst_value(ctx, index) is Some(iconst) {
    let combined = explicit_offset + extra_offset + iconst
    return !is_valid_load_store_offset(ctx, combined, access_size)
  }
  true
}

///|
/// Match uextend/sextend(i32)->i64 used in address calculations.
fn match_extend_i32_to_i64(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> (@milkir.Value, @instr.IndexExtend)? {
  if find_defining_inst(ctx, value) is Some(inst) {
    match inst.opcode {
      Uextend =>
        if value.ty is I64 && inst.operands[0].ty is I32 {
          return Some((inst.operands[0], Uxtw))
        }
      Sextend =>
        if value.ty is I64 && inst.operands[0].ty is I32 {
          return Some((inst.operands[0], Sxtw))
        }
      _ => ()
    }
  }
  None
}

///|
fn log2_access_size(access_size : Int) -> Int? {
  match access_size {
    1 => Some(0)
    2 => Some(1)
    4 => Some(2)
    8 => Some(3)
    16 => Some(4)
    _ => None
  }
}

///|
/// Match AArch64-style register-offset addressing (Cranelift AMode rules).
///
/// Returns:
/// - base: base pointer value
/// - index: index value (i32 if extended, otherwise i64)
/// - ext: None/Uxtw/Sxtw
/// - shift: 0 or log2(access_size)
/// - subsumed: intermediate SSA values that can be skipped (uextend/sextend/ishl)
/// - has_extra: whether we fused something beyond plain iadd(base, index)
fn match_addr_reg_offset(
  ctx : LoweringContext,
  value : @milkir.Value,
  access_size : Int,
) -> (
  @milkir.Value,
  @milkir.Value,
  @instr.IndexExtend,
  Int,
  Array[Int],
  Int64,
  Bool,
)? {
  guard find_defining_inst(ctx, value) is Some(inst) else { return None }
  guard inst.opcode is Iadd else { return None }
  let scale = log2_access_size(access_size)
  if scale is None {
    return None
  }
  let scale = scale.unwrap()

  if match_iadd_const(ctx, value) is Some((inner, folded_offset)) &&
    match_addr_reg_offset(ctx, inner, access_size)
    is Some((base, index, ext, shift, subsumed, extra_offset, _)) {
    let merged_subsumed : Array[Int] = []
    for id in subsumed {
      merged_subsumed.push(id)
    }
    merged_subsumed.push(value.id)
    return Some(
      (
        base,
        index,
        ext,
        shift,
        merged_subsumed,
        extra_offset + folded_offset,
        true,
      ),
    )
  }

  fn analyze(
    ctx : LoweringContext,
    base : @milkir.Value,
    index0 : @milkir.Value,
    scale : Int,
  ) -> (
    @milkir.Value,
    @milkir.Value,
    @instr.IndexExtend,
    Int,
    Array[Int],
    Int64,
    Int,
  ) {
    let mut base = base
    let mut index = index0
    let mut ext = @instr.IndexExtend::None
    let mut shift = 0
    let subsumed : Array[Int] = []
    let mut extra_offset = 0L
    let mut score = 0

    // Match offset-index: iadd(index, iconst C).
    if match_iadd_const(ctx, index) is Some((inner, off)) {
      subsumed.push(index.id)
      index = inner
      extra_offset = extra_offset + off
      score = score + 1
    }

    // Match base displacement: iadd(base, iconst C).
    if match_iadd_const(ctx, base) is Some((inner, off)) {
      subsumed.push(base.id)
      base = inner
      extra_offset = extra_offset + off
      score = score + 1
    }

    // Match scaled-index: iadd(base, (ishl idx scale)).
    if match_shl_const_value(ctx, index) is Some((inner, sh)) && sh == scale {
      subsumed.push(index.id)
      index = inner
      shift = scale
      score = score + 1
    }

    // Match extend after optional shift: uextend/sextend(i32)->i64.
    if match_extend_i32_to_i64(ctx, index) is Some((inner, e)) {
      subsumed.push(index.id)
      index = inner
      ext = e
      score = score + 1
    }
    // Match offset-index again after extend/shift normalization.
    //
    // Do this only for already-64-bit index forms.
    //
    // For `uxtw`/`sxtw`, rewriting:
    //   extend(iadd32(idx, C)) -> (extend idx) + C
    // is not semantics-preserving in general because `iadd32` wraps before
    // the extend. Splitting the constant can change addresses when overflow
    // occurs in 32-bit arithmetic.
    if ext is None && match_iadd_const(ctx, index) is Some((inner, off)) {
      subsumed.push(index.id)
      index = inner
      extra_offset = extra_offset + off
      score = score + 1
    }
    // Second chance to recover scaled-index after peeling nested adds.
    if shift == 0 &&
      match_shl_const_value(ctx, index) is Some((inner, sh)) &&
      sh == scale {
      subsumed.push(index.id)
      index = inner
      shift = scale
      score = score + 1
    }
    (base, index, ext, shift, subsumed, extra_offset, score)
  }

  let a = inst.operands[0]
  let b = inst.operands[1]
  let (base1, index1, ext1, shift1, subs1, extra1, score1) = analyze(
    ctx, a, b, scale,
  )
  let (base2, index2, ext2, shift2, subs2, extra2, score2) = analyze(
    ctx, b, a, scale,
  )
  if score1 >= score2 {
    let has_extra = score1 > 0 || extra1 != 0L
    Some((base1, index1, ext1, shift1, subs1, extra1, has_extra))
  } else {
    let has_extra = score2 > 0 || extra2 != 0L
    Some((base2, index2, ext2, shift2, subs2, extra2, has_extra))
  }
}

///|
/// Check if an offset is encodable in selected ISA addressing mode immediate.
fn is_valid_load_store_offset_for_isa(
  isa : @isa.ISA,
  offset : Int64,
  access_size : Int,
) -> Bool {
  match isa {
    AArch64 => {
      if offset < 0L {
        return false
      }
      // Check alignment
      if offset % access_size.to_int64() != 0L {
        return false
      }
      // Check scaled offset fits in 12 bits (max 4095 * access_size)
      let max_offset = 4095L * access_size.to_int64()
      offset <= max_offset
    }
    AMD64 => fits_i32_int64(offset)
  }
}

///|
/// Check if an offset is encodable in current ISA addressing mode immediate.
pub fn is_valid_load_store_offset(
  ctx : LoweringContext,
  offset : Int64,
  access_size : Int,
) -> Bool {
  is_valid_load_store_offset_for_isa(ctx.isa, offset, access_size)
}

///|
/// Check if a value is the result of an Icmp instruction
/// Returns (lhs, rhs, condition) if matched
fn match_icmp_value(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> (@milkir.Value, @milkir.Value, @milkir.IntCC)? {
  let mut current = value
  let mut depth = 0
  while depth < 8 {
    depth = depth + 1
    if find_defining_inst(ctx, current) is Some(inst) {
      match inst.opcode {
        Icmp(cc) => return Some((inst.operands[0], inst.operands[1], cc))
        Copy =>
          if !inst.operands.is_empty() {
            current = inst.operands[0]
            continue
          } else {
            return None
          }
        _ => return None
      }
    } else {
      return None
    }
  }
  None
}

///|
/// Convert IR IntCC to MachV Cond for conditional branches
fn intcc_to_cond(cc : @milkir.IntCC) -> @instr.Cond {
  match cc {
    Eq => Eq
    Ne => Ne
    Slt => Lt
    Sle => Le
    Sgt => Gt
    Sge => Ge
    Ult => Lo
    Ule => Ls
    Ugt => Hi
    Uge => Hs
  }
}

///|
/// Lower an entire IR function to MachV
pub fn lower_function(
  ir_func : @milkir.Function,
  isa? : @isa.ISA = AArch64,
  abi_settings? : @abi.ABISettings = @abi.ABISettings::default(),
  embedding_reg_roles? : @abi.EmbeddingRegRoles = @abi.EmbeddingRegRoles::none(),
  embedding_context_layout? : @abi.EmbeddingContextLayout? = None,
  call_conv_layout? : @abi.CallConventionLayout? = None,
  external_helper_symbols? : Map[String, String] = {},
  trap_payload_resolver? : (String) -> Int = fn(_reason) { 0 },
  extension_lowerer? : ((
    LoweringContext,
    @milkir.Inst,
    @block.MachVBlock,
    @milkir.ExtOp,
  ) -> Bool)? = None,
  num_imports? : Int = -1,
  run_ir_opt? : Bool = true,
) -> @machv.Function {
  // Keep this optional for call sites that already ran full IR optimization.
  if run_ir_opt {
    // Apply e-graph optimization before lowering (constant folding, uextend(const) -> const, etc.)
    @milkir.optimize_function(ir_func) |> ignore
  }
  let ctx = LoweringContext::new(
    ir_func, isa, abi_settings, embedding_reg_roles, embedding_context_layout, call_conv_layout,
    external_helper_symbols, trap_payload_resolver, extension_lowerer, num_imports,
  )

  // Phase 0: Pre-compute which Icmps can be fused with Select
  let fused_dense = compute_fused_icmps(
    ir_func,
    ctx.use_counts,
    ctx.def_inst_table,
  )
  for id in 0..<fused_dense.length() {
    if id >= 0 && id < ctx.fused_icmps_dense.length() {
      ctx.fused_icmps_dense[id] = fused_dense[id]
    }
  }
  // Phase 0.5: Pre-compute values to skip (subsumed by fused instruction selection)
  let skipped_dense = compute_skipped_values(ctx)
  for id in 0..<skipped_dense.length() {
    if id >= 0 && id < ctx.skipped_values_dense.length() {
      ctx.skipped_values_dense[id] = skipped_dense[id]
    }
  }

  // Phase 1: Create MachV blocks and set up block mapping
  for ir_block in ir_func.blocks {
    let machv_block = ctx.machv_func.new_block()
    ctx.block_map.set(ir_block.id, machv_block.id)
  }

  // Phase 2: Lower function parameters
  // ABI: params[0] is the embedding context, then configured argument assignment:
  // - int params: context register plus configured user argument registers
  // - float params: V0-V7
  // - overflow: int overflow first, then float overflow
  let call_conv = ctx.require_call_conv_layout()
  let max_int_reg_params = 1 + call_conv.user_arg_gprs.length()
  let max_float_reg_params = call_conv.arg_fprs.length()
  let mut int_reg_count = 0
  let mut float_reg_count = 0
  let int_stack_values : Array[@milkir.Value] = []
  let float_stack_values : Array[(@milkir.Value, @abi.RegClass)] = []
  let float_stack_classes : Array[@abi.RegClass] = []
  for param in function_params_for_lowering(ir_func) {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    if class is Int {
      if int_reg_count < max_int_reg_params {
        // Register parameter: allocate @abi.VReg
        let vreg = ctx.machv_func.add_param(class)
        ctx.set_cached_vreg(value.id, vreg)
        int_reg_count = int_reg_count + 1
      } else {
        // Stack parameter: laid out in overflow area (entry SP).
        int_stack_values.push(value)
      }
      // Vector uses same V0-V7 registers as floats on AArch64
    } else if float_reg_count < max_float_reg_params {
      // Register parameter: allocate @abi.VReg
      let vreg = ctx.machv_func.add_param(class)
      ctx.set_cached_vreg(value.id, vreg)
      float_reg_count = float_reg_count + 1
    } else {
      float_stack_values.push((value, class))
      float_stack_classes.push(class)
    }
  }
  let (int_offsets, float_offsets, _) = call_conv.layout_overflow_stack(
    int_stack_values.length(),
    float_stack_classes,
  )
  // amd64 uses a CALL instruction, so the return address occupies 8 bytes at
  // the entry SP. Stack parameters are therefore at [entry_sp + 8 + offset].
  // (Cranelift x64 models this the same way.)
  let stack_arg_base = if ctx.isa is AMD64 { 8 } else { 0 }
  for i in 0..<int_stack_values.length() {
    ctx.stack_param_map.set(
      int_stack_values[i].id,
      (int_offsets[i] + stack_arg_base, Int),
    )
  }
  for i in 0..<float_stack_values.length() {
    let (value, class) = float_stack_values[i]
    ctx.stack_param_map.set(
      value.id,
      (float_offsets[i] + stack_arg_base, class),
    )
  }
  ctx.machv_func.set_int_stack_params(int_stack_values.length())

  // Phase 3: Lower result types
  for ty in ir_func.results {
    let class = ir_type_to_reg_class(ty)
    ctx.machv_func.add_result(class)
    ctx.machv_func.add_result_kind(ir_type_to_value_kind(ty))
  }

  // Phase 3.5: Pre-register all block parameters
  // This is critical: when processing jumps/branches, we need to know
  // the vreg IDs of target block parameters BEFORE lowering those blocks.
  for i, ir_block in ir_func.blocks {
    for param in ir_block.params {
      let (value, ty) = param
      let class = ir_type_to_reg_class(ty)
      let vreg = ctx.machv_func.new_vreg(class)
      ctx.set_cached_vreg(value.id, vreg)
      ctx.machv_func.blocks[i].params.push(vreg)
    }
  }

  // Phase 4: Lower each block (instructions and terminators only, params already done)
  for i, ir_block in ir_func.blocks {
    lower_block_body(ctx, ir_block, ctx.machv_func.blocks[i])
  }

  // Phase 5: Peephole optimization
  // Keep post-lowering cleanup deterministic (profile-driven) instead of
  // function-size gating.
  optimize_machv_for_lowering(
    ctx.machv_func,
    isa=ctx.isa,
    embedding_context_layout~,
    embedding_reg_roles=ctx.embedding_reg_roles,
  )

  // Phase 6: Target-specific fixups (Cranelift-style).
  //
  // On amd64, variable shifts/rotates use CL (rcx) as the implicit count
  // register. Enforce this constraint universally to avoid relying on each
  // lowering site to set it correctly.
  if ctx.isa is AMD64 {
    fixup_amd64_shift_count_constraints(ctx.machv_func)
  }
  ctx.machv_func
}

///|
fn fixup_amd64_shift_count_constraints(func : @machv.Function) -> Unit {
  for block in func.blocks {
    for inst in block.insts {
      if (
          inst.opcode is Shl(_) ||
          inst.opcode is LShr(_) ||
          inst.opcode is AShr(_) ||
          inst.opcode is Rotr(_)
        ) &&
        inst.uses.length() >= 2 {
        match inst.use_constraints[1] {
          FixedReg(_) => ()
          _ => inst.use_constraints[1] = FixedReg({ index: 1, class: Int }) // rcx
        }
      }
    }
  }
}

///|
/// Lower a single IR block to MachV (body only, params handled in pre-registration)
fn lower_block_body(
  ctx : LoweringContext,
  ir_block : @milkir.Block,
  machv_block : @block.MachVBlock,
) -> Unit {
  // Block-local cache: do not carry context-pointer CSE across block boundaries.
  invalidate_context_pointer_cache(ctx)

  // Block parameters are already handled in pre-registration phase

  // Lower instructions
  for inst in ir_block.instructions {
    if inst.first_result() is Some(result) && ctx.is_skipped_value(result.id) {
      continue
    }
    lower_inst(ctx, inst, machv_block)
  }

  // Lower terminator
  if ir_block.terminator is Some(term) {
    lower_terminator(ctx, term, machv_block)
  }
}

///|
fn lower_unsupported_generic_opcode(
  inst : @milkir.Inst,
  _block : @block.MachVBlock,
) -> Unit {
  // TODO(milkir): Implement full generic MilkIR lowering for this opcode.
  // Dialect extension lowering is handled explicitly; aborting here keeps
  // unsupported generic paths explicit instead of silently miscompiling.
  abort("unsupported MilkIR opcode: \{to_repr(inst.opcode)}")
}

///|
pub fn lower_unsupported_extension_opcode(
  inst : @milkir.Inst,
  block : @block.MachVBlock,
) -> Unit {
  lower_unsupported_generic_opcode(inst, block)
}

///|
fn lower_extension(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  ext : @milkir.ExtOp,
) -> Unit {
  match ctx.extension_lowerer {
    Some(lowerer) =>
      if !lowerer(ctx, inst, block, ext) {
        lower_unsupported_generic_opcode(inst, block)
      }
    None => lower_unsupported_generic_opcode(inst, block)
  }
}

///|
/// Lower a single IR instruction to MachV
fn lower_inst(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
) -> Unit {
  match inst.opcode {
    // Constants
    Iconst(val) => lower_iconst(ctx, inst, block, val)
    Fconst(val) => lower_fconst(ctx, inst, block, val)

    // Integer arithmetic - with pattern matching for AArch64
    Iadd => lower_iadd(ctx, inst, block)
    Isub => lower_isub(ctx, inst, block)
    Imul => lower_imul(ctx, inst, block)
    Umulh => lower_umulh(ctx, inst, block)
    Smulh => lower_smulh(ctx, inst, block)
    Sdiv => lower_div(ctx, inst, block, signed=true)
    Udiv => lower_div(ctx, inst, block, signed=false)
    Srem => lower_rem(ctx, inst, block, true)
    Urem => lower_rem(ctx, inst, block, false)

    // Bitwise operations - with pattern matching for shifted operands
    Band => lower_band(ctx, inst, block)
    Bor => lower_bor(ctx, inst, block)
    Bxor => lower_bxor(ctx, inst, block)
    Ishl =>
      lower_shift(ctx, inst, block, fn(is_64) { Shl(is_64) }, fn(amt, is_64) {
        ShlImm(amt, is_64)
      })
    Sshr =>
      lower_shift(ctx, inst, block, fn(is_64) { AShr(is_64) }, fn(amt, is_64) {
        AShrImm(amt, is_64)
      })
    Ushr =>
      lower_shift(ctx, inst, block, fn(is_64) { LShr(is_64) }, fn(amt, is_64) {
        LShrImm(amt, is_64)
      })
    Rotl => lower_rotl(ctx, inst, block)
    Rotr =>
      lower_shift(ctx, inst, block, fn(is_64) { Rotr(is_64) }, fn(amt, is_64) {
        RotrImm(amt, is_64)
      })
    Bnot => lower_unary_int(ctx, inst, block, fn(is_64) { Not(is_64) })

    // Integer comparisons
    Icmp(cc) => lower_icmp(ctx, inst, block, cc)
    IcmpEq => lower_unsupported_generic_opcode(inst, block)

    // Floating point arithmetic
    Fadd => lower_binary_float(ctx, inst, block)
    Fsub => lower_binary_float(ctx, inst, block)
    Fmul => lower_binary_float(ctx, inst, block)
    Fdiv => lower_binary_float(ctx, inst, block)
    Fmin => lower_binary_float(ctx, inst, block)
    Fmax => lower_binary_float(ctx, inst, block)

    // Floating point unary operations
    Fsqrt => lower_unary_float(ctx, inst, block)
    Fabs => lower_unary_float(ctx, inst, block)
    Fneg => lower_unary_float(ctx, inst, block)
    Fceil => lower_unary_float(ctx, inst, block)
    Ffloor => lower_unary_float(ctx, inst, block)
    Ftrunc => lower_unary_float(ctx, inst, block)
    Fnearest => lower_unary_float(ctx, inst, block)

    // Bit counting operations
    Clz => lower_bitcount(ctx, inst, block, fn(is_64) { Clz(is_64) })
    Ctz => lower_ctz(ctx, inst, block)
    Popcnt => lower_bitcount(ctx, inst, block, fn(is_64) { Popcnt(is_64) })

    // Floating point comparisons
    Fcmp(cc) => lower_fcmp(ctx, inst, block, cc)

    // Note: Load/Store opcodes removed - now desugared via FuncEnvironment to LoadPtr/StorePtr
    Load | Store | StackAddr(_) => lower_unsupported_generic_opcode(inst, block)

    // Conversions
    Sextend => lower_extend(ctx, inst, block, signed=true)
    Uextend => lower_extend(ctx, inst, block, signed=false)
    Sextend8 => lower_sextend_inplace(ctx, inst, block, from_bits=8)
    Sextend16 => lower_sextend_inplace(ctx, inst, block, from_bits=16)
    Sextend32 => lower_sextend_inplace(ctx, inst, block, from_bits=32)
    Ireduce => lower_truncate(ctx, inst, block)
    FcvtToSint => lower_float_to_int(ctx, inst, block, signed=true)
    FcvtToUint => lower_float_to_int(ctx, inst, block, signed=false)
    FcvtToSintSat => lower_float_to_int_sat(ctx, inst, block, signed=true)
    FcvtToUintSat => lower_float_to_int_sat(ctx, inst, block, signed=false)
    SintToFcvt => lower_int_to_float(ctx, inst, block, signed=true)
    UintToFcvt => lower_int_to_float(ctx, inst, block, signed=false)
    Fpromote => lower_promote(ctx, inst, block)
    Fdemote => lower_demote(ctx, inst, block)
    Bitcast => lower_bitcast(ctx, inst, block)

    // Misc
    Copy => lower_copy(ctx, inst, block)
    Select => lower_select(ctx, inst, block)

    // Function calls
    Call(symbol) => lower_external_call(ctx, inst, block, symbol)
    CallIndirect(_) => lower_unsupported_generic_opcode(inst, block)

    // Raw pointer operations (for trampolines)
    LoadPtr(ty) => lower_load_ptr(ctx, inst, block, ty)
    StorePtr(ty) => lower_store_ptr(ctx, inst, block, ty)
    LoadPtrNarrow(result_ty, bits, signed) =>
      lower_load_ptr_narrow(ctx, inst, block, result_ty, bits, signed)
    StorePtrNarrow(bits) => lower_store_ptr_narrow(ctx, inst, block, bits)
    CallPtr(num_args, num_results) =>
      lower_call_ptr(ctx, inst, block, num_args, num_results)
    Trap(_) | Custom(_) => lower_unsupported_generic_opcode(inst, block)
    Ext(ext) => lower_extension(ctx, inst, block, ext)

    // SIMD operations
    V128Const(bytes) => lower_v128_const(ctx, inst, block, bytes)
    V128Splat8 => lower_v128_splat(ctx, inst, block, B8)
    V128Splat16 => lower_v128_splat(ctx, inst, block, H16)
    V128Splat32 => lower_v128_splat(ctx, inst, block, S32)
    V128Splat64 => lower_v128_splat(ctx, inst, block, D64)
    V128SplatF32 => lower_v128_splat_f(ctx, inst, block, true)
    V128SplatF64 => lower_v128_splat_f(ctx, inst, block, false)
    V128ExtractLane8S(lane) => lower_v128_extract_s(ctx, inst, block, B8, lane)
    V128ExtractLane8U(lane) => lower_v128_extract_u(ctx, inst, block, B8, lane)
    V128ExtractLane16S(lane) =>
      lower_v128_extract_s(ctx, inst, block, H16, lane)
    V128ExtractLane16U(lane) =>
      lower_v128_extract_u(ctx, inst, block, H16, lane)
    V128ExtractLane32(lane) => lower_v128_extract_u(ctx, inst, block, S32, lane)
    V128ExtractLane64(lane) => lower_v128_extract_u(ctx, inst, block, D64, lane)
    V128ExtractLaneF32(lane) =>
      lower_v128_extract_f(ctx, inst, block, true, lane)
    V128ExtractLaneF64(lane) =>
      lower_v128_extract_f(ctx, inst, block, false, lane)
    V128ReplaceLane8(lane) => lower_v128_replace(ctx, inst, block, B8, lane)
    V128ReplaceLane16(lane) => lower_v128_replace(ctx, inst, block, H16, lane)
    V128ReplaceLane32(lane) => lower_v128_replace(ctx, inst, block, S32, lane)
    V128ReplaceLane64(lane) => lower_v128_replace(ctx, inst, block, D64, lane)
    V128ReplaceLaneF32(lane) =>
      lower_v128_replace_f(ctx, inst, block, true, lane)
    V128ReplaceLaneF64(lane) =>
      lower_v128_replace_f(ctx, inst, block, false, lane)
    V128Shuffle(lanes) => lower_v128_shuffle(ctx, inst, block, lanes)
    V128Swizzle => lower_v128_swizzle(ctx, inst, block)

    // Bitwise operations
    V128Not => lower_v128_unary(ctx, inst, block, SIMDNot)
    V128And => lower_v128_binary(ctx, inst, block, SIMDAnd)
    V128AndNot => lower_v128_binary(ctx, inst, block, SIMDBic)
    V128Or => lower_v128_binary(ctx, inst, block, SIMDOr)
    V128Xor => lower_v128_binary(ctx, inst, block, SIMDXor)
    V128Bitselect => lower_v128_ternary(ctx, inst, block, SIMDBsl)

    // Any/All true, Bitmask
    V128AnyTrue => lower_v128_to_i32(ctx, inst, block, SIMDAnyTrue)
    V128AllTrue8 => lower_v128_to_i32(ctx, inst, block, SIMDAllTrue(B8))
    V128AllTrue16 => lower_v128_to_i32(ctx, inst, block, SIMDAllTrue(H16))
    V128AllTrue32 => lower_v128_to_i32(ctx, inst, block, SIMDAllTrue(S32))
    V128AllTrue64 => lower_v128_to_i32(ctx, inst, block, SIMDAllTrue(D64))
    V128Bitmask8 => lower_v128_to_i32(ctx, inst, block, SIMDBitmask(B8))
    V128Bitmask16 => lower_v128_to_i32(ctx, inst, block, SIMDBitmask(H16))
    V128Bitmask32 => lower_v128_to_i32(ctx, inst, block, SIMDBitmask(S32))
    V128Bitmask64 => lower_v128_to_i32(ctx, inst, block, SIMDBitmask(D64))

    // Integer arithmetic
    V128Add8 => lower_v128_binary(ctx, inst, block, SIMDAdd(B8))
    V128Add16 => lower_v128_binary(ctx, inst, block, SIMDAdd(H16))
    V128Add32 => lower_v128_binary(ctx, inst, block, SIMDAdd(S32))
    V128Add64 => lower_v128_binary(ctx, inst, block, SIMDAdd(D64))
    V128Sub8 => lower_v128_binary(ctx, inst, block, SIMDSub(B8))
    V128Sub16 => lower_v128_binary(ctx, inst, block, SIMDSub(H16))
    V128Sub32 => lower_v128_binary(ctx, inst, block, SIMDSub(S32))
    V128Sub64 => lower_v128_binary(ctx, inst, block, SIMDSub(D64))
    V128Mul16 => lower_v128_binary(ctx, inst, block, SIMDMul(H16))
    V128Mul32 => lower_v128_binary(ctx, inst, block, SIMDMul(S32))
    V128Mul64 => lower_v128_binary(ctx, inst, block, SIMDMul(D64))

    // Saturating arithmetic
    V128AddSat8S => lower_v128_binary(ctx, inst, block, SIMDSqadd(B8))
    V128AddSat8U => lower_v128_binary(ctx, inst, block, SIMDUqadd(B8))
    V128AddSat16S => lower_v128_binary(ctx, inst, block, SIMDSqadd(H16))
    V128AddSat16U => lower_v128_binary(ctx, inst, block, SIMDUqadd(H16))
    V128SubSat8S => lower_v128_binary(ctx, inst, block, SIMDSqsub(B8))
    V128SubSat8U => lower_v128_binary(ctx, inst, block, SIMDUqsub(B8))
    V128SubSat16S => lower_v128_binary(ctx, inst, block, SIMDSqsub(H16))
    V128SubSat16U => lower_v128_binary(ctx, inst, block, SIMDUqsub(H16))

    // Min/Max
    V128Min8S => lower_v128_binary(ctx, inst, block, SIMDSmin(B8))
    V128Min8U => lower_v128_binary(ctx, inst, block, SIMDUmin(B8))
    V128Min16S => lower_v128_binary(ctx, inst, block, SIMDSmin(H16))
    V128Min16U => lower_v128_binary(ctx, inst, block, SIMDUmin(H16))
    V128Min32S => lower_v128_binary(ctx, inst, block, SIMDSmin(S32))
    V128Min32U => lower_v128_binary(ctx, inst, block, SIMDUmin(S32))
    V128Max8S => lower_v128_binary(ctx, inst, block, SIMDSmax(B8))
    V128Max8U => lower_v128_binary(ctx, inst, block, SIMDUmax(B8))
    V128Max16S => lower_v128_binary(ctx, inst, block, SIMDSmax(H16))
    V128Max16U => lower_v128_binary(ctx, inst, block, SIMDUmax(H16))
    V128Max32S => lower_v128_binary(ctx, inst, block, SIMDSmax(S32))
    V128Max32U => lower_v128_binary(ctx, inst, block, SIMDUmax(S32))

    // Average
    V128Avgr8U => lower_v128_binary(ctx, inst, block, SIMDUrhadd(B8))
    V128Avgr16U => lower_v128_binary(ctx, inst, block, SIMDUrhadd(H16))

    // Unary operations
    V128Abs8 => lower_v128_unary(ctx, inst, block, SIMDAbs(B8))
    V128Abs16 => lower_v128_unary(ctx, inst, block, SIMDAbs(H16))
    V128Abs32 => lower_v128_unary(ctx, inst, block, SIMDAbs(S32))
    V128Abs64 => lower_v128_unary(ctx, inst, block, SIMDAbs(D64))
    V128Neg8 => lower_v128_unary(ctx, inst, block, SIMDNeg(B8))
    V128Neg16 => lower_v128_unary(ctx, inst, block, SIMDNeg(H16))
    V128Neg32 => lower_v128_unary(ctx, inst, block, SIMDNeg(S32))
    V128Neg64 => lower_v128_unary(ctx, inst, block, SIMDNeg(D64))
    V128Popcnt8 => lower_v128_unary(ctx, inst, block, SIMDCnt)

    // Shifts - split into SIMDBroadcastShift + SIMDShiftByVec
    // lower_v128_shift(ctx, inst, block, lane_size, negate, use_ushl)
    V128Shl8 => lower_v128_shift(ctx, inst, block, B8, false, false)
    V128Shl16 => lower_v128_shift(ctx, inst, block, H16, false, false)
    V128Shl32 => lower_v128_shift(ctx, inst, block, S32, false, false)
    V128Shl64 => lower_v128_shift(ctx, inst, block, D64, false, false)
    V128Shr8S => lower_v128_shift(ctx, inst, block, B8, true, false)
    V128Shr8U => lower_v128_shift(ctx, inst, block, B8, true, true)
    V128Shr16S => lower_v128_shift(ctx, inst, block, H16, true, false)
    V128Shr16U => lower_v128_shift(ctx, inst, block, H16, true, true)
    V128Shr32S => lower_v128_shift(ctx, inst, block, S32, true, false)
    V128Shr32U => lower_v128_shift(ctx, inst, block, S32, true, true)
    V128Shr64S => lower_v128_shift(ctx, inst, block, D64, true, false)
    V128Shr64U => lower_v128_shift(ctx, inst, block, D64, true, true)

    // Comparisons
    V128Eq8 => lower_v128_binary(ctx, inst, block, SIMDCmp(B8, Eq))
    V128Eq16 => lower_v128_binary(ctx, inst, block, SIMDCmp(H16, Eq))
    V128Eq32 => lower_v128_binary(ctx, inst, block, SIMDCmp(S32, Eq))
    V128Eq64 => lower_v128_binary(ctx, inst, block, SIMDCmp(D64, Eq))
    V128Ne8 => lower_v128_cmp_ne(ctx, inst, block, B8)
    V128Ne16 => lower_v128_cmp_ne(ctx, inst, block, H16)
    V128Ne32 => lower_v128_cmp_ne(ctx, inst, block, S32)
    V128Ne64 => lower_v128_cmp_ne(ctx, inst, block, D64)
    V128Lt8S => lower_v128_cmp_lt(ctx, inst, block, B8, true)
    V128Lt8U => lower_v128_cmp_lt(ctx, inst, block, B8, false)
    V128Lt16S => lower_v128_cmp_lt(ctx, inst, block, H16, true)
    V128Lt16U => lower_v128_cmp_lt(ctx, inst, block, H16, false)
    V128Lt32S => lower_v128_cmp_lt(ctx, inst, block, S32, true)
    V128Lt32U => lower_v128_cmp_lt(ctx, inst, block, S32, false)
    V128Lt64S => lower_v128_cmp_lt(ctx, inst, block, D64, true)
    V128Gt8S => lower_v128_binary(ctx, inst, block, SIMDCmp(B8, GtS))
    V128Gt8U => lower_v128_binary(ctx, inst, block, SIMDCmp(B8, GtU))
    V128Gt16S => lower_v128_binary(ctx, inst, block, SIMDCmp(H16, GtS))
    V128Gt16U => lower_v128_binary(ctx, inst, block, SIMDCmp(H16, GtU))
    V128Gt32S => lower_v128_binary(ctx, inst, block, SIMDCmp(S32, GtS))
    V128Gt32U => lower_v128_binary(ctx, inst, block, SIMDCmp(S32, GtU))
    V128Gt64S => lower_v128_binary(ctx, inst, block, SIMDCmp(D64, GtS))
    V128Le8S => lower_v128_cmp_le(ctx, inst, block, B8, true)
    V128Le8U => lower_v128_cmp_le(ctx, inst, block, B8, false)
    V128Le16S => lower_v128_cmp_le(ctx, inst, block, H16, true)
    V128Le16U => lower_v128_cmp_le(ctx, inst, block, H16, false)
    V128Le32S => lower_v128_cmp_le(ctx, inst, block, S32, true)
    V128Le32U => lower_v128_cmp_le(ctx, inst, block, S32, false)
    V128Le64S => lower_v128_cmp_le(ctx, inst, block, D64, true)
    V128Ge8S => lower_v128_binary(ctx, inst, block, SIMDCmp(B8, GeS))
    V128Ge8U => lower_v128_binary(ctx, inst, block, SIMDCmp(B8, GeU))
    V128Ge16S => lower_v128_binary(ctx, inst, block, SIMDCmp(H16, GeS))
    V128Ge16U => lower_v128_binary(ctx, inst, block, SIMDCmp(H16, GeU))
    V128Ge32S => lower_v128_binary(ctx, inst, block, SIMDCmp(S32, GeS))
    V128Ge32U => lower_v128_binary(ctx, inst, block, SIMDCmp(S32, GeU))
    V128Ge64S => lower_v128_binary(ctx, inst, block, SIMDCmp(D64, GeS))

    // Narrow/Extend
    V128Narrow16to8S =>
      lower_v128_binary(ctx, inst, block, SIMDNarrow(B8, true))
    V128Narrow16to8U =>
      lower_v128_binary(ctx, inst, block, SIMDNarrow(B8, false))
    V128Narrow32to16S =>
      lower_v128_binary(ctx, inst, block, SIMDNarrow(H16, true))
    V128Narrow32to16U =>
      lower_v128_binary(ctx, inst, block, SIMDNarrow(H16, false))
    V128ExtendLow8to16S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(H16, true))
    V128ExtendHigh8to16S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(H16, true))
    V128ExtendLow8to16U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(H16, false))
    V128ExtendHigh8to16U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(H16, false))
    V128ExtendLow16to32S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(S32, true))
    V128ExtendHigh16to32S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(S32, true))
    V128ExtendLow16to32U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(S32, false))
    V128ExtendHigh16to32U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(S32, false))
    V128ExtendLow32to64S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(D64, true))
    V128ExtendHigh32to64S =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(D64, true))
    V128ExtendLow32to64U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendLow(D64, false))
    V128ExtendHigh32to64U =>
      lower_v128_unary(ctx, inst, block, SIMDExtendHigh(D64, false))

    // Extended multiply
    V128ExtMulLow8to16S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(H16, true))
    V128ExtMulHigh8to16S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(H16, true))
    V128ExtMulLow8to16U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(H16, false))
    V128ExtMulHigh8to16U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(H16, false))
    V128ExtMulLow16to32S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(S32, true))
    V128ExtMulHigh16to32S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(S32, true))
    V128ExtMulLow16to32U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(S32, false))
    V128ExtMulHigh16to32U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(S32, false))
    V128ExtMulLow32to64S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(D64, true))
    V128ExtMulHigh32to64S =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(D64, true))
    V128ExtMulLow32to64U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulLow(D64, false))
    V128ExtMulHigh32to64U =>
      lower_v128_binary(ctx, inst, block, SIMDExtMulHigh(D64, false))

    // Extended add pairwise
    V128ExtAddPairwise8to16S =>
      lower_v128_unary(ctx, inst, block, SIMDExtAddPairwise(H16, true))
    V128ExtAddPairwise8to16U =>
      lower_v128_unary(ctx, inst, block, SIMDExtAddPairwise(H16, false))
    V128ExtAddPairwise16to32S =>
      lower_v128_unary(ctx, inst, block, SIMDExtAddPairwise(S32, true))
    V128ExtAddPairwise16to32U =>
      lower_v128_unary(ctx, inst, block, SIMDExtAddPairwise(S32, false))

    // Dot product and Q15
    V128Dot16to32S => lower_v128_binary(ctx, inst, block, SIMDDot)
    V128Q15MulrSat16S => lower_v128_binary(ctx, inst, block, SIMDQ15MulrSat)

    // Floating point arithmetic
    V128AddF32 => lower_v128_binary(ctx, inst, block, SIMDFAdd(true))
    V128AddF64 => lower_v128_binary(ctx, inst, block, SIMDFAdd(false))
    V128SubF32 => lower_v128_binary(ctx, inst, block, SIMDFSub(true))
    V128SubF64 => lower_v128_binary(ctx, inst, block, SIMDFSub(false))
    V128MulF32 => lower_v128_binary(ctx, inst, block, SIMDFMul(true))
    V128MulF64 => lower_v128_binary(ctx, inst, block, SIMDFMul(false))
    V128DivF32 => lower_v128_binary(ctx, inst, block, SIMDFDiv(true))
    V128DivF64 => lower_v128_binary(ctx, inst, block, SIMDFDiv(false))
    V128MinF32 => lower_v128_binary(ctx, inst, block, SIMDFMin(true))
    V128MinF64 => lower_v128_binary(ctx, inst, block, SIMDFMin(false))
    V128MaxF32 => lower_v128_binary(ctx, inst, block, SIMDFMax(true))
    V128MaxF64 => lower_v128_binary(ctx, inst, block, SIMDFMax(false))
    V128PMinF32 => lower_v128_binary(ctx, inst, block, SIMDFPMin(true))
    V128PMinF64 => lower_v128_binary(ctx, inst, block, SIMDFPMin(false))
    V128PMaxF32 => lower_v128_binary(ctx, inst, block, SIMDFPMax(true))
    V128PMaxF64 => lower_v128_binary(ctx, inst, block, SIMDFPMax(false))

    // Floating point unary
    V128AbsF32 => lower_v128_unary(ctx, inst, block, SIMDFAbs(true))
    V128AbsF64 => lower_v128_unary(ctx, inst, block, SIMDFAbs(false))
    V128NegF32 => lower_v128_unary(ctx, inst, block, SIMDFNeg(true))
    V128NegF64 => lower_v128_unary(ctx, inst, block, SIMDFNeg(false))
    V128SqrtF32 => lower_v128_unary(ctx, inst, block, SIMDFSqrt(true))
    V128SqrtF64 => lower_v128_unary(ctx, inst, block, SIMDFSqrt(false))
    V128CeilF32 => lower_v128_unary(ctx, inst, block, SIMDFCeil(true))
    V128CeilF64 => lower_v128_unary(ctx, inst, block, SIMDFCeil(false))
    V128FloorF32 => lower_v128_unary(ctx, inst, block, SIMDFFloor(true))
    V128FloorF64 => lower_v128_unary(ctx, inst, block, SIMDFFloor(false))
    V128TruncF32 => lower_v128_unary(ctx, inst, block, SIMDFTrunc(true))
    V128TruncF64 => lower_v128_unary(ctx, inst, block, SIMDFTrunc(false))
    V128NearestF32 => lower_v128_unary(ctx, inst, block, SIMDFNearest(true))
    V128NearestF64 => lower_v128_unary(ctx, inst, block, SIMDFNearest(false))

    // Floating point comparisons
    V128EqF32 => lower_v128_binary(ctx, inst, block, SIMDFCmp(true, Eq))
    V128EqF64 => lower_v128_binary(ctx, inst, block, SIMDFCmp(false, Eq))
    V128NeF32 => lower_v128_fcmp_ne(ctx, inst, block, true)
    V128NeF64 => lower_v128_fcmp_ne(ctx, inst, block, false)
    V128LtF32 =>
      // lt(a,b) = gt(b,a) - swap operands
      lower_v128_binary_swap(ctx, inst, block, SIMDFCmp(true, Gt))
    V128LtF64 => lower_v128_binary_swap(ctx, inst, block, SIMDFCmp(false, Gt))
    V128GtF32 => lower_v128_binary(ctx, inst, block, SIMDFCmp(true, Gt))
    V128GtF64 => lower_v128_binary(ctx, inst, block, SIMDFCmp(false, Gt))
    V128LeF32 =>
      // le(a,b) = ge(b,a) - swap operands
      lower_v128_binary_swap(ctx, inst, block, SIMDFCmp(true, Ge))
    V128LeF64 => lower_v128_binary_swap(ctx, inst, block, SIMDFCmp(false, Ge))
    V128GeF32 => lower_v128_binary(ctx, inst, block, SIMDFCmp(true, Ge))
    V128GeF64 => lower_v128_binary(ctx, inst, block, SIMDFCmp(false, Ge))

    // Conversions
    V128TruncSatF32toI32S =>
      lower_v128_unary(ctx, inst, block, SIMDFCvtToIntS(true))
    V128TruncSatF32toI32U =>
      lower_v128_unary(ctx, inst, block, SIMDFCvtToIntU(true))
    V128TruncSatF64toI32SZero =>
      lower_v128_unary(ctx, inst, block, SIMDTruncSatF64ToI32SZero)
    V128TruncSatF64toI32UZero =>
      lower_v128_unary(ctx, inst, block, SIMDTruncSatF64ToI32UZero)
    V128ConvertI32toF32S =>
      lower_v128_unary(ctx, inst, block, SIMDIntToFloatS(true))
    V128ConvertI32toF32U =>
      lower_v128_unary(ctx, inst, block, SIMDIntToFloatU(true))
    V128ConvertLowI32toF64S =>
      lower_v128_unary(ctx, inst, block, SIMDConvertLowI32ToF64S)
    V128ConvertLowI32toF64U =>
      lower_v128_unary(ctx, inst, block, SIMDConvertLowI32ToF64U)
    V128DemoteF64toF32Zero =>
      lower_v128_unary(ctx, inst, block, SIMDDemoteF64ToF32Zero)
    V128PromoteLowF32toF64 =>
      lower_v128_unary(ctx, inst, block, SIMDPromoteLowF32ToF64)

    // Memory operations
    V128Load8x8S(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 8, true, offset.to_int())
    V128Load8x8U(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 8, false, offset.to_int())
    V128Load16x4S(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 16, true, offset.to_int())
    V128Load16x4U(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 16, false, offset.to_int())
    V128Load32x2S(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 32, true, offset.to_int())
    V128Load32x2U(_, _, offset) =>
      lower_v128_load_extend(ctx, inst, block, 32, false, offset.to_int())
    V128Load8Splat(_, _, offset) =>
      lower_v128_load_splat(ctx, inst, block, B8, offset.to_int())
    V128Load16Splat(_, _, offset) =>
      lower_v128_load_splat(ctx, inst, block, H16, offset.to_int())
    V128Load32Splat(_, _, offset) =>
      lower_v128_load_splat(ctx, inst, block, S32, offset.to_int())
    V128Load64Splat(_, _, offset) =>
      lower_v128_load_splat(ctx, inst, block, D64, offset.to_int())
    V128Load32Zero(_, _, offset) =>
      lower_v128_load_zero(ctx, inst, block, false, offset.to_int())
    V128Load64Zero(_, _, offset) =>
      lower_v128_load_zero(ctx, inst, block, true, offset.to_int())
    V128Load8Lane(_, _, offset, lane) =>
      lower_v128_load_lane(ctx, inst, block, B8, lane, offset.to_int())
    V128Load16Lane(_, _, offset, lane) =>
      lower_v128_load_lane(ctx, inst, block, H16, lane, offset.to_int())
    V128Load32Lane(_, _, offset, lane) =>
      lower_v128_load_lane(ctx, inst, block, S32, lane, offset.to_int())
    V128Load64Lane(_, _, offset, lane) =>
      lower_v128_load_lane(ctx, inst, block, D64, lane, offset.to_int())
    V128Store8Lane(_, _, offset, lane) =>
      lower_v128_store_lane(ctx, inst, block, B8, lane, offset.to_int())
    V128Store16Lane(_, _, offset, lane) =>
      lower_v128_store_lane(ctx, inst, block, H16, lane, offset.to_int())
    V128Store32Lane(_, _, offset, lane) =>
      lower_v128_store_lane(ctx, inst, block, S32, lane, offset.to_int())
    V128Store64Lane(_, _, offset, lane) =>
      lower_v128_store_lane(ctx, inst, block, D64, lane, offset.to_int())

    // ============ Relaxed SIMD ============
    // relaxed_swizzle: same as swizzle (TBL instruction, out-of-range gives 0)
    V128RelaxedSwizzle => lower_v128_swizzle(ctx, inst, block)

    // relaxed_trunc: same as trunc_sat (the relaxation is for NaN behavior)
    V128RelaxedTruncF32toI32S =>
      lower_v128_unary(ctx, inst, block, SIMDFCvtToIntS(true))
    V128RelaxedTruncF32toI32U =>
      lower_v128_unary(ctx, inst, block, SIMDFCvtToIntU(true))
    V128RelaxedTruncF64toI32SZero =>
      lower_v128_unary(ctx, inst, block, SIMDTruncSatF64ToI32SZero)
    V128RelaxedTruncF64toI32UZero =>
      lower_v128_unary(ctx, inst, block, SIMDTruncSatF64ToI32UZero)

    // relaxed_madd/nmadd: fused multiply-add/subtract
    V128RelaxedMaddF32 => lower_v128_fma(ctx, inst, block, true, false)
    V128RelaxedNmaddF32 => lower_v128_fma(ctx, inst, block, true, true)
    V128RelaxedMaddF64 => lower_v128_fma(ctx, inst, block, false, false)
    V128RelaxedNmaddF64 => lower_v128_fma(ctx, inst, block, false, true)

    // relaxed_laneselect: same as bitselect (BSL instruction)
    V128RelaxedLaneselect8 => lower_v128_ternary(ctx, inst, block, SIMDBsl)
    V128RelaxedLaneselect16 => lower_v128_ternary(ctx, inst, block, SIMDBsl)
    V128RelaxedLaneselect32 => lower_v128_ternary(ctx, inst, block, SIMDBsl)
    V128RelaxedLaneselect64 => lower_v128_ternary(ctx, inst, block, SIMDBsl)

    // relaxed_min/max: use FMIN/FMAX (relaxation is for NaN propagation)
    V128RelaxedMinF32 => lower_v128_binary(ctx, inst, block, SIMDFMin(true))
    V128RelaxedMaxF32 => lower_v128_binary(ctx, inst, block, SIMDFMax(true))
    V128RelaxedMinF64 => lower_v128_binary(ctx, inst, block, SIMDFMin(false))
    V128RelaxedMaxF64 => lower_v128_binary(ctx, inst, block, SIMDFMax(false))

    // relaxed_q15mulr_s: same as q15mulr_s (SQRDMULH instruction)
    V128RelaxedQ15MulrS => lower_v128_binary(ctx, inst, block, SIMDQ15MulrSat)

    // relaxed_dot products
    V128RelaxedDot8to16S =>
      lower_v128_binary(ctx, inst, block, SIMDRelaxedDot8to16)
    V128RelaxedDot8to32AddS => lower_v128_relaxed_dot_add(ctx, inst, block)
  }
}

///|
/// Convert IR IntCC to MachV CmpKind
fn ir_intcc_to_cmp_kind(cc : @milkir.IntCC) -> @instr.CmpKind {
  match cc {
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
/// Lower integer comparison
fn lower_icmp(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  cc : @milkir.IntCC,
) -> Unit {
  if inst.first_result() is Some(result) {
    // Skip if this Icmp will be fused with a Select (to avoid redundant Cmp)
    if ctx.is_fused_icmp_result(result.id) {
      return
    }
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let kind = ir_intcc_to_cmp_kind(cc)
    // Determine is_64 from operand type, not result type (result is always i32)
    // Reference types (FuncRef, ExternRef) are also 64-bit values
    let is_64 = match inst.operands[0].ty {
      I64 | FuncRef | ExternRef => true
      _ => false
    }
    let machv_inst = @instr.MachVInst::new(Cmp(kind, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    if ctx.isa is AArch64 && is_const_zero_value(ctx, inst.operands[1]) {
      // Cranelift-style zero-compare fast path: use xzr/wzr directly and
      // avoid materializing an explicit zero register.
      machv_inst.add_use(Physical({ index: 31, class: Int }))
    } else {
      let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
      machv_inst.add_use(Virtual(rhs))
    }
    block.add_inst(machv_inst)
  }
}

///|
/// Convert IR FloatCC to MachV FCmpKind
fn ir_floatcc_to_fcmp_kind(cc : @milkir.FloatCC) -> @instr.FCmpKind {
  match cc {
    Eq => Eq
    Ne => Ne
    Lt => Lt
    Le => Le
    Gt => Gt
    Ge => Ge
  }
}

///|
/// Lower float comparison
fn lower_fcmp(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  cc : @milkir.FloatCC,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let kind = ir_floatcc_to_fcmp_kind(cc)
    let machv_inst = @instr.MachVInst::new(FCmp(kind))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower a terminator
fn lower_terminator(
  ctx : LoweringContext,
  term : @milkir.Terminator,
  block : @block.MachVBlock,
) -> Unit {
  match term {
    Jump(target, args) => {
      let target_id = ctx.get_block_id(target)

      // Lower SSA block arguments directly onto the terminator.
      // The target block's params are created during lower_function; we rely on
      // bundle merging to coalesce param vregs with their incoming args.
      let regs : Array[@abi.Reg] = []
      for a in args {
        regs.push(Virtual(ctx.get_vreg_for_use(a, block)))
      }
      block.set_terminator(Jump(target_id, regs))
    }
    Branch(cond, true_target, _true_args, false_target, _false_args) =>
      // TODO(milkir): MachV MachV currently has no edge-argument branch
      // terminator. Lower branch arguments through explicit block-param copies.
      block.set_terminator(
        Branch(
          Virtual(ctx.get_vreg_for_use(cond, block)),
          ctx.get_block_id(true_target),
          ctx.get_block_id(false_target),
        ),
      )
    Brz(cond, then_block, else_block) => {
      let then_id = ctx.get_block_id(then_block)
      let else_id = ctx.get_block_id(else_block)
      // brz means branch if zero, so:
      // - If condition is from icmp, invert the condition for BranchCmp/BranchCmpImm
      // - Otherwise use BranchZero with is_nonzero=false
      if match_icmp_value(ctx, cond) is Some((lhs, rhs, cc)) {
        // Brz(icmp(cc, a, b)) = branch to then if icmp result is 0 (i.e., condition is false)
        // So we need to branch to else_block if condition is true, then_block if false
        // This means: BranchCmp with swapped targets
        let machv_cond = intcc_to_cond(cc)
        // Determine is_64 from operand type (same as lower_icmp)
        let is_64 = match lhs.ty {
          I64 | FuncRef | ExternRef => true
          _ => false
        }
        // Try to use BranchCmpImm if RHS is a valid immediate
        if match_add_imm_value(ctx, rhs) is Some(imm) {
          let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
          // Note: swapped - branch to else_id if condition is true
          block.set_terminator(
            BranchCmpImm(
              Virtual(lhs_vreg),
              imm.to_int(),
              machv_cond,
              is_64,
              else_id,
              then_id,
            ),
          )
        } else {
          let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
          let rhs_vreg = ctx.get_vreg_for_use(rhs, block)
          // Note: swapped - branch to else_id if condition is true
          block.set_terminator(
            BranchCmp(
              Virtual(lhs_vreg),
              Virtual(rhs_vreg),
              machv_cond,
              is_64,
              else_id,
              then_id,
            ),
          )
        }
      } else {
        // Use BranchZero: branch to then_block if reg is zero
        // Condition result is always i32, so is_64=false
        let cond_vreg = ctx.get_vreg_for_use(cond, block)
        block.set_terminator(
          BranchZero(Virtual(cond_vreg), false, false, then_id, else_id),
        )
      }
    }
    Brnz(cond, then_block, else_block) => {
      let then_id = ctx.get_block_id(then_block)
      let else_id = ctx.get_block_id(else_block)
      // brnz means branch if nonzero, so:
      // - If condition is from icmp, use BranchCmp/BranchCmpImm directly
      // - Otherwise use BranchZero with is_nonzero=true
      if match_icmp_value(ctx, cond) is Some((lhs, rhs, cc)) {
        // Brnz(icmp(cc, a, b)) = branch to then if icmp result is nonzero (i.e., condition is true)
        let machv_cond = intcc_to_cond(cc)
        // Determine is_64 from operand type (same as lower_icmp)
        let is_64 = match lhs.ty {
          I64 | FuncRef | ExternRef => true
          _ => false
        }
        // Try to use BranchCmpImm if RHS is a valid immediate
        if match_add_imm_value(ctx, rhs) is Some(imm) {
          let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
          block.set_terminator(
            BranchCmpImm(
              Virtual(lhs_vreg),
              imm.to_int(),
              machv_cond,
              is_64,
              then_id,
              else_id,
            ),
          )
        } else {
          let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
          let rhs_vreg = ctx.get_vreg_for_use(rhs, block)
          block.set_terminator(
            BranchCmp(
              Virtual(lhs_vreg),
              Virtual(rhs_vreg),
              machv_cond,
              is_64,
              then_id,
              else_id,
            ),
          )
        }
      } else {
        // Use BranchZero: branch to then_block if reg is nonzero
        // Condition result is always i32, so is_64=false
        let cond_vreg = ctx.get_vreg_for_use(cond, block)
        block.set_terminator(
          BranchZero(Virtual(cond_vreg), true, false, then_id, else_id),
        )
      }
    }
    Return(values) => {
      let regs : Array[@abi.Reg] = []
      for v in values {
        regs.push(Virtual(ctx.get_vreg_for_use(v, block)))
      }
      block.set_terminator(Return(regs))
    }
    Trap(msg) | TrapExit(msg) =>
      block.set_terminator(Trap(ctx.trap_payload(msg)))
    BrTable(index, targets, default) => {
      let index_vreg = ctx.get_vreg_for_use(index, block)
      let default_id = ctx.get_block_id(default)
      // WebAssembly br_table index is i32, but check IR type to be safe
      let is_64 = index.ty is I64
      if targets.is_empty() {
        // No targets, just jump to default
        block.set_terminator(Jump(default_id, []))
      } else if targets.length() < 4 {
        // Small number of targets: use comparison chain (more efficient)
        let chain_blocks : Array[@block.MachVBlock] = []
        for _ in 0..<(targets.length() - 1) {
          chain_blocks.push(ctx.machv_func.new_block())
        }

        // First comparison in original block
        let cmp_result_0 = ctx.machv_func.new_vreg(Int)
        let zero_vreg = ctx.machv_func.new_vreg(Int)
        let load_zero = @instr.MachVInst::new(LoadConst(0L))
        load_zero.add_def({ reg: Virtual(zero_vreg) })
        block.add_inst(load_zero)
        let cmp_inst_0 = @instr.MachVInst::new(Cmp(Eq, is_64))
        cmp_inst_0.add_def({ reg: Virtual(cmp_result_0) })
        cmp_inst_0.add_use(Virtual(index_vreg))
        cmp_inst_0.add_use(Virtual(zero_vreg))
        block.add_inst(cmp_inst_0)
        let target_0_id = ctx.get_block_id(targets[0])
        if targets.length() == 1 {
          block.set_terminator(
            Branch(Virtual(cmp_result_0), target_0_id, default_id),
          )
        } else {
          block.set_terminator(
            Branch(Virtual(cmp_result_0), target_0_id, chain_blocks[0].id),
          )
        }

        // Chain blocks for remaining targets
        for i in 1..<targets.length() {
          let chain_block = chain_blocks[i - 1]
          let target_id = ctx.get_block_id(targets[i])
          let const_vreg = ctx.machv_func.new_vreg(Int)
          let load_const = @instr.MachVInst::new(LoadConst(i.to_int64()))
          load_const.add_def({ reg: Virtual(const_vreg) })
          chain_block.add_inst(load_const)
          let cmp_result = ctx.machv_func.new_vreg(Int)
          let cmp_inst = @instr.MachVInst::new(Cmp(Eq, is_64))
          cmp_inst.add_def({ reg: Virtual(cmp_result) })
          cmp_inst.add_use(Virtual(index_vreg))
          cmp_inst.add_use(Virtual(const_vreg))
          chain_block.add_inst(cmp_inst)
          if i == targets.length() - 1 {
            chain_block.set_terminator(
              Branch(Virtual(cmp_result), target_id, default_id),
            )
          } else {
            chain_block.set_terminator(
              Branch(Virtual(cmp_result), target_id, chain_blocks[i].id),
            )
          }
        }
      } else {
        // Large number of targets: use jump table (O(1) dispatch)
        let target_ids : Array[Int] = []
        for target in targets {
          target_ids.push(ctx.get_block_id(target))
        }
        block.set_terminator(
          BrTable(Virtual(index_vreg), target_ids, default_id),
        )
      }
    }
  }
}

// NOTE: lower_global_get, lower_global_set are removed
// These operations are desugared via FuncEnvironment at IR level to LoadPtr/StorePtr

// ============ Raw Pointer Operations (for trampolines) ============

///|
/// Lower load_ptr instruction (raw pointer load without bounds checking)
/// Used in trampolines to load arguments from values_vec
fn lower_load_ptr(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  ty : @milkir.Type,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Convert IR type to MachV memory type and get access size
  let mem_ty = ir_type_to_mem_type(ty)
  let access_size = match ty {
    I32 | F32 => 4
    I64 | F64 | Ptr | Ref | FuncRef | ExternRef => 8
    V128 => 16
  }

  // Get the base pointer and offset from operands
  // operand 0 = base pointer
  // operand 1 = offset constant (optional)
  let base_value = inst.operands[0]

  // Check if we have an offset from a second operand (must be an iconst)
  let explicit_offset = if inst.operands.length() > 1 {
    if find_defining_inst(ctx, inst.operands[1]) is Some(def_inst) &&
      def_inst.opcode is Iconst(off) {
      off
    } else {
      0L
    }
  } else {
    0L
  }
  // Try Cranelift-style register-offset addressing:
  //   load [base + (extend/ishl index)] => load_regoff base, index, (ext/scale)
  //
  // On amd64, we support scales 0..3 and lower extends through regoffset as well.
  let isa = ctx.isa
  let is_amd64 = isa is AMD64
  let allow_nonzero_regoff = is_amd64
  if (mem_ty is I32 || mem_ty is I64) &&
    match_addr_reg_offset(ctx, base_value, access_size)
    is Some((am_base, am_index, ext, shift, _, extra_offset, has_extra)) &&
    (allow_nonzero_regoff || explicit_offset + extra_offset == 0L || has_extra) &&
    prefer_reg_offset_for_index(
      ctx, am_index, access_size, explicit_offset, extra_offset, has_extra,
    ) &&
    (!is_amd64 || (shift >= 0 && shift <= 3)) {
    let fused_offset = explicit_offset + extra_offset
    let mut regoff_ext = ext
    let (base, index, regoff_offset) = if is_amd64 &&
      is_valid_load_store_offset_for_isa(isa, fused_offset, access_size) {
      (
        ctx.get_vreg_for_use(am_base, block),
        ctx.get_vreg_for_use(am_index, block),
        fused_offset.to_int(),
      )
    } else {
      let base0 = ctx.get_vreg_for_use(am_base, block)
      let index0 = ctx.get_vreg_for_use(am_index, block)
      // V8 Liftoff (arm64 GetMemOp) materializes base+imm first, then applies
      // register offset with UXTW/LSL. Keep AArch64 on that shape.
      if !is_amd64 {
        let adjusted_base = get_adjusted_base_with_offset(
          ctx, block, base0, fused_offset,
        )
        (adjusted_base, index0, 0)
      } else if get_adjusted_regoff_index_with_offset(
          ctx, block, index0, ext, shift, fused_offset,
        )
        is Some((adjusted_index, adjusted_ext)) {
        regoff_ext = adjusted_ext
        (base0, adjusted_index, 0)
      } else {
        let adjusted_base = get_adjusted_base_with_offset(
          ctx, block, base0, fused_offset,
        )
        (adjusted_base, index0, 0)
      }
    }
    let load_inst = @instr.MachVInst::new(
      LoadPtrRegOffset(mem_ty, regoff_ext, shift, regoff_offset),
    )
    load_inst.add_def({ reg: Virtual(result_vreg) })
    load_inst.add_use(Virtual(base))
    load_inst.add_use(Virtual(index))
    block.add_inst(load_inst)
    return
  }

  // Try to fold address calculation: if base is iadd(real_base, const),
  // we can fold the const into the load offset
  let (actual_base_value, total_offset) = if match_iadd_const(ctx, base_value)
    is Some((real_base, addr_offset)) {
    let combined = explicit_offset + addr_offset
    if is_valid_load_store_offset(ctx, combined, access_size) {
      (real_base, combined.to_int())
    } else {
      // Offset too large or unaligned, can't fold
      (base_value, explicit_offset.to_int())
    }
  } else {
    (base_value, explicit_offset.to_int())
  }
  let base = ctx.get_vreg_for_use(actual_base_value, block)

  // Create LoadPtr instruction
  let load_inst = @instr.MachVInst::new(LoadPtr(mem_ty, total_offset))
  load_inst.add_def({ reg: Virtual(result_vreg) })
  load_inst.add_use(Virtual(base))
  block.add_inst(load_inst)
}

///|
/// Lower store_ptr instruction (raw pointer store without bounds checking)
/// Used in trampolines to store results to values_vec
fn lower_store_ptr(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  ty : @milkir.Type,
) -> Unit {
  // operand 0 = base pointer
  // operand 1 = value to store
  // operand 2 = offset constant (optional)
  guard inst.operands.length() >= 2 else { return }

  // Convert IR type to MachV memory type and get access size
  let mem_ty = ir_type_to_mem_type(ty)
  let access_size = match ty {
    I32 | F32 => 4
    I64 | F64 | Ptr | Ref | FuncRef | ExternRef => 8
    V128 => 16
  }
  let base_value = inst.operands[0]
  let store_value = inst.operands[1]

  // Check if we have an offset from a third operand
  let explicit_offset = if inst.operands.length() > 2 {
    if find_defining_inst(ctx, inst.operands[2]) is Some(def_inst) &&
      def_inst.opcode is Iconst(off) {
      off
    } else {
      0L
    }
  } else {
    0L
  }
  // Try Cranelift-style register-offset addressing for stores.
  let isa = ctx.isa
  let is_amd64 = isa is AMD64
  let allow_nonzero_regoff = is_amd64
  if (mem_ty is I32 || mem_ty is I64) &&
    match_addr_reg_offset(ctx, base_value, access_size)
    is Some((am_base, am_index, ext, shift, _, extra_offset, has_extra)) &&
    (allow_nonzero_regoff || explicit_offset + extra_offset == 0L || has_extra) &&
    prefer_reg_offset_for_index(
      ctx, am_index, access_size, explicit_offset, extra_offset, has_extra,
    ) &&
    (!is_amd64 || (shift >= 0 && shift <= 3)) {
    let fused_offset = explicit_offset + extra_offset
    let mut regoff_ext = ext
    let (base, index, regoff_offset) = if is_amd64 &&
      is_valid_load_store_offset_for_isa(isa, fused_offset, access_size) {
      (
        ctx.get_vreg_for_use(am_base, block),
        ctx.get_vreg_for_use(am_index, block),
        fused_offset.to_int(),
      )
    } else {
      let base0 = ctx.get_vreg_for_use(am_base, block)
      let index0 = ctx.get_vreg_for_use(am_index, block)
      // Align AArch64 regoff shape with V8 Liftoff: add immediate on base.
      if !is_amd64 {
        let adjusted_base = get_adjusted_base_with_offset(
          ctx, block, base0, fused_offset,
        )
        (adjusted_base, index0, 0)
      } else if get_adjusted_regoff_index_with_offset(
          ctx, block, index0, ext, shift, fused_offset,
        )
        is Some((adjusted_index, adjusted_ext)) {
        regoff_ext = adjusted_ext
        (base0, adjusted_index, 0)
      } else {
        let adjusted_base = get_adjusted_base_with_offset(
          ctx, block, base0, fused_offset,
        )
        (adjusted_base, index0, 0)
      }
    }
    let value = ctx.get_vreg_for_use(store_value, block)
    let store_inst = @instr.MachVInst::new(
      StorePtrRegOffset(mem_ty, regoff_ext, shift, regoff_offset),
    )
    store_inst.add_use(Virtual(base))
    store_inst.add_use(Virtual(index))
    store_inst.add_use(Virtual(value))
    block.add_inst(store_inst)
    return
  }

  // Try to fold address calculation: if base is iadd(real_base, const),
  // we can fold the const into the store offset
  let (actual_base_value, total_offset) = if match_iadd_const(ctx, base_value)
    is Some((real_base, addr_offset)) {
    let combined = explicit_offset + addr_offset
    if is_valid_load_store_offset(ctx, combined, access_size) {
      (real_base, combined.to_int())
    } else {
      // Offset too large or unaligned, can't fold
      (base_value, explicit_offset.to_int())
    }
  } else {
    (base_value, explicit_offset.to_int())
  }
  let base = ctx.get_vreg_for_use(actual_base_value, block)
  let value = ctx.get_vreg_for_use(store_value, block)

  // Create StorePtr instruction
  let store_inst = @instr.MachVInst::new(StorePtr(mem_ty, total_offset))
  store_inst.add_use(Virtual(base))
  store_inst.add_use(Virtual(value))
  block.add_inst(store_inst)
}

///|
/// Lower load_ptr_narrow instruction (raw pointer narrow load without bounds checking)
/// Used by FuncEnvironment for memory loads
fn lower_load_ptr_narrow(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  _result_ty : @milkir.Type,
  bits : Int,
  signed : Bool,
) -> Unit {
  // operand 0 = base pointer
  // operand 1 = offset constant
  guard inst.operands.length() >= 1 else { return }
  guard inst.first_result() is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Access size in bytes
  let access_size = bits / 8
  let base_value = inst.operands[0]

  // Check if we have an offset from a second operand
  let explicit_offset = if inst.operands.length() > 1 {
    if find_defining_inst(ctx, inst.operands[1]) is Some(def_inst) &&
      def_inst.opcode is Iconst(off) {
      off
    } else {
      0L
    }
  } else {
    0L
  }

  // Cranelift-style narrow register-offset addressing:
  //   load{8,16,32} [base + index{,extend}{,scale}]
  let isa = ctx.isa
  let is_aarch64 = isa is AArch64
  let is_amd64 = isa is AMD64
  let allow_nonzero_regoff = is_amd64
  if (is_aarch64 || is_amd64) &&
    match_addr_reg_offset(ctx, base_value, access_size)
    is Some((am_base, am_index, ext, shift, _, extra_offset, has_extra)) &&
    (!is_amd64 || (shift >= 0 && shift <= 3)) &&
    (allow_nonzero_regoff || explicit_offset + extra_offset == 0L || has_extra) &&
    prefer_reg_offset_for_index(
      ctx, am_index, access_size, explicit_offset, extra_offset, has_extra,
    ) {
    let fused_offset = explicit_offset + extra_offset
    let mut regoff_ext = ext
    let (base, index, regoff_offset) = if is_amd64 &&
      is_valid_load_store_offset_for_isa(isa, fused_offset, access_size) {
      (
        ctx.get_vreg_for_use(am_base, block),
        ctx.get_vreg_for_use(am_index, block),
        fused_offset.to_int(),
      )
    } else {
      let base0 = ctx.get_vreg_for_use(am_base, block)
      let index0 = ctx.get_vreg_for_use(am_index, block)
      if !is_amd64 {
        let adjusted_base = get_adjusted_base_with_offset(
          ctx, block, base0, fused_offset,
        )
        (adjusted_base, index0, 0)
      } else if get_adjusted_regoff_index_with_offset(
          ctx, block, index0, ext, shift, fused_offset,
        )
        is Some((adjusted_index, adjusted_ext)) {
        regoff_ext = adjusted_ext
        (base0, adjusted_index, 0)
      } else {
        let adjusted_base = get_adjusted_base_with_offset(
          ctx, block, base0, fused_offset,
        )
        (adjusted_base, index0, 0)
      }
    }
    let load_inst = @instr.MachVInst::new(
      LoadPtrNarrowRegOffset(bits, signed, regoff_ext, shift, regoff_offset),
    )
    load_inst.add_def({ reg: Virtual(result_vreg) })
    load_inst.add_use(Virtual(base))
    load_inst.add_use(Virtual(index))
    block.add_inst(load_inst)
    return
  }

  // Try to fold address calculation: if base is iadd(real_base, const),
  // we can fold the const into the load offset
  let (actual_base_value, total_offset) = if match_iadd_const(ctx, base_value)
    is Some((real_base, addr_offset)) {
    let combined = explicit_offset + addr_offset
    if is_valid_load_store_offset(ctx, combined, access_size) {
      (real_base, combined.to_int())
    } else {
      (base_value, explicit_offset.to_int())
    }
  } else {
    (base_value, explicit_offset.to_int())
  }
  let base = ctx.get_vreg_for_use(actual_base_value, block)

  // Create LoadPtrNarrow instruction
  let load_inst = @instr.MachVInst::new(
    LoadPtrNarrow(bits, signed, total_offset),
  )
  load_inst.add_def({ reg: Virtual(result_vreg) })
  load_inst.add_use(Virtual(base))
  block.add_inst(load_inst)
}

///|
/// Lower store_ptr_narrow instruction (raw pointer narrow store without bounds checking)
/// Used by FuncEnvironment for memory stores
fn lower_store_ptr_narrow(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  bits : Int,
) -> Unit {
  // operand 0 = base pointer
  // operand 1 = value to store
  // operand 2 = offset constant (optional)
  guard inst.operands.length() >= 2 else { return }

  // Access size in bytes
  let access_size = bits / 8
  let base_value = inst.operands[0]
  let store_value = inst.operands[1]

  // Check if we have an offset from a third operand
  let explicit_offset = if inst.operands.length() > 2 {
    if find_defining_inst(ctx, inst.operands[2]) is Some(def_inst) &&
      def_inst.opcode is Iconst(off) {
      off
    } else {
      0L
    }
  } else {
    0L
  }

  // Cranelift-style narrow register-offset addressing:
  //   store{8,16,32} [base + index{,extend}{,scale}]
  let isa = ctx.isa
  let is_aarch64 = isa is AArch64
  let is_amd64 = isa is AMD64
  let allow_nonzero_regoff = is_amd64
  if (is_aarch64 || is_amd64) &&
    match_addr_reg_offset(ctx, base_value, access_size)
    is Some((am_base, am_index, ext, shift, _, extra_offset, has_extra)) &&
    (!is_amd64 || (shift >= 0 && shift <= 3)) &&
    (allow_nonzero_regoff || explicit_offset + extra_offset == 0L || has_extra) &&
    prefer_reg_offset_for_index(
      ctx, am_index, access_size, explicit_offset, extra_offset, has_extra,
    ) {
    let fused_offset = explicit_offset + extra_offset
    let mut regoff_ext = ext
    let (base, index, regoff_offset) = if is_amd64 &&
      is_valid_load_store_offset_for_isa(isa, fused_offset, access_size) {
      (
        ctx.get_vreg_for_use(am_base, block),
        ctx.get_vreg_for_use(am_index, block),
        fused_offset.to_int(),
      )
    } else {
      let base0 = ctx.get_vreg_for_use(am_base, block)
      let index0 = ctx.get_vreg_for_use(am_index, block)
      if !is_amd64 {
        let adjusted_base = get_adjusted_base_with_offset(
          ctx, block, base0, fused_offset,
        )
        (adjusted_base, index0, 0)
      } else if get_adjusted_regoff_index_with_offset(
          ctx, block, index0, ext, shift, fused_offset,
        )
        is Some((adjusted_index, adjusted_ext)) {
        regoff_ext = adjusted_ext
        (base0, adjusted_index, 0)
      } else {
        let adjusted_base = get_adjusted_base_with_offset(
          ctx, block, base0, fused_offset,
        )
        (adjusted_base, index0, 0)
      }
    }
    let value = ctx.get_vreg_for_use(store_value, block)
    let store_inst = @instr.MachVInst::new(
      StorePtrNarrowRegOffset(bits, regoff_ext, shift, regoff_offset),
    )
    store_inst.add_use(Virtual(base))
    store_inst.add_use(Virtual(index))
    store_inst.add_use(Virtual(value))
    block.add_inst(store_inst)
    return
  }

  // Try to fold address calculation: if base is iadd(real_base, const),
  // we can fold the const into the store offset
  let (actual_base_value, total_offset) = if match_iadd_const(ctx, base_value)
    is Some((real_base, addr_offset)) {
    let combined = explicit_offset + addr_offset
    if is_valid_load_store_offset(ctx, combined, access_size) {
      (real_base, combined.to_int())
    } else {
      (base_value, explicit_offset.to_int())
    }
  } else {
    (base_value, explicit_offset.to_int())
  }
  let base = ctx.get_vreg_for_use(actual_base_value, block)
  let value = ctx.get_vreg_for_use(store_value, block)

  // Create StorePtrNarrow instruction
  let store_inst = @instr.MachVInst::new(StorePtrNarrow(bits, total_offset))
  store_inst.add_use(Virtual(base))
  store_inst.add_use(Virtual(value))
  block.add_inst(store_inst)
}
