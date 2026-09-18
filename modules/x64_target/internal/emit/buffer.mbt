///|
/// Instruction bytes supplied by the enclosing target emitter.
pub struct CodeBuffer {
  priv code : Array[Byte]
}

///|
pub fn CodeBuffer::new(code : Array[Byte]) -> CodeBuffer {
  { code, }
}

///|
fn CodeBuffer::emit_byte(self : CodeBuffer, byte : Int) -> Unit {
  self.code.push((byte & 0xFF).to_byte())
}
