///|
/// Match the pinned engine's GC-storage capability without rejecting unused
/// declarations or modules that independently use GC and stack switching.
/// This is an engine build restriction, not portable WebAssembly validation.
pub fn validate_continuation_gc_storage(
  module_ : @types.Module,
) -> Unit raise @runtime.RuntimeError {
  fn check(index : Int) -> Unit raise @runtime.RuntimeError {
    guard module_.types.get(index) is Some(subtype) else { return }
    let fields = match subtype.composite {
      Struct(struct_) => struct_.fields
      Array(array) => [array.element]
      Func(_) | Cont(_) => return
    }
    for field in fields {
      if field.storage_type is Val(ty) && ty.is_continuation_ref() {
        raise @runtime.UnsupportedGcContinuationStorage
      }
    }
  }
  fn visit(
    body : Array[@types.Instruction],
  ) -> Unit raise @runtime.RuntimeError {
    for instruction in body {
      match instruction {
        Block(_, body) | Loop(_, body) | TryTable(_, _, body) => visit(body)
        If(_, yes, no) => {
          visit(yes)
          visit(no)
        }
        StructNew(index)
        | StructNewDefault(index)
        | StructGet(index, _)
        | StructGetS(index, _)
        | StructGetU(index, _)
        | StructSet(index, _)
        | ArrayNew(index)
        | ArrayNewDefault(index)
        | ArrayNewFixed(index, _)
        | ArrayNewData(index, _)
        | ArrayNewElem(index, _)
        | ArrayGet(index)
        | ArrayGetS(index)
        | ArrayGetU(index)
        | ArraySet(index)
        | ArrayFill(index)
        | ArrayInitData(index, _)
        | ArrayInitElem(index, _) => check(index)
        ArrayCopy(destination, source) => {
          check(destination)
          check(source)
        }
        _ => ()
      }
    }
  }
  for code in module_.codes {
    visit(code.body)
  }
  for global in module_.globals {
    visit(global.init)
  }
  for table in module_.tables {
    if table.init is Some(init) {
      visit(init)
    }
  }
  for element in module_.elems {
    for init in element.init {
      visit(init)
    }
  }
}
