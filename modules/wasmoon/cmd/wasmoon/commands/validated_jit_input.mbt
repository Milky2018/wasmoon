///|
/// Validation evidence and binary instruction positions from the same input.
/// The constructor uses the same Wasm feature policy as `compile_module`.
pub struct ValidatedJITInput {
  priv validated : @validator.ValidatedModule
  priv bytes : Bytes
  priv instruction_sources : Array[Array[@types.InstructionSource]]
}

///|
pub fn ValidatedJITInput::parse(bytes : Bytes) -> ValidatedJITInput raise {
  let (code, instruction_sources) = @parser.parse_module_with_sources(bytes)
  let validated = @validator.ValidatedModule::new(code)
  { validated, bytes, instruction_sources, }
}

///|
/// Share validation evidence with the executor. Its snapshots are independent
/// of the input used by the compiler.
pub fn ValidatedJITInput::validated_module(
  self : ValidatedJITInput,
) -> @validator.ValidatedModule {
  self.validated
}

///|
/// Compile this validated binary with its original source positions.
pub fn ValidatedJITInput::compile(
  self : ValidatedJITInput,
  opt_level~ : Int32 = 2,
  enable_dwarf~ : Bool = false,
  on_progress~ : (CompileProgress) -> Unit? = fn(_event) { None },
  enable_cancellation~ : Bool = false,
  nan_canonicalization~ : Bool = false,
) -> @artifact.Artifact? {
  compile_validated_binary_to_jit(
    self.validated.snapshot(),
    self.bytes,
    self.instruction_sources,
    @perf.tick_now(),
    opt_level~,
    enable_dwarf~,
    on_progress~,
    enable_cancellation~,
    nan_canonicalization~,
  )
}
