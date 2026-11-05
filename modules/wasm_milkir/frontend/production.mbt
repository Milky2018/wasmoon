///|
/// Module-wide state shared while translating multiple function bodies.
pub type TranslationContext = @ir.TranslationContext

///|
fn get_func_type(
  mod_ : @types.Module,
  func_local_idx : Int32,
) -> @types.FuncType raise LowerError {
  if func_local_idx < 0 || func_local_idx >= mod_.funcs.length() {
    raise FunctionIndexOutOfRange(index=func_local_idx)
  }
  let type_idx = mod_.funcs[func_local_idx]
  if type_idx < 0 || type_idx >= mod_.types.length() {
    raise TypeIndexOutOfRange(index=type_idx)
  }
  match mod_.types[type_idx].composite {
    Func(func_type) => func_type
    _ => raise NonFunctionType(index=type_idx)
  }
}

///|
fn get_code(
  mod_ : @types.Module,
  func_local_idx : Int32,
) -> @types.FunctionCode raise LowerError {
  if func_local_idx < 0 || func_local_idx >= mod_.codes.length() {
    raise MissingCode(index=func_local_idx)
  }
  mod_.codes[func_local_idx]
}

///|
/// Translate one module function through the canonical production frontend.
pub fn translate_function(
  embedding_env : EmbeddingEnvironment,
  mod_ : @types.Module,
  func_local_idx : Int32,
  name? : String,
  memory_max_override~ : Int32? = None,
) -> @milkir.Function raise LowerError {
  get_func_type(mod_, func_local_idx) |> ignore
  get_code(mod_, func_local_idx) |> ignore
  @ir.translate_function(
    mod_,
    func_local_idx,
    embedding_env,
    name?,
    memory_max_override~,
  )
}

///|
/// Build the canonical production translation context for a decoded module.
pub fn translation_context_from_module(
  mod_ : @types.Module,
  embedding_env : EmbeddingEnvironment,
  memory_max_override~ : Int32? = None,
  func_base~ : Int32 = 0,
  import_remap~ : Array[Int32] = [],
) -> TranslationContext {
  @ir.TranslationContext::from_module(
    mod_,
    embedding_env,
    memory_max_override~,
    func_base~,
    import_remap~,
  )
}

///|
/// Build contextual contracts for validating the MilkIR emitted by `ctx`.
pub fn wasm_validation_context(
  ctx : TranslationContext,
) -> @wasm_milkir.WasmValidationContext {
  ctx.wasm_validation_context()
}

///|
/// Small leaf callee bodies for bounded O2/O3 inlining. Call only after module
/// validation, with the context constructed from this exact module.
pub fn scalar_callees(
  ctx : TranslationContext,
  module_ : @types.Module,
) -> Map[Int32, @milkir.Function] {
  ctx.scalar_callees(module_)
}

///|
/// Translate one decoded function body through the production Wasm frontend.
pub fn translate_function_body(
  ctx : TranslationContext,
  name : String,
  func_type : @types.FuncType,
  locals : ArrayView[@types.ValueType],
  body : ArrayView[@types.Instruction],
  instruction_sources~ : Array[@types.InstructionSource] = [],
) -> @milkir.Function {
  @ir.translate_function_body(
    ctx,
    name,
    func_type,
    locals,
    body,
    instruction_sources~,
  )
}
