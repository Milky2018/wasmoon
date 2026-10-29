///|
extern "c" fn test_inactive_trap_result() -> Int32 = "wasmoon_test_inactive_trap_result"

///|
test "native helper failures retain the inactive trap contract" {
  inspect(test_inactive_trap_result(), content="1")
}
