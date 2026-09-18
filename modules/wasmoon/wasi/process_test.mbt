///|
test "CPU clocks expose positive resolution and monotonic consumed CPU time" {
  let memory = @runtime.Memory::Memory(1, None)
  for clock in [2, 3] {
    inspect(@wasi.clock_res_get(memory, clock, 0), content="0")
    assert_true(memory.read_i64(0) > 0L)
    inspect(@wasi.clock_time_get(memory, clock, 0L, 0), content="0")
    let before = memory.read_i64(0)
    inspect(@wasi.sched_yield(), content="0")
    inspect(@wasi.clock_time_get(memory, clock, 0L, 0), content="0")
    assert_true(memory.read_i64(0) >= before)
  }
}

///|
test "signal policy denies by default and never sees invalid tags" {
  inspect(@wasi.proc_raise_impl(15), content="58")
  let observed : Array[Int] = []
  let context = @wasi.WasiContextBuilder::WasiContextBuilder()
    .signal_handler(signal => {
      observed.push(signal)
      if signal == 0 {
        @wasi.raise_host_signal(signal)
      } else {
        63
      }
    })
    .build()
  inspect(@wasi.proc_raise_impl(0, handler=context.signal_handler), content="0")
  inspect(
    @wasi.proc_raise_impl(15, handler=context.signal_handler),
    content="63",
  )
  inspect(
    @wasi.proc_raise_impl(31, handler=context.signal_handler),
    content="28",
  )
  assert_eq(observed, [0, 15])
}
