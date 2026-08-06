///|
/// Branches to local labels (#486).
///
/// A branch can only be widened if the second word was reserved when it was
/// emitted, so every relative branch that can outgrow imm19 has to go through
/// `emit_fixup_branch`. Emitting a bare word and patching it directly gives a
/// branch that is short forever: re-emitting with `long_branches` on does not
/// help it, because there is still nowhere to put the long form.
///
/// That is what `emit_edges.mbt` used to do for the joins after an edge's
/// parallel moves and for every `br_table` stub. Those spans grow with the
/// program -- the switch ones with the number of cases -- so a large enough
/// switch failed to compile no matter how many times emission was retried.
///
/// These cover the label path itself. That real `br_table` shapes still work
/// once the reserved words are in place is covered by running the corpus with
/// `emit_single_pass`'s `long_branches` default flipped to `true`, which forces
/// every conditional branch through the wide form: 258/258 files and 62563
/// assertions in both JIT and interpreter mode, on 2026-08-06.

///|
/// Resolve the label fixups in `buffer` the way `patch_branches` does.
fn resolve_labels(buffer : CodeBuffer) -> Unit raise AArch64EmitError {
  for fixup in buffer.fixups {
    guard fixup.target is ToLabel(label) else { continue }
    let target = buffer.labels[label]
    if target < 0 {
      raise BranchLabelUnbound(label~)
    }
    if fixup.wide {
      patch_wide_conditional_branch(buffer, fixup.offset, target)
    } else {
      patch_relative_branch(buffer, fixup.offset, target, fixup.bits)
    }
  }
}

///|
/// `b.eq`, condition 0000.
const LABEL_TEST_BEQ : UInt = 0x54000000U

///|
/// A conditional branch to a label reserves its second word, which is the
/// whole reason the label path exists.
test "local label: an imm19 branch reserves a second word" {
  let buffer = CodeBuffer::new(long_branches=true)
  let label = buffer.new_label()
  buffer.emit_label_branch(label, 19, LABEL_TEST_BEQ)
  inspect(buffer.position(), content="8")
  inspect(buffer.read_word(4) == AARCH64_NOP, content="true")
}

///|
/// An imm26 branch does not, which is what holds a jump table's stride: the
/// `adr`/`add`/`br` sequence indexes the table one instruction per case, so a
/// stub entry gaining a word would send every case to the wrong place.
test "local label: an imm26 branch stays one word even in wide mode" {
  let buffer = CodeBuffer::new(long_branches=true)
  for _ in 0..<4 {
    let label = buffer.new_label()
    buffer.emit_label_branch(label, 26, AARCH64_BRANCH)
  }
  inspect(buffer.position(), content="16")
}

///|
/// Compact mode reserves nothing, so an ordinary function is the size it was.
test "local label: compact mode reserves nothing" {
  let buffer = CodeBuffer::new()
  let label = buffer.new_label()
  buffer.emit_label_branch(label, 19, LABEL_TEST_BEQ)
  inspect(buffer.position(), content="4")
}

///|
/// A label bound after the branch resolves to where it was bound.
test "local label: a forward branch resolves to the bind point" {
  let buffer = CodeBuffer::new()
  let label = buffer.new_label()
  buffer.emit_label_branch(label, 19, LABEL_TEST_BEQ)
  for _ in 0..<5 {
    buffer.emit_word(AARCH64_NOP)
  }
  buffer.bind_label(label)
  resolve_labels(buffer)
  // imm19 = 6 words on from the branch.
  inspect(buffer.read_word(0) == (LABEL_TEST_BEQ | (6U << 5)), content="true")
}

///|
/// The case #486 hits: the span past a switch's table and stubs runs beyond
/// imm19, and because the word was reserved the branch can still be made.
test "local label: a branch beyond imm19 takes the wide form" {
  let buffer = CodeBuffer::new(long_branches=true)
  let label = buffer.new_label()
  buffer.emit_label_branch(label, 19, LABEL_TEST_BEQ)
  let target = 1 << 21 // 2MB, past imm19's 1MB reach
  while buffer.position() < target {
    buffer.emit_word(AARCH64_NOP)
  }
  buffer.bind_label(label)
  resolve_labels(buffer)
  // b.ne +8, over the unconditional branch that carries the real distance.
  inspect(
    buffer.read_word(0) == ((LABEL_TEST_BEQ ^ 1U) | (2U << 5)),
    content="true",
  )
  let from_b = (target - 4) / 4
  inspect(
    buffer.read_word(4) == (AARCH64_BRANCH | from_b.reinterpret_as_uint()),
    content="true",
  )
}

///|
/// Without the reserved word the same span raises instead, which is the signal
/// `emit` catches to re-emit in wide mode. Before the label path existed this
/// raise came from a direct patch that the retry could not help, so the retry
/// hit it again and the compilation failed.
test "local label: compact mode reports the overflow rather than truncating" {
  let buffer = CodeBuffer::new()
  let label = buffer.new_label()
  buffer.emit_label_branch(label, 19, LABEL_TEST_BEQ)
  let target = 1 << 21
  while buffer.position() < target {
    buffer.emit_word(AARCH64_NOP)
  }
  buffer.bind_label(label)
  let overflowed = try {
    resolve_labels(buffer)
    false
  } catch {
    BranchOutOfRange(_) => true
    _ => false
  }
  inspect(overflowed, content="true")
}

///|
/// A label nobody bound is a bug in the emitter, so it is reported rather than
/// silently patched to offset zero.
test "local label: an unbound label is reported" {
  let buffer = CodeBuffer::new()
  let label = buffer.new_label()
  buffer.emit_label_branch(label, 19, LABEL_TEST_BEQ)
  let unbound = try {
    resolve_labels(buffer)
    false
  } catch {
    BranchLabelUnbound(_) => true
    _ => false
  }
  inspect(unbound, content="true")
}

///|
/// Branches over a fixed instruction sequence stay on the direct path, and the
/// bound is what keeps a data-dependent span from quietly joining them.
test "fixed span: a short skip patches, a long one is rejected" {
  let buffer = CodeBuffer::new()
  buffer.emit_word(LABEL_TEST_BEQ)
  for _ in 0..<40 {
    buffer.emit_word(AARCH64_NOP)
  }
  patch_fixed_span_branch(buffer, 0, 16, 19)
  inspect(buffer.read_word(0) == (LABEL_TEST_BEQ | (4U << 5)), content="true")
  let rejected = try {
    patch_fixed_span_branch(buffer, 0, 160, 19)
    false
  } catch {
    BranchSpanNotFixed(_) => true
    _ => false
  }
  inspect(rejected, content="true")
}
