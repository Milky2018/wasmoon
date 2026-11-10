///|
priv struct ReachableFunctions {
  imports : Int32
  selected : Array[Bool]
  pending : Array[Int32]
}

///|
fn ReachableFunctions::mark(self : ReachableFunctions, index : Int32) -> Unit {
  let local_index = index - self.imports
  if local_index >= 0 &&
    local_index < self.selected.length() &&
    !self.selected[local_index] {
    self.selected[local_index] = true
    self.pending.push(local_index)
  }
}

///|
fn ReachableFunctions::visit(
  self : ReachableFunctions,
  instructions : ArrayView[@types.Instruction],
) -> Unit {
  for instruction in instructions {
    match instruction {
      Call(index) | ReturnCall(index) | RefFunc(index) => self.mark(index)
      Block(_, body) | Loop(_, body) | TryTable(_, _, body) => self.visit(body)
      If(_, then_body, else_body) => {
        self.visit(then_body)
        self.visit(else_body)
      }
      _ => ()
    }
  }
}

///|
/// Select entry roots, initialization roots, and their transitive callees.
fn build_compile_mask(
  mod_ : @types.Module,
  roots : ArrayView[Int32],
) -> Array[Bool]? {
  let reachable : ReachableFunctions = {
    imports: @types.count_func_imports(mod_.imports),
    selected: Array::make(mod_.codes.length(), false),
    pending: [],
  }
  for index in roots {
    reachable.mark(index)
  }
  if mod_.start is Some(index) {
    reachable.mark(index)
  }
  for global in mod_.globals {
    reachable.visit(global.init)
  }
  for table in mod_.tables {
    if table.init is Some(initializer) {
      reachable.visit(initializer)
    }
  }
  for element in mod_.elems {
    if element.mode is Active(_, offset) {
      reachable.visit(offset)
    }
    for initializer in element.init {
      reachable.visit(initializer)
    }
  }
  for cursor = 0; cursor < reachable.pending.length(); {
    reachable.visit(mod_.codes[reachable.pending[cursor]].body)
    continue cursor + 1
  }
  let count = reachable.pending.length()
  if count == 0 || count == reachable.selected.length() {
    None
  } else {
    Some(reachable.selected)
  }
}
