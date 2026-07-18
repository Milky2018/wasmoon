///|
test "hostcall import trampoline AArch64 helpers handle large immediates" {
  let code : Array[Int] = []
  try! a64_emit_sub_imm(code, 31, 31, 8192)
  inspect(code.length(), content="12")
  try! a64_emit_add_imm(code, 31, 31, 8192)
  inspect(code.length(), content="24")
}

///|
test "hostcall import trampoline AArch64 helpers handle general offsets" {
  let unaligned_load : Array[Int] = []
  try! a64_emit_ldr_x(unaligned_load, 0, 31, 3)
  inspect(unaligned_load.length(), content="8")
  let out_of_range_vector_store : Array[Int] = []
  try! a64_emit_str_q(out_of_range_vector_store, 0, 31, 65536)
  inspect(out_of_range_vector_store.length() > 4, content="true")
  inspect(
    out_of_range_vector_store[out_of_range_vector_store.length() - 1],
    content="61",
  )
}

///|
test "x64 hostcall trampolines align the stack before C bridge calls" {
  inspect(x64_hostcall_stack_adjust(0), content="8")
  inspect(x64_hostcall_stack_adjust(8), content="24")
  inspect(x64_hostcall_stack_adjust(16), content="24")
  inspect(x64_hostcall_stack_adjust(17), content="40")
}
