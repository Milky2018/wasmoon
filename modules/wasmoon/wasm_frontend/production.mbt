///|
/// Module-wide state shared while translating multiple function bodies.
pub type TranslationContext = @ir.TranslationContext

///|
/// Translate one module function through the canonical production frontend.
pub fn translate_function(
  embedding_env : EmbeddingEnvironment,
  mod_ : @types.Module,
  func_local_idx : Int,
  name? : String,
  memory_max_override? : Int? = None,
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
  memory_max_override? : Int? = None,
  func_base? : Int = 0,
  import_remap? : Array[Int] = [],
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
/// Translate one decoded function body through the production Wasm frontend.
pub fn translate_function_body(
  ctx : TranslationContext,
  name : String,
  func_type : @types.FuncType,
  locals : Array[@types.ValueType],
  body : Array[@types.Instruction],
) -> @milkir.Function {
  @ir.translate_function_body(ctx, name, func_type, locals, body)
}
