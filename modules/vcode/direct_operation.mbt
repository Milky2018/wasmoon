///|
/// Source and liveness information for one operation, including any checks
/// emitted before its selected instruction.
#valtype
pub struct DirectOperationSource {
  priv source : @native.SourceLocation?
  priv stack_map : @native.StackMapMetadata?
  priv roots : Array[Value]
  priv semantics : @native.OperationSemantics
}

///|
pub fn DirectOperationSource::new(
  source : @native.SourceLocation?,
  stack_map : @native.StackMapMetadata?,
  roots : Array[Value],
  semantics : @native.OperationSemantics,
) -> DirectOperationSource {
  { source, stack_map, roots, semantics, }
}

///|
pub fn DirectOperationSource::metadata(
  self : DirectOperationSource,
  trap? : @native.TrapReason,
) -> InstructionMetadata {
  direct_source_metadata(
    self.source,
    self.stack_map,
    self.roots,
    self.semantics,
    trap?,
  )
}

///|
pub fn DirectOperationSource::selected_metadata(
  self : DirectOperationSource,
  operation : @lowering.Operation,
) -> InstructionMetadata {
  let trap = match operation {
    Load(spec) => spec.trap
    Store(spec) => spec.trap
    VectorLoad(spec) => spec.trap
    VectorStoreLane(spec) => spec.trap
    AtomicLoad(spec)
    | AtomicStore(spec)
    | AtomicRmw(spec, _)
    | AtomicCompareExchange(spec) => spec.trap
    _ => None
  }
  self.metadata(trap?)
}

///|
fn float_to_int_bounds(
  source : @native.FloatType,
  result : @native.IntegerType,
  signedness : @native.Signedness,
) -> (UInt64, UInt64, Bool) {
  match (source, result, signedness) {
    (F32, I32, Signed) => (0xCF000000UL, 0x4F000000UL, false)
    (F32, I32, Unsigned) => (0xBF800000UL, 0x4F800000UL, true)
    (F32, I64, Signed) => (0xDF000000UL, 0x5F000000UL, false)
    (F32, I64, Unsigned) => (0xBF800000UL, 0x5F800000UL, true)
    (F64, I32, Signed) => (0xC1E0000000200000UL, 0x41E0000000000000UL, true)
    (F64, I32, Unsigned) => (0xBFF0000000000000UL, 0x41F0000000000000UL, true)
    (F64, I64, Signed) => (0xC3E0000000000000UL, 0x43E0000000000000UL, false)
    (F64, I64, Unsigned) => (0xBFF0000000000000UL, 0x43F0000000000000UL, true)
  }
}

///|
/// Preserve NaN and range trap order before a trapping conversion. Targets
/// supply the concrete trap pseudos, which have no implicit clobbers.
pub fn[Inst] CheckedBuilder::append_float_to_int_checks(
  self : CheckedBuilder[Inst],
  block : Block,
  operand : Value,
  source : @native.FloatType,
  result : @native.IntegerType,
  signedness : @native.Signedness,
  site : DirectOperationSource,
  float_constant : (@native.ValueType, UInt64) -> Inst,
  trap_unordered : (@native.ValueType) -> Inst,
  trap_minimum : (@native.ValueType, Bool) -> Inst,
  trap_maximum : (@native.ValueType) -> Inst,
) -> Unit raise VCodeBuildError {
  let ty : @native.ValueType = match source {
    F32 => F32
    F64 => F64
  }
  self.append_body(
    block,
    trap_unordered(ty),
    [Input::any(operand)],
    [],
    [],
    site.metadata(trap=InvalidConversionToInteger),
  )
  |> ignore
  let (minimum, maximum, inclusive_minimum) = float_to_int_bounds(
    source, result, signedness,
  )
  for
    bound_check in [
      (minimum, trap_minimum(ty, inclusive_minimum)),
      (maximum, trap_maximum(ty)),
    ] {
    let (bound, trap) = bound_check
    let (_, values) = self.append_body(
      block,
      float_constant(ty, bound),
      [],
      [Output::any(ty)],
      [],
      InstructionMetadata::empty(),
    )
    self.append_body(
      block,
      trap,
      [Input::any(operand), Input::any(values[0])],
      [],
      [],
      site.metadata(trap=IntegerOverflow),
    )
    |> ignore
  }
}

///|
/// Atomic pseudos address memory at offset zero. Materialize a nonzero static
/// offset before the selected atomic instruction and leave trap metadata there.
pub fn[Inst] CheckedBuilder::materialize_atomic_address(
  self : CheckedBuilder[Inst],
  block : Block,
  operation : @lowering.Operation,
  operands : Array[Value],
  load_offset : (UInt64) -> Inst,
  add_address : Inst,
) -> Array[Value] raise VCodeBuildError {
  let offset = match operation {
    AtomicLoad(spec)
    | AtomicStore(spec)
    | AtomicRmw(spec, _)
    | AtomicCompareExchange(spec) => spec.offset
    _ => 0UL
  }
  if offset == 0UL {
    return operands
  }
  let (_, offset_values) = self.append_body(
    block,
    load_offset(offset),
    [],
    [Output::any(I64)],
    [],
    InstructionMetadata::empty(),
  )
  let (_, addresses) = self.append_body(
    block,
    add_address,
    [Input::any(operands[0]), Input::any(offset_values[0])],
    [Output::any(Ptr64)],
    [],
    InstructionMetadata::empty(),
  )
  let values = operands.copy()
  values[0] = addresses[0]
  values
}
