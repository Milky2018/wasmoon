// Wasmoon Runtime - Runtime data structures
// Implements the execution environment for WebAssembly modules

// ============================================================
// Runtime Errors
// ============================================================

///|
suberror RuntimeError {
  StackUnderflow
  StackOverflow
  TypeMismatch
  OutOfBoundsMemoryAccess
  OutOfBoundsTableAccess
  UndefinedElement
  UninitializedElement
  IndirectCallTypeMismatch
  DivisionByZero
  IntegerOverflow
  InvalidConversion
  Unreachable
  CallStackExhausted
} derive(Show)

// ============================================================
// Stack
// ============================================================

///|
/// Value stack for operands
struct Stack {
  values : Array[Value]
  mut sp : Int // stack pointer
} derive(Show)

///|
fn Stack::new() -> Stack {
  { values: [], sp: 0 }
}

///|
fn Stack::push(self : Stack, value : Value) -> Unit raise RuntimeError {
  if self.sp >= 10000 { // arbitrary limit
    raise StackOverflow
  }
  if self.sp >= self.values.length() {
    self.values.push(value)
  } else {
    self.values[self.sp] = value
  }
  self.sp = self.sp + 1
}

///|
fn Stack::pop(self : Stack) -> Value raise RuntimeError {
  if self.sp <= 0 {
    raise StackUnderflow
  }
  self.sp = self.sp - 1
  self.values[self.sp]
}

///|
fn Stack::peek(self : Stack) -> Value raise RuntimeError {
  if self.sp <= 0 {
    raise StackUnderflow
  }
  self.values[self.sp - 1]
}

///|
fn Stack::pop_i32(self : Stack) -> Int raise RuntimeError {
  match self.pop() {
    I32(n) => n
    _ => raise TypeMismatch
  }
}

///|
fn Stack::pop_i64(self : Stack) -> Int64 raise RuntimeError {
  match self.pop() {
    I64(n) => n
    _ => raise TypeMismatch
  }
}

///|
fn Stack::pop_f32(self : Stack) -> Float raise RuntimeError {
  match self.pop() {
    F32(f) => f
    _ => raise TypeMismatch
  }
}

///|
fn Stack::pop_f64(self : Stack) -> Double raise RuntimeError {
  match self.pop() {
    F64(f) => f
    _ => raise TypeMismatch
  }
}

///|
fn Stack::size(self : Stack) -> Int {
  self.sp
}

///|
fn Stack::clear(self : Stack) -> Unit {
  self.sp = 0
}

// ============================================================
// Linear Memory
// ============================================================

///|
/// WebAssembly linear memory (64KB pages)
struct Memory {
  data : Array[Byte]
  mut size : Int // current size in pages
  max : Int? // max size in pages
} derive(Show)

///|
fn Memory::new(min : Int, max : Int?) -> Memory {
  let page_size = 65536 // 64KB
  let initial_size = min * page_size
  let data : Array[Byte] = []
  for i = 0; i < initial_size; i = i + 1 {
    data.push(b'\x00')
  }
  { data, size: min, max }
}

///|
fn Memory::load_byte(self : Memory, addr : Int) -> Byte raise RuntimeError {
  if addr < 0 || addr >= self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  self.data[addr]
}

///|
fn Memory::store_byte(
  self : Memory,
  addr : Int,
  value : Byte,
) -> Unit raise RuntimeError {
  if addr < 0 || addr >= self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  self.data[addr] = value
}

