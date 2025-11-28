///|
/// The store contains all global runtime state
pub struct Store {
  funcs : Array[@wasmoon.FunctionCode]
  tables : Array[Table]
  mems : Array[Memory]
  globals : Array[GlobalInstance]
} derive(Show)

///|
pub fn Store::new() -> Store {
  { funcs: [], tables: [], mems: [], globals: [] }
}

///|
pub fn Store::alloc_func(self : Store, func : @wasmoon.FunctionCode) -> Int {
  let idx = self.funcs.length()
  self.funcs.push(func)
  idx
}

///|
pub fn Store::alloc_table(self : Store, table : Table) -> Int {
  let idx = self.tables.length()
  self.tables.push(table)
  idx
}

///|
pub fn Store::alloc_mem(self : Store, mem : Memory) -> Int {
  let idx = self.mems.length()
  self.mems.push(mem)
  idx
}

///|
pub fn Store::alloc_global(self : Store, global : GlobalInstance) -> Int {
  let idx = self.globals.length()
  self.globals.push(global)
  idx
}

///|
pub fn Store::get_func(
  self : Store,
  idx : Int,
) -> @wasmoon.FunctionCode raise RuntimeError {
  if idx < 0 || idx >= self.funcs.length() {
    raise UndefinedElement
  }
  self.funcs[idx]
}

///|
pub fn Store::get_table(self : Store, idx : Int) -> Table raise RuntimeError {
  if idx < 0 || idx >= self.tables.length() {
    raise UndefinedElement
  }
  self.tables[idx]
}

///|
pub fn Store::get_mem(self : Store, idx : Int) -> Memory raise RuntimeError {
  if idx < 0 || idx >= self.mems.length() {
    raise UndefinedElement
  }
  self.mems[idx]
}

///|
pub fn Store::get_global(
  self : Store,
  idx : Int,
) -> GlobalInstance raise RuntimeError {
  if idx < 0 || idx >= self.globals.length() {
    raise UndefinedElement
  }
  self.globals[idx]
}
