///|
test "AArch64 reserves IP0 for stack-address finalization" {
  debug_inspect(
    [stack_address_scratch(), int_transfer_scratch()],
    content="[p16:int, p17:int]",
  )
  try require_legal_register(stack_address_scratch(), true) catch {
    error => inspect(error, content="IllegalRegister(reg=p16:int)")
  } noraise {
    _ => fail("expected IP0 to be rejected as an allocation scratch")
  }
  require_legal_register(int_transfer_scratch(), true)
}
