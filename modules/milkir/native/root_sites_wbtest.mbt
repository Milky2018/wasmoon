///|
test "root sites are independent from observability and physical address stability" {
  let b = @milkir.FunctionBuilder("explicit_root_sites")
  let object = b.add_param(Ref)
  b.add_result(Ref)
  let effects : @milkir.ExtensionEffects = {
    read: Some(Control),
    write: Some(Control),
    may_trap: true,
    observable: true,
    invalidates_addresses: false,
    pointer_region: None,
    pointer_bytes: 0,
  }
  b.emit_void_ext_inst(
    ExtOp("test", "proved_charge", [], effects=Some(effects)),
    [],
  )
  b.emit_void_ext_inst(
    ExtOp("test", "unknown_stable_operation", [], effects=Some(effects)),
    [],
  )
  let symbol = b.get_function().declare_external_symbol("unknown_call")
  b.call_symbol(symbol, None, []) |> ignore
  b.return_([object])
  let function = b.finalize()
  let cfg = @milkir.CFG::build(function)
  let conservative = compute_gc_roots(function, cfg, fn(_) { false })
  let selected = compute_gc_roots(function, cfg, op => {
    op.opcode == "proved_charge"
  })
  let mut checked = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      match inst.opcode {
        Ext(op, _) => {
          assert_eq(conservative[id], [object.id])
          assert_eq(
            selected[id],
            if op.opcode == "proved_charge" {
              []
            } else {
              [object.id]
            },
          )
          checked += 1
        }
        Call(_) => {
          assert_eq(conservative[id], [object.id])
          assert_eq(selected[id], [object.id])
          checked += 1
        }
        _ => ()
      }
    }
  }
  assert_eq(checked, 3)
}
