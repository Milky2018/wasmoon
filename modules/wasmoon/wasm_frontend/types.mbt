///|
pub type RuntimeLayout = @embedding.RuntimeLayout

///|
pub type MemoryDescriptorLayout = @embedding.MemoryDescriptorLayout

///|
pub type EmbeddingEnvironment = @embedding.EmbeddingEnvironment

///|
pub suberror LowerError {
  FunctionIndexOutOfRange(index~ : Int)
  TypeIndexOutOfRange(index~ : Int)
  NonFunctionType(index~ : Int)
  MissingCode(index~ : Int)
  UnsupportedNativeLowering(index~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
pub impl Show for LowerError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}
