///|
test "native lowering preserves every sequentially consistent atomic operation" {
  let shapes : Array[(@milkir.Type, Int)] = [
    (I32, 8),
    (I32, 16),
    (I32, 32),
    (I64, 8),
    (I64, 16),
    (I64, 32),
    (I64, 64),
  ]
  for pair in shapes {
    let (ty, bits) = pair
    let builder = @milkir.FunctionBuilder("atomic_accesses")
    let pointer = builder.add_param(Ptr)
    let value = builder.add_param(ty)
    let offset = builder.iconst_i64(0L)
    builder.atomic_load(ty, bits, pointer, offset) |> ignore
    builder.atomic_store(bits, pointer, value, offset)
    let operations : Array[@milkir.AtomicRmwOp] = [
      Add,
      Sub,
      And,
      Or,
      Xor,
      Exchange,
    ]
    for operation in operations {
      builder.atomic_rmw(operation, bits, pointer, value, offset) |> ignore
    }
    builder.atomic_compare_exchange(bits, pointer, value, value, offset)
    |> ignore
    builder.atomic_fence()
    builder.return_([])
    let func = builder.finalize()
    func.verify()
    let trace = trace_lowering(func)
    let counts = [0, 0, 0, 0, 0]
    for operation in trace.operations {
      match operation {
        AtomicLoad(_) => counts[0] += 1
        AtomicStore(_) => counts[1] += 1
        AtomicRmw(_, _) => counts[2] += 1
        AtomicCompareExchange(_) => counts[3] += 1
        AtomicFence => counts[4] += 1
        _ => ()
      }
    }
    debug_inspect(counts, content="[1, 1, 6, 1, 1]")
  }
}
