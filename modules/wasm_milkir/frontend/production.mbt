///|
/// Module-wide state shared while translating multiple function bodies.
pub type TranslationContext = @ir.TranslationContext

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
) -> @milkir.Function {
  @ir.translate_function_body(ctx, name, func_type, locals, body)
}
