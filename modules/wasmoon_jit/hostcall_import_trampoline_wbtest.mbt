///|
test "hostcall import trampoline AArch64 helpers handle large immediates" {
  let code : Array[Int32] = []
  try! a64_emit_adjust_imm(code, 31, 31, 8192, subtract=true)
  inspect(code.length(), content="12")
  try! a64_emit_adjust_imm(code, 31, 31, 8192)
  inspect(code.length(), content="24")
}

///|
test "AArch64 split offsets accumulate across distinct registers" {
  for rd in [0, 1, 16, 17, 31] {
    for rn in [0, 1, 16, 17, 31] {
      for immediate in [0, 1, 4095, 4096, 8192, 65536] {
        for subtract in [false, true] {
          let code : Array[Int32] = []
          a64_emit_adjust_imm(code, rd, rn, immediate, subtract~)
          let registers = Array::makei(32, i => 0x123456789000L + i.to_int64())
          let initial = registers[rn]
          for index in 0..<(code.length() / 4) {
            let offset = index * 4
            let word = code[offset] |
              (code[offset + 1] << 8) |
              (code[offset + 2] << 16) |
              (code[offset + 3] << 24)
            assert_eq(word & 0x9f000000, 0x91000000)
            let destination = word & 31
            let source = (word >> 5) & 31
            let amount = ((word >> 10) & 4095).to_int64()
            registers[destination] = if (word & 0x40000000) != 0 {
              registers[source] - amount
            } else {
              registers[source] + amount
            }
          }
          assert_eq(
            registers[rd],
            if subtract {
              initial - immediate.to_int64()
            } else {
              initial + immediate.to_int64()
            },
          )
        }
      }
    }
  }
}

///|
test "hostcall import trampoline AArch64 helpers handle general offsets" {
  let unaligned_load : Array[Int32] = []
  try! a64_emit_load_slot(unaligned_load, I64, 0, 3)
  inspect(unaligned_load.length(), content="8")
  let out_of_range_vector_store : Array[Int32] = []
  try! a64_emit_store_slot(out_of_range_vector_store, V128, 0, 65536)
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