///|
fn Memory::load_i32(self : Memory, addr : Int) -> Int raise RuntimeError {
  if addr + 4 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  let b0 = self.data[addr].to_int()
  let b1 = self.data[addr + 1].to_int()
  let b2 = self.data[addr + 2].to_int()
  let b3 = self.data[addr + 3].to_int()
  // Little-endian
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn Memory::store_i32(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  if addr + 4 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  self.store_byte(addr, value.land(0xFF).to_byte())
  self.store_byte(addr + 1, (value >> 8).land(0xFF).to_byte())
  self.store_byte(addr + 2, (value >> 16).land(0xFF).to_byte())
  self.store_byte(addr + 3, (value >> 24).land(0xFF).to_byte())
}

///|
fn Memory::load_i64(self : Memory, addr : Int) -> Int64 raise RuntimeError {
  if addr + 8 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  let b0 = self.data[addr].to_int64()
  let b1 = self.data[addr + 1].to_int64()
  let b2 = self.data[addr + 2].to_int64()
  let b3 = self.data[addr + 3].to_int64()
  let b4 = self.data[addr + 4].to_int64()
  let b5 = self.data[addr + 5].to_int64()
  let b6 = self.data[addr + 6].to_int64()
  let b7 = self.data[addr + 7].to_int64()
  // Little-endian
  b0 |
  (b1 << 8) |
  (b2 << 16) |
  (b3 << 24) |
  (b4 << 32) |
  (b5 << 40) |
  (b6 << 48) |
  (b7 << 56)
}

///|
fn Memory::store_i64(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  if addr + 8 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  for i = 0; i < 8; i = i + 1 {
    let byte_val = (value >> (i * 8)).land(0xFFL).to_int()
    self.store_byte(addr + i, byte_val.to_byte())
  }
}

///|
fn Memory::size_pages(self : Memory) -> Int {
  self.size
}

///|
fn Memory::grow(self : Memory, delta : Int) -> Int {
  let old_size = self.size
  let new_size = old_size + delta

  // Check max limit
  match self.max {
    Some(max) => if new_size > max { return -1 }
    None => ()
  }

  // Check absolute limit (65536 pages = 4GB)
  if new_size > 65536 {
    return -1
  }

  // Grow the memory
  let page_size = 65536
  let new_data_size = delta * page_size
  for i = 0; i < new_data_size; i = i + 1 {
    self.data.push(b'\x00')
  }
  self.size = new_size
  old_size
}

// ============================================================
// Table
// ============================================================

///|
/// WebAssembly table for function references
struct Table {
  elem_type : ValueType
  elements : Array[Value]
  mut size : Int
  max : Int?
} derive(Show)

///|
fn Table::new(elem_type : ValueType, min : Int, max : Int?) -> Table {
  let elements : Array[Value] = []
  for i = 0; i < min; i = i + 1 {
    elements.push(Null)
  }
  { elem_type, elements, size: min, max }
}

///|
fn Table::get(self : Table, idx : Int) -> Value raise RuntimeError {
  if idx < 0 || idx >= self.size {
    raise OutOfBoundsTableAccess
  }
  let elem = self.elements[idx]
  match elem {
    Null => raise UninitializedElement
    _ => elem
  }
}

///|
fn Table::set(
  self : Table,
  idx : Int,
  value : Value,
) -> Unit raise RuntimeError {
  if idx < 0 || idx >= self.size {
    raise OutOfBoundsTableAccess
  }
  self.elements[idx] = value
}

///|
fn Table::size_entries(self : Table) -> Int {
  self.size
}

///|
fn Table::grow(self : Table, delta : Int, init : Value) -> Int {
  let old_size = self.size
  let new_size = old_size + delta

  // Check max limit
  match self.max {
    Some(max) => if new_size > max { return -1 }
    None => ()
  }

  // Grow the table
  for i = 0; i < delta; i = i + 1 {
    self.elements.push(init)
  }
  self.size = new_size
  old_size
}

// ============================================================
// Global Variables
// ============================================================

///|
/// Runtime representation of a global variable
struct GlobalInstance {
  type_ : GlobalType
  mut value : Value
} derive(Show)

///|
fn GlobalInstance::new(type_ : GlobalType, value : Value) -> GlobalInstance {
  { type_, value }
}

///|
fn GlobalInstance::get(self : GlobalInstance) -> Value {
  self.value
}

///|
fn GlobalInstance::set(
  self : GlobalInstance,
  value : Value,
) -> Unit raise RuntimeError {
  if !self.type_.mutable {
    raise RuntimeError::TypeMismatch // attempting to mutate immutable global
  }
  self.value = value
}

// ============================================================
// Call Frames and Labels
// ============================================================

///|
/// Label for structured control flow (blocks, loops, if)
struct Label {
  arity : Int // number of values to keep when branching
  continuation : Int // instruction pointer to jump to
} derive(Show)

///|
/// Call frame for function execution
struct Frame {
  func_idx : Int
  locals : Array[Value]
  ip : Int // instruction pointer
  return_arity : Int // number of return values
} derive(Show)

///|
fn Frame::new(
  func_idx : Int,
  locals : Array[Value],
  return_arity : Int,
) -> Frame {
  { func_idx, locals, ip: 0, return_arity }
}

///|
fn Frame::get_local(self : Frame, idx : Int) -> Value raise RuntimeError {
  if idx < 0 || idx >= self.locals.length() {
    raise RuntimeError::TypeMismatch
  }
  self.locals[idx]
}

///|
fn Frame::set_local(
  self : Frame,
  idx : Int,
  value : Value,
) -> Unit raise RuntimeError {
  if idx < 0 || idx >= self.locals.length() {
    raise RuntimeError::TypeMismatch
  }
  self.locals[idx] = value
}

// ============================================================
// Module Instance
// ============================================================

///|
/// Runtime instance of a WebAssembly module
pub struct ModuleInstance {
  types : Array[FuncType]
  func_addrs : Array[Int] // indices into function store
  table_addrs : Array[Int] // indices into table store
  mem_addrs : Array[Int] // indices into memory store
  global_addrs : Array[Int] // indices into global store
  exports : Array[Export]
  elem_segments : Array[Element]
  data_segments : Array[Data]
} derive(Show)

///|
pub fn ModuleInstance::new() -> ModuleInstance {
  {
    types: [],
    func_addrs: [],
    table_addrs: [],
    mem_addrs: [],
    global_addrs: [],
    exports: [],
    elem_segments: [],
    data_segments: [],
  }
}

// ============================================================
// Store (Global runtime state)
// ============================================================

///|
/// The store contains all global runtime state
pub struct Store {
  funcs : Array[FunctionCode]
  tables : Array[Table]
  mems : Array[Memory]
  globals : Array[GlobalInstance]
} derive(Show)

///|
pub fn Store::new() -> Store {
  { funcs: [], tables: [], mems: [], globals: [] }
}

///|
fn Store::alloc_func(self : Store, func : FunctionCode) -> Int {
  let idx = self.funcs.length()
  self.funcs.push(func)
  idx
}

///|
fn Store::alloc_table(self : Store, table : Table) -> Int {
  let idx = self.tables.length()
  self.tables.push(table)
  idx
}

///|
fn Store::alloc_mem(self : Store, mem : Memory) -> Int {
  let idx = self.mems.length()
  self.mems.push(mem)
  idx
}

///|
fn Store::alloc_global(self : Store, global : GlobalInstance) -> Int {
  let idx = self.globals.length()
  self.globals.push(global)
  idx
}

///|
fn Store::get_func(self : Store, idx : Int) -> FunctionCode raise RuntimeError {
  if idx < 0 || idx >= self.funcs.length() {
    raise UndefinedElement
  }
  self.funcs[idx]
}

///|
fn Store::get_table(self : Store, idx : Int) -> Table raise RuntimeError {
  if idx < 0 || idx >= self.tables.length() {
    raise UndefinedElement
  }
  self.tables[idx]
}

///|
fn Store::get_mem(self : Store, idx : Int) -> Memory raise RuntimeError {
  if idx < 0 || idx >= self.mems.length() {
    raise UndefinedElement
  }
  self.mems[idx]
}

///|
fn Store::get_global(
  self : Store,
  idx : Int,
) -> GlobalInstance raise RuntimeError {
  if idx < 0 || idx >= self.globals.length() {
    raise UndefinedElement
  }
  self.globals[idx]
}
