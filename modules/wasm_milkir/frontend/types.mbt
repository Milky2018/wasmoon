///|
pub type RuntimeLayout = @embedding.RuntimeLayout

///|
pub type MemoryDescriptorLayout = @embedding.MemoryDescriptorLayout

///|
pub type EmbeddingEnvironment = @embedding.EmbeddingEnvironment

///|
#derive(Debug, Eq)
pub suberror LowerError {
  FunctionIndexOutOfRange(index~ : Int32)
  TypeIndexOutOfRange(index~ : Int32)
  NonFunctionType(index~ : Int32)
  MissingCode(index~ : Int32)
}

///|
pub impl Show for LowerError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}
