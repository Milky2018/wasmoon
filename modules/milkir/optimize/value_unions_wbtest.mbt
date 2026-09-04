///|
test "scoped optimizer unions are typed and roll back at dominance boundaries" {
  let func = @milkir.Function::new_empty("scoped_value_unions")
  let root = func.new_value(I32)
  let child = func.new_value(I32)
  let grandchild = func.new_value(I32)
  let session = OptimizerSession::new(func)
  session.record_alias(child, root)
  inspect(session.canonical_value(child).id, content=root.id.to_string())
  let scope = session.begin_scope()
  session.record_alias(grandchild, child)
  inspect(session.canonical_value(grandchild).id, content=root.id.to_string())
  inspect(session.canonical_value(grandchild).ty == I32, content="true")
  session.end_scope(scope)
  inspect(
    session.canonical_value(grandchild).id,
    content=grandchild.id.to_string(),
  )
  inspect(session.canonical_value(child).id, content=root.id.to_string())
}

///|
test "optimizer candidate scopes commit or tombstone unplaced DFG nodes" {
  let discarded = @milkir.Function::new_empty("discard_candidate")
  let discarded_entry = discarded.new_block0()
  discarded_entry.set_terminator(Return([]))
  let discarded_session = OptimizerSession::new(discarded)
  let discarded_marker = discarded_session.begin_candidates()
  inspect(
    discarded_session.stage_pure_candidate(Scalar(IntConst(7L)), [], I32)
    is Some(_),
    content="true",
  )
  discarded_session.discard_candidates(discarded_marker)
  inspect(discarded.verify(), content="()")

  let committed = @milkir.Function::new_empty("commit_candidate")
  committed.add_result(I32)
  let committed_entry = committed.new_block0()
  let committed_session = OptimizerSession::new(committed)
  let committed_marker = committed_session.begin_candidates()
  guard committed_session.stage_pure_candidate(Scalar(IntConst(9L)), [], I32)
    is Some(value) else {
    fail("pure candidate was rejected")
  }
  let placement : Array[@milkir.Inst] = []
  committed_session.commit_candidates(committed_marker, placement)
  for inst in placement {
    committed_entry.append_inst(inst)
  }
  committed_entry.set_terminator(Return([value]))
  inspect(committed.verify(), content="()")
}

///|
test "optimizer candidate scopes reject effectful instructions before staging" {
  let func = @milkir.Function::new_empty("reject_effectful_candidate")
  let entry = func.new_block0()
  entry.set_terminator(Return([]))
  let session = OptimizerSession::new(func)
  let marker = session.begin_candidates()
  inspect(
    session.stage_pure_candidate(Memory(Load(I32)), [], I32) is None,
    content="true",
  )
  session.discard_candidates(marker)
  inspect(func.verify(), content="()")
}

///|
test "optimizer candidate extraction rejects equal-cost alternatives" {
  let func = @milkir.Function::new_empty("reject_equal_cost_candidate")
  let input = func.add_param(I32)
  func.add_result(I32)
  let entry = func.new_block0()
  entry.set_terminator(Return([input]))
  let session = OptimizerSession::new(func)
  let marker = session.begin_candidates()
  guard session.stage_pure_candidate(
      Scalar(IntBinary(Add)),
      [input, input],
      I32,
    )
    is Some(_) else {
    fail("pure candidate was rejected")
  }
  let placement : Array[@milkir.Inst] = []
  inspect(
    session.commit_candidates_if_cheaper(marker, 1, placement),
    content="false",
  )
  inspect(placement.length(), content="0")
  inspect(func.verify(), content="()")
}
