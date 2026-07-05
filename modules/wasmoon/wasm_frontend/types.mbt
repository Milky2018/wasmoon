///|
pub(all) struct EmbeddingEnvironment {
  runtime_symbol_prefix : String
  hidden_context_type : @milkir.Type?
} derive(Debug)

///|
pub fn EmbeddingEnvironment::new(
  runtime_symbol_prefix? : String = "wasmoon",
  hidden_context_type? : @milkir.Type? = Some(Ptr),
) -> EmbeddingEnvironment {
  { runtime_symbol_prefix, hidden_context_type }
}

///|
pub fn EmbeddingEnvironment::runtime_symbol(
  self : EmbeddingEnvironment,
  name : String,
) -> @milkir.ExternalSymbol {
  @milkir.ExternalSymbol::new(self.runtime_symbol_prefix + "." + name)
}

///|
pub fn EmbeddingEnvironment::hidden_context_param(
  self : EmbeddingEnvironment,
) -> @milkir.Type? {
  self.hidden_context_type
}

///|
pub suberror LowerError {
  FunctionIndexOutOfRange(index~ : Int)
  TypeIndexOutOfRange(index~ : Int)
  NonFunctionType(index~ : Int)
  MissingCode(index~ : Int)
  UnsupportedNativeLowering(index~ : Int)
} derive(Debug, Eq)

///|
pub impl Show for LowerError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}
