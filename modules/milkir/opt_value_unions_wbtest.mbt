///|
test "scoped optimizer unions are typed and roll back at dominance boundaries" {
  let func = Function::new_empty("scoped_value_unions")
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
