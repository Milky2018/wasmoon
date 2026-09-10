///|
test "atomic ordering preserves unused accesses and invalidates ordinary loads" {
  let builder = @milkir.FunctionBuilder("atomic_ordering")
  let pointer = builder.add_param(Ptr)
  builder.add_result(I32)
  builder.add_result(I32)
  let zero = builder.iconst_i64(0L)
  let before = builder.load_ptr(I32, pointer, zero)
  builder.atomic_load(I32, 32, pointer, zero) |> ignore
  builder.atomic_load(I32, 32, pointer, zero) |> ignore
  builder.atomic_fence()
  let after = builder.load_ptr(I32, pointer, zero)
  builder.return_([before, after])
  let func = builder.finalize()
  func.verify()
  optimize_with_level(func, O2) |> ignore
  func.verify()
  let mut loads = 0
  let mut atomics = 0
  let mut fences = 0
  for block in func.blocks {
    for index in 0..<block.instruction_count() {
      let inst = func.block_instruction_at(block, index).unwrap()
      match inst.opcode {
        Memory(Load(_)) => loads += 1
        Memory(Atomic(Load(_, _))) => atomics += 1
        Memory(Atomic(Fence)) => fences += 1
        _ => ()
      }
    }
  }
  debug_inspect((loads, atomics, fences), content="(2, 2, 1)")
}
