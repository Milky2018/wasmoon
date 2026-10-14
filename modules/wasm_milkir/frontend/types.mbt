///|
pub type RuntimeLayout = @embedding.RuntimeLayout

///|
pub type MemoryDescriptorLayout = @embedding.MemoryDescriptorLayout

///|
pub type EmbeddingEnvironment = @embedding.EmbeddingEnvironment

///|
pub suberror LowerError {
  FunctionIndexOutOfRange(index~ : Int32)
  TypeIndexOutOfRange(index~ : Int32)
  NonFunctionType(index~ : Int32)
  MissingCode(index~ : Int32)
  UnsupportedNativeLowering(index~ : Int32, reason~ : String)
} derive(Debug, Eq)

///|
pub impl Show for LowerError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}
