// Wasmoon - A WebAssembly Runtime in MoonBit
// Core data structures and type definitions

// ============================================================
// Value Types
// ============================================================

///|
/// WebAssembly value types
pub(all) enum ValueType {
  I32
  I64
  F32
  F64
  V128 // SIMD
  FuncRef
  ExternRef
} derive(Eq, Show)

///|
/// Runtime values
pub(all) enum Value {
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
  FuncRef(Int) // function index
  ExternRef(Int) // external reference
  Null
} derive(Eq, Show)

// ============================================================
// Instructions
// ============================================================

///|
/// WebAssembly instructions
pub(all) enum Instruction {
  // Control instructions
  Unreachable
  Nop
  Block(BlockType, Array[Instruction])
  Loop(BlockType, Array[Instruction])
  If(BlockType, Array[Instruction], Array[Instruction])
  Br(Int) // label index
  BrIf(Int)
  BrTable(Array[Int], Int) // labels, default
  Return
  Call(Int) // function index
  CallIndirect(Int, Int) // type index, table index

  // Parametric instructions
  Drop
  Select

  // Variable instructions
  LocalGet(Int)
  LocalSet(Int)
  LocalTee(Int)
  GlobalGet(Int)
  GlobalSet(Int)

  // Table instructions
  TableGet(Int) // table index
  TableSet(Int) // table index
  TableSize(Int) // table index
  TableGrow(Int) // table index
  TableFill(Int) // table index
  TableCopy(Int, Int) // dest table index, src table index

  // Memory instructions
  I32Load(Int, Int) // align, offset
  I64Load(Int, Int)
  F32Load(Int, Int)
  F64Load(Int, Int)
  I32Load8S(Int, Int)
  I32Load8U(Int, Int)
  I32Load16S(Int, Int)
  I32Load16U(Int, Int)
  I64Load8S(Int, Int)
  I64Load8U(Int, Int)
  I64Load16S(Int, Int)
  I64Load16U(Int, Int)
  I64Load32S(Int, Int)
  I64Load32U(Int, Int)
  I32Store(Int, Int)
  I64Store(Int, Int)
  F32Store(Int, Int)
  F64Store(Int, Int)
  I32Store8(Int, Int)
  I32Store16(Int, Int)
  I64Store8(Int, Int)
  I64Store16(Int, Int)
  I64Store32(Int, Int)
  MemorySize
  MemoryGrow
  MemoryInit(Int) // data segment index
  DataDrop(Int) // data segment index
  MemoryCopy
  MemoryFill
  ElemDrop(Int) // element segment index

  // Reference type instructions
  RefNull(ValueType) // ref.null: push null reference of given type
  RefIsNull // ref.is_null: test if reference is null
  RefFunc(Int) // ref.func: push reference to function by index

  // Numeric instructions - Constants
  I32Const(Int)
  I64Const(Int64)
  F32Const(Float)
  F64Const(Double)

  // Numeric instructions - i32
  I32Eqz
  I32Eq
  I32Ne
  I32LtS
  I32LtU
  I32GtS
  I32GtU
  I32LeS
  I32LeU
  I32GeS
  I32GeU
  I32Clz
  I32Ctz
  I32Popcnt
  I32Add
  I32Sub
  I32Mul
  I32DivS
  I32DivU
  I32RemS
  I32RemU
  I32And
  I32Or
  I32Xor
  I32Shl
  I32ShrS
  I32ShrU
  I32Rotl
  I32Rotr
  // Sign-extension operators
  I32Extend8S
  I32Extend16S

  // Numeric instructions - i64
  I64Eqz
  I64Eq
  I64Ne
  I64LtS
  I64LtU
  I64GtS
  I64GtU
  I64LeS
  I64LeU
  I64GeS
  I64GeU
  I64Clz
  I64Ctz
  I64Popcnt
  I64Add
  I64Sub
  I64Mul
  I64DivS
  I64DivU
  I64RemS
  I64RemU
  I64And
  I64Or
  I64Xor
  I64Shl
  I64ShrS
  I64ShrU
  I64Rotl
  I64Rotr
  // Sign-extension operators
  I64Extend8S
  I64Extend16S
  I64Extend32S

  // Numeric instructions - f32
  F32Eq
  F32Ne
  F32Lt
  F32Gt
  F32Le
  F32Ge
  F32Abs
  F32Neg
  F32Ceil
  F32Floor
  F32Trunc
  F32Nearest
  F32Sqrt
  F32Add
  F32Sub
  F32Mul
  F32Div
  F32Min
  F32Max
  F32Copysign

