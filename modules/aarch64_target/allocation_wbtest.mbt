///|
test "AArch64 reserves IP0 for stack-address finalization" {
  debug_inspect(
    [
      int_transfer_scratch(),
      stack_address_scratch(),
      int_instruction_scratch(),
      fp_transfer_scratch(),
    ],
    content="[p15:int, p16:int, p17:int, p18:fpvec]",
  )
  try require_legal_register(stack_address_scratch(), true) catch {
    error => inspect(error, content="IllegalRegister(reg=p16:int)")
  } noraise {
    _ => fail("expected IP0 to be rejected as an allocation scratch")
  }
  require_legal_register(int_transfer_scratch(), true)
  require_legal_register(int_instruction_scratch(), true)
  require_legal_register(fp_transfer_scratch(), true)
}
