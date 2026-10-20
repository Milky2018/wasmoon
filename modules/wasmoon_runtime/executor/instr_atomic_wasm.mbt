///|
fn ExecContext::exec_atomic(
  _self : ExecContext,
  _subopcode : Int32,
  _memidx : Int32,
  _align : Int32,
  _offset : Int64,
) -> Unit raise {
  raise @runtime.RuntimeError::UnsupportedHostCapability(
    "atomic memory operations",
  )
}
