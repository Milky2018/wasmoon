///|
test "low-bit shift encodings match independent AArch64 assembler boundaries" {
  let destination = @vcode.PhysicalReg::new(0, Int)
  let source = @vcode.PhysicalReg::new(1, Int)
  // UBFIZ encodings checked with Apple clang, including full fields and top bits.
  assert_eq(
    encode_low_bits_shift_left(W32, 13, 1, destination, source),
    0x531F3020U,
  )
  assert_eq(
    encode_low_bits_shift_left(W32, 1, 31, destination, source),
    0x53010020U,
  )
  assert_eq(
    encode_low_bits_shift_left(W32, 32, 0, destination, source),
    0x53007C20U,
  )
  assert_eq(
    encode_low_bits_shift_left(W64, 32, 1, destination, source),
    0xD37F7C20U,
  )
  assert_eq(
    encode_low_bits_shift_left(W64, 1, 63, destination, source),
    0xD3410020U,
  )
  assert_eq(
    encode_low_bits_shift_left(W64, 64, 0, destination, source),
    0xD340FC20U,
  )
}
