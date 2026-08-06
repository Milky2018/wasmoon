///|
/// Long-range conditional branches (#486).
///
/// A conditional branch reaches only +/-1MB through imm19. A function large
/// enough to exceed that used to fail to compile outright, which is what
/// #486 reports. The reserved second word lets the patch fall back to an
/// inverted short branch over an unconditional `b`, which reaches +/-128MB.
///
/// These cover the encoding. What they cannot reach is whether the reserved
/// word throws off the offsets around it, since a function that overflows
/// imm19 needs about a megabyte of code and takes minutes to compile.
///
/// To check that instead, flip `emit_single_pass`'s `long_branches` default to
/// `true` and run `scripts/run_all_wast.py --rec`. Every conditional branch
/// then takes the wide path, and the corpus exercises it 62563 times in each
/// mode. Done on 2026-08-06: all 258 files passed in both modes. The only
/// casualties are the golden-byte tests in `emit_test.mbt`, which change by
/// design -- each conditional branch gains a nop and the displacements after
/// it shift one word.

///|
/// Lay one branch at offset 0 and pad out to `target`, so the patch sees the
/// distance a real function of that size would produce.
fn wide_branch_words(
  base : UInt,
  target : Int,
) -> Array[UInt] raise AArch64EmitError {
  let buffer = CodeBuffer::new(long_branches=true)
  buffer.emit_word(base)
  buffer.emit_word(AARCH64_NOP) // the reserved slot
  while buffer.position() < target {
    buffer.emit_word(AARCH64_NOP)
  }
  patch_wide_conditional_branch(buffer, 0, target)
  [buffer.read_word(0), buffer.read_word(4)]
}

///|
/// `b.eq`, condition 0000.
const TEST_BEQ : UInt = 0x54000000U

///|
/// `cbz w0`.
const TEST_CBZ : UInt = 0x34000000U

///|
test "long branch: within imm19 keeps the short form and leaves a nop" {
  // +64 bytes is 16 words, comfortably inside imm19.
  let words = wide_branch_words(TEST_BEQ, 64)
  // b.eq with imm19 = 16, and the reserved word untouched.
  inspect(words[0] == (TEST_BEQ | (16U << 5)), content="true")
  inspect(words[1] == AARCH64_NOP, content="true")
}

///|
/// The case #486 hits: beyond imm19, so the condition inverts and jumps over
/// an unconditional branch that carries the real distance.
test "long branch: beyond imm19 inverts and branches over a b" {
  let target = 1 << 21 // 2MB, past imm19's 1MB reach
  let words = wide_branch_words(TEST_BEQ, target)
  // b.ne +8 -- the inverse of b.eq, skipping the word below.
  inspect(words[0] == ((TEST_BEQ ^ 1U) | (2U << 5)), content="true")
  // b with imm26 covering the distance from the second word, not the first.
  let from_b = (target - 4) / 4
  inspect(
    words[1] == (AARCH64_BRANCH | from_b.reinterpret_as_uint()),
    content="true",
  )
}

///|
/// cbz/cbnz reach imm19 too, and invert on a different bit than b.cond.
test "long branch: cbz inverts to cbnz" {
  let target = 1 << 21
  let words = wide_branch_words(TEST_CBZ, target)
  // cbnz w0, +8
  inspect(words[0] == ((TEST_CBZ ^ 0x01000000U) | (2U << 5)), content="true")
  let from_b = (target - 4) / 4
  inspect(
    words[1] == (AARCH64_BRANCH | from_b.reinterpret_as_uint()),
    content="true",
  )
}

///|
test "long branch: a backward target beyond imm19 also inverts" {
  let buffer = CodeBuffer::new(long_branches=true)
  let distance = 1 << 21
  while buffer.position() < distance {
    buffer.emit_word(AARCH64_NOP)
  }
  let branch = buffer.position()
  buffer.emit_word(TEST_BEQ)
  buffer.emit_word(AARCH64_NOP)
  patch_wide_conditional_branch(buffer, branch, 0)
  inspect(
    buffer.read_word(branch) == ((TEST_BEQ ^ 1U) | (2U << 5)),
    content="true",
  )
  // A negative imm26, measured from the second word, so the field is the
  // two's-complement word count.
  let words = -((distance + 4) / 4)
  inspect(
    buffer.read_word(branch + 4) ==
    (AARCH64_BRANCH | (words.reinterpret_as_uint() & 0x03FFFFFFU)),
    content="true",
  )
}

///|
/// Both conditional forms invert; anything else is rejected rather than
/// silently mangled, since only these two are ever given a reserved slot.
test "long branch: only the conditional forms invert" {
  inspect(
    invert_conditional_branch(TEST_BEQ) == Some(TEST_BEQ ^ 1U),
    content="true",
  )
  inspect(
    invert_conditional_branch(0xB4000000U) == Some(0xB5000000U),
    content="true",
  )
  inspect(
    invert_conditional_branch(0x35000000U) == Some(0x34000000U),
    content="true",
  )
  // an unconditional `b`
  inspect(invert_conditional_branch(AARCH64_BRANCH) is None, content="true")
}

///|
/// Without the reserved slot nothing changes, which is what keeps ordinary
/// functions the size they were.
test "long branch: compact emission still overflows" {
  let buffer = CodeBuffer::new()
  buffer.emit_word(TEST_BEQ)
  let target = 1 << 21
  while buffer.position() < target {
    buffer.emit_word(AARCH64_NOP)
  }
  let failed = try {
    patch_relative_branch(buffer, 0, target, 19)
    false
  } catch {
    BranchOutOfRange(_) => true
    _ => false
  }
  inspect(failed, content="true")
}
