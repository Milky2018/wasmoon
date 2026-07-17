///|
test "entry trampoline IR verifies with i64 pointer carriers" {
  inspect(generate_trampoline_ir([], []).verify(), content="()")
}
