///|
pub suberror VerifyError {
  EmptyFunction
  EmptyBlock(block_id~ : Int)
} derive(Debug, Eq)

///|
pub impl Show for VerifyError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn Function::verify(self : Function) -> Unit raise VerifyError {
  if self.blocks.is_empty() {
    raise EmptyFunction
  }
  for block in self.blocks {
    if block.instructions.is_empty() {
      raise EmptyBlock(block_id=block.id)
    }
  }
}
