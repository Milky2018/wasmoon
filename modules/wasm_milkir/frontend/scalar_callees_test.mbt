///|
test "scalar callee templates use linked local indices and preserve entry polls" {
  let module_ = @types.Module::simple(
    [I32],
    [I64],
    [LocalGet(0), I64ExtendI32S],
    "extend",
  )
  module_.imports.push({ mod_name: "host", name: "imported", desc: Func(0), })
  for polling in [false, true] {
    let context = @frontend.translation_context_from_module(
      module_,
      { ..native_test_env(), cancellation_safepoints: polling, },
      func_base=10,
      import_remap=[100],
    )
    let templates = @frontend.scalar_callees(context, module_)
    assert_eq(templates.length(), 1)
    assert_false(templates.contains(100))
    let template = templates[11]
    template.verify()
    let mut has_poll_call = false
    for block in template.blocks {
      for id in template.block_instruction_ids(block) {
        if template.instruction_by_id(id).unwrap().opcode is Call(_) {
          has_poll_call = true
        }
      }
    }
    assert_eq(has_poll_call, polling)
  }
}
