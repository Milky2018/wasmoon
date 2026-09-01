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
