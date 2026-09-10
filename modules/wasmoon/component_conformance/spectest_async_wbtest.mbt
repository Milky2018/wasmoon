///|
test "spectest slow host calls yield once and canceled calls do not wake" {
  for echo in [false, true] {
    for cancel in [false, true] {
      let linker = @runtime_impl.ComponentLinker()
      defer linker.close()
      let runtime = linker.host_runtime_state()
      let queue : Array[SpectestYield] = []
      let exports : Map[String, @runtime_impl.ComponentExtern] = Map([])
      exports.set("f", Func(make_spectest_slow_func(echo, queue)))
      let instance = make_instance("host", linker.get_store(), exports, runtime)
      let invocation = instance.start_exported_func(
        "f",
        if echo {
          [U32(42)]
        } else {
          []
        },
      )
      debug_inspect(invocation.poll(), content="InvocationPending")
      inspect(queue.length(), content="1")
      if cancel {
        invocation.cancel()
        inspect(wake_spectest_yields(queue), content="false")
      } else {
        inspect(wake_spectest_yields(queue), content="true")
        debug_inspect(
          invocation.poll(),
          content=if echo {
            "InvocationReady([U32(42)])"
          } else {
            "InvocationReady([S32(2)])"
          },
        )
      }
      inspect(wake_spectest_yields(queue), content="false")
    }
  }
}
