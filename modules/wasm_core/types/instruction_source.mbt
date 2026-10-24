///|
/// Original module-byte position of one decoded instruction. Entries are in
/// preorder; subtree_end is the exclusive entry index after nested bodies.
/// Positions are independent of semantic AST equality and encoding choices.
pub(all) struct InstructionSource {
  byte_offset : Int32
  subtree_end : Int32
} derive(Debug, Eq)

///|
pub extend InstructionSource with Debug::{to_repr}

///|
pub extend InstructionSource with Eq::{equal, not_equal}

///|
priv enum SourceWork {
  Visit(Instruction)
  End(Int32)
}

///|
/// Check that a position table describes this exact instruction-tree shape.
/// Malformed or stale tables must not shift locations onto unrelated code.
pub fn validate_instruction_sources(
  body : ArrayView[Instruction],
  sources : ArrayView[InstructionSource],
) -> Bool {
  let pending : Array[SourceWork] = []
  fn push_body(body : ArrayView[Instruction]) -> Unit {
    for i = body.length() - 1; i >= 0; i = i - 1 {
      pending.push(Visit(body[i]))
    }
  }
  push_body(body)
  let mut cursor = 0
  let mut previous_offset = -1
  while pending.pop() is Some(work) {
    match work {
      End(expected) => if cursor != expected { return false }
      Visit(instruction) => {
        guard cursor < sources.length() else { return false }
        let source = sources[cursor]
        guard source.byte_offset > previous_offset &&
          source.subtree_end > cursor &&
          source.subtree_end <= sources.length() else {
          return false
        }
        previous_offset = source.byte_offset
        cursor += 1
        pending.push(End(source.subtree_end))
        match instruction {
          Block(_, body) | Loop(_, body) | TryTable(_, _, body) =>
            push_body(body)
          If(_, then_body, else_body) => {
            push_body(else_body)
            push_body(then_body)
          }
          _ => ()
        }
      }
    }
  }
  cursor == sources.length()
}