  // Numeric instructions - f64
  F64Eq
  F64Ne
  F64Lt
  F64Gt
  F64Le
  F64Ge
  F64Abs
  F64Neg
  F64Ceil
  F64Floor
  F64Trunc
  F64Nearest
  F64Sqrt
  F64Add
  F64Sub
  F64Mul
  F64Div
  F64Min
  F64Max
  F64Copysign

  // Conversion instructions
  I32WrapI64
  I32TruncF32S
  I32TruncF32U
  I32TruncF64S
  I32TruncF64U
  I64ExtendI32S
  I64ExtendI32U
  I64TruncF32S
  I64TruncF32U
  I64TruncF64S
  I64TruncF64U
  F32ConvertI32S
  F32ConvertI32U
  F32ConvertI64S
  F32ConvertI64U
  F32DemoteF64
  F64ConvertI32S
  F64ConvertI32U
  F64ConvertI64S
  F64ConvertI64U
  F64PromoteF32
  I32ReinterpretF32
  I64ReinterpretF64
  F32ReinterpretI32
  F64ReinterpretI64

  // Saturating truncation instructions (nontrapping float-to-int)
  I32TruncSatF32S
  I32TruncSatF32U
  I32TruncSatF64S
  I32TruncSatF64U
  I64TruncSatF32S
  I64TruncSatF32U
  I64TruncSatF64S
  I64TruncSatF64U
} derive(Eq, Show)

///|
/// Block type
pub(all) enum BlockType {
  Empty
  Value(ValueType)
  TypeIndex(Int)
} derive(Eq, Show)

// ============================================================
// Module Structures
// ============================================================

///|
/// Function type
pub(all) struct FuncType {
  params : Array[ValueType]
  results : Array[ValueType]
} derive(Eq, Show)

///|
/// Limits for memory and tables
pub(all) struct Limits {
  min : Int
  max : Int?
} derive(Eq, Show)

///|
/// Memory type
pub(all) struct MemoryType {
  limits : Limits
} derive(Eq, Show)

///|
/// Table type
pub(all) struct TableType {
  elem_type : ValueType
  limits : Limits
} derive(Eq, Show)

///|
/// Global type
pub(all) struct GlobalType {
  value_type : ValueType
  mutable : Bool
} derive(Eq, Show)

///|
/// Import descriptor
pub(all) enum ImportDesc {
  Func(Int) // type index
  Table(TableType)
  Memory(MemoryType)
  Global(GlobalType)
} derive(Eq, Show)

///|
/// Import entry
pub(all) struct Import {
  mod_name : String
  name : String
  desc : ImportDesc
} derive(Eq, Show)

///|
/// Export descriptor
pub(all) enum ExportDesc {
  Func(Int) // function index
  Table(Int) // table index
  Memory(Int) // memory index
  Global(Int) // global index
} derive(Eq, Show)

///|
/// Export entry
pub(all) struct Export {
  name : String
  desc : ExportDesc
} derive(Eq, Show)

///|
/// Function code
pub(all) struct FunctionCode {
  locals : Array[ValueType]
  body : Array[Instruction]
} derive(Eq, Show)

///|
/// Global definition
pub(all) struct Global {
  type_ : GlobalType
  init : Array[Instruction]
} derive(Eq, Show)

///|
/// Element segment
pub(all) struct Element {
  table_idx : Int
  offset : Array[Instruction]
  init : Array[Int] // function indices
} derive(Eq, Show)

///|
/// Data segment
pub(all) struct Data {
  memory_idx : Int
  offset : Array[Instruction]
  init : Bytes
} derive(Eq, Show)

///|
/// WebAssembly module
pub(all) struct Module {
  types : Array[FuncType]
  imports : Array[Import]
  funcs : Array[Int] // type indices for functions
  tables : Array[TableType]
  memories : Array[MemoryType]
  globals : Array[Global]
  exports : Array[Export]
  mut start : Int? // start function index
  elems : Array[Element]
  codes : Array[FunctionCode]
  datas : Array[Data]
} derive(Show)

///|
/// Create an empty module
pub fn Module::new() -> Module {
  {
    types: [],
    imports: [],
    funcs: [],
    tables: [],
    memories: [],
    globals: [],
    exports: [],
    start: None,
    elems: [],
    codes: [],
    datas: [],
  }
}

///|
test "parse empty module" {
  let _ = Module::new()
  inspect(true, content="true")
}
