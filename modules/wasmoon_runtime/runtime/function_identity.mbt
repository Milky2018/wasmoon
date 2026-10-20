///|
/// One allocation lifetime, independent of a reused function address or code.
pub struct FunctionIdentity {
  priv active : Ref[Bool]
}

///|
priv struct StoredFunction {
  callable : FuncInst
  lifetime : FunctionIdentity
}

///|
pub fn FunctionIdentity::is_live(self : FunctionIdentity) -> Bool {
  self.active.val
}

///|
/// Low-level handle support: retain an allocation's identity without its closure.
pub fn Store::function_identity(
  self : Store,
  address : Int32,
) -> FunctionIdentity raise RuntimeError {
  self.ensure_open()
  guard self.funcs.get(address) is Some(function) else { raise InvalidHandle }
  function.lifetime
}

///|
impl Debug for StoredFunction with fn to_repr(self) {
  Repr(self.callable)
}
