///|
test "trusted core lowering skips redundant input validation" {
  let function_builder = @milkir.FunctionBuilder::FunctionBuilder("trusted")
  function_builder.return_([])
  let function = function_builder.finalize()
  let next_value = Ref(0)
  let sink = @lowering.TargetSink::new(
    fn() { [] },
    fn() { 0 },
    fn(types) {
      let values = types.map(_ => {
        let value = next_value.val
        next_value.val += 1
        value
      })
      (1, values)
    },
    fn(_, _) { 0 },
    fn(_) { () },
    fn(_, _, _, result_types, _, _, _) {
      result_types.map(_ => {
        let value = next_value.val
        next_value.val += 1
        value
      })
    },
    fn(_, _, _) { () },
    fn() { () },
  )
  let events : Array[NativeLowerEvent] = []
  lower_core_to_sink(function, sink, verify_input=false, on_event=fn(event) {
    events.push(event)
  })
  debug_inspect(
    events,
    content="[TargetConstructionStarted, NativeLoweringFinished]",
  )
}

///|
test "GC-free functions skip reference liveness while unknown calls retain it" {
  for call in [false, true] {
    let b = @milkir.FunctionBuilder::FunctionBuilder("reference_liveness")
    let reference = b.add_param(Ref)
    b.add_result(Ref)
    if call {
      let symbol = b.get_function().declare_external_symbol("unknown_host")
      b.call_symbol(symbol, None, []) |> ignore
    }
    b.return_([reference])
    let analyses = Ref(0)
    trace_lowering(b.finalize(), on_event=fn(event) {
      if event is PreparationStarted(name="native_gc_liveness") {
        analyses.val += 1
      }
    })
    |> ignore
    assert_eq(analyses.val, if call { 1 } else { 0 })
  }
}
