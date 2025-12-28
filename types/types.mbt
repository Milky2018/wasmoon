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
  FuncRef // nullable function reference (ref null func)
  ExternRef // nullable external reference (ref null extern)
  RefFunc // non-null function reference (ref func)
  RefExtern // non-null external reference (ref extern)
  // Typed function references
  RefFuncTyped(Int) // non-null typed function reference (ref $t)
  RefNullFuncTyped(Int) // nullable typed function reference (ref null $t)
  // GC reference types
  AnyRef // nullable any reference (ref null any)
  ExnRef // nullable exception reference (ref null exn)
  // GC struct/array references
  RefStruct(Int) // non-null typed struct reference (ref $t)
  RefNullStruct(Int) // nullable typed struct reference (ref null $t)
  RefArray(Int) // non-null typed array reference (ref $t)
  RefNullArray(Int) // nullable typed array reference (ref null $t)
  // GC abstract heap types
  RefAny // non-null any reference (ref any)
  RefEq // non-null eq reference (ref eq) - comparable
  RefNullEq // nullable eq reference (ref null eq)
  RefI31 // non-null i31 reference (ref i31)
  RefNullI31 // nullable i31 reference (ref null i31)
  RefNone // non-null none (ref none) - bottom type
  // Bottom reference types
  NullRef // bottom type (ref null none) - subtype of all nullable refs
  NullFuncRef // bottom type for func (ref null nofunc)
  NullExnRef // bottom type for exn (ref null noexn)
  NullExternRef // bottom type for extern (ref null noextern)
} derive(Eq, Show)

///|
/// Check if a reference type is nullable
pub fn ValueType::is_nullable(self : ValueType) -> Bool {
  match self {
    // Nullable reference types
    FuncRef | ExternRef | AnyRef | ExnRef => true
    RefNullFuncTyped(_) | RefNullStruct(_) | RefNullArray(_) => true
    RefNullEq | RefNullI31 => true
    NullRef | NullFuncRef | NullExnRef | NullExternRef => true
    // Non-nullable reference types
    RefFunc | RefExtern | RefAny | RefEq | RefI31 | RefNone => false
    RefFuncTyped(_) | RefStruct(_) | RefArray(_) => false
    // Value types (not references)
    I32 | I64 | F32 | F64 | V128 => false
  }
}

// ============================================================
// GC Types (WebAssembly GC Proposal)
// ============================================================

///|
/// Packed storage types for struct/array fields
pub(all) enum PackedType {
  I8
  I16
} derive(Eq, Show)

///|
/// Storage type for struct/array fields
pub(all) enum StorageType {
  Val(ValueType) // unpacked value type
  Packed(PackedType) // packed i8 or i16
} derive(Eq, Show)

///|
/// Field type with mutability
pub(all) struct FieldType {
  storage_type : StorageType
  mutable : Bool
} derive(Eq, Show)

///|
/// Struct type definition
pub(all) struct StructType {
  fields : Array[FieldType]
} derive(Eq, Show)

///|
/// Array type definition
pub(all) struct ArrayType {
  element : FieldType
} derive(Eq, Show)

///|
/// Composite type (func, struct, or array)
pub(all) enum CompositeType {
  Func(FuncType)
  Struct(StructType)
  Array(ArrayType)
} derive(Eq, Show)

///|
/// Subtype definition with optional supertype
pub(all) struct SubType {
  final_ : Bool // true if type cannot be subtyped further
  supertypes : Array[Int] // indices of supertypes (0 or 1 for MVP)
  composite : CompositeType
} derive(Eq, Show)

///|
/// Create a simple subtype without inheritance
pub fn SubType::simple(composite : CompositeType) -> SubType {
  { final_: true, supertypes: [], composite }
}

///|
/// Create a subtype from a function type
pub fn SubType::from_func(func_type : FuncType) -> SubType {
  SubType::simple(CompositeType::Func(func_type))
}

///|
/// Create a subtype from params and results (convenience function)
pub fn SubType::func(
  params : Array[ValueType],
  results : Array[ValueType],
) -> SubType {
  SubType::from_func({ params, results })
}

///|
/// Convert an array of FuncType to an array of SubType
pub fn func_types_to_subtypes(func_types : Array[FuncType]) -> Array[SubType] {
  let result : Array[SubType] = []
  for ft in func_types {
    result.push(SubType::from_func(ft))
  }
  result
}

///|
/// Extract FuncTypes from an array of SubType (for backwards compatibility)
/// Non-function types are replaced with empty function types
pub fn extract_func_types(subtypes : Array[SubType]) -> Array[FuncType] {
  let result : Array[FuncType] = []
  for subtype in subtypes {
    match subtype.composite {
      Func(ft) => result.push(ft)
      _ => result.push({ params: [], results: [] }) // placeholder
    }
  }
  result
}

///|
/// Runtime values
pub(all) enum Value {
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
  FuncRef(Int) // function index
  ExternRef(Int) // external reference
  ExnRef(Int) // exception reference (index into exception store)
  // GC values
  StructRef(Int) // struct reference (index into GC heap)
  ArrayRef(Int) // array reference (index into GC heap)
  I31(Int) // i31ref value (31-bit integer, stored directly)
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
  CallRef(Int) // type index (WasmGC)
  ReturnCall(Int) // function index (tail call)
  ReturnCallIndirect(Int, Int) // type index, table index (tail call)
  ReturnCallRef(Int) // type index (tail call, WasmGC)

  // Exception handling instructions
  Throw(Int) // tag index - throw exception with tag
  ThrowRef // throw exception from exnref on stack
  TryTable(BlockType, Array[CatchHandler], Array[Instruction]) // block type, handlers, body

  // Parametric instructions
  Drop
  Select
  SelectTyped(Array[ValueType]) // select with explicit result type

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
  TableInit(Int, Int) // table index, elem index

  // Memory instructions - (memidx, align, offset)
  // offset is Int64 to support memory64 64-bit offsets
  I32Load(Int, Int, Int64) // memidx, align, offset
  I64Load(Int, Int, Int64)
  F32Load(Int, Int, Int64)
  F64Load(Int, Int, Int64)
  I32Load8S(Int, Int, Int64)
  I32Load8U(Int, Int, Int64)
  I32Load16S(Int, Int, Int64)
  I32Load16U(Int, Int, Int64)
  I64Load8S(Int, Int, Int64)
  I64Load8U(Int, Int, Int64)
  I64Load16S(Int, Int, Int64)
  I64Load16U(Int, Int, Int64)
  I64Load32S(Int, Int, Int64)
  I64Load32U(Int, Int, Int64)
  I32Store(Int, Int, Int64)
  I64Store(Int, Int, Int64)
  F32Store(Int, Int, Int64)
  F64Store(Int, Int, Int64)
  I32Store8(Int, Int, Int64)
  I32Store16(Int, Int, Int64)
  I64Store8(Int, Int, Int64)
  I64Store16(Int, Int, Int64)
  I64Store32(Int, Int, Int64)
  MemorySize(Int) // memidx
  MemoryGrow(Int) // memidx
  MemoryInit(Int, Int) // memidx, data segment index
  DataDrop(Int) // data segment index
  MemoryCopy(Int, Int) // dest memidx, src memidx
  MemoryFill(Int) // memidx
  ElemDrop(Int) // element segment index

  // Reference type instructions
  RefNull(ValueType) // ref.null: push null reference of given type
  RefIsNull // ref.is_null: test if reference is null
  RefFunc(Int) // ref.func: push reference to function by index
  RefAsNonNull // ref.as_non_null: convert nullable ref to non-null ref
  RefEqInstr // ref.eq: compare two references for equality
  BrOnNull(Int) // br_on_null: branch if reference is null
  BrOnNonNull(Int) // br_on_non_null: branch if reference is non-null

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

  // GC instructions - struct operations
  StructNew(Int) // type index
  StructNewDefault(Int) // type index
  StructGet(Int, Int) // type index, field index
  StructGetS(Int, Int) // type index, field index (signed packed)
  StructGetU(Int, Int) // type index, field index (unsigned packed)
  StructSet(Int, Int) // type index, field index

  // GC instructions - array operations
  ArrayNew(Int) // type index
  ArrayNewDefault(Int) // type index
  ArrayNewFixed(Int, Int) // type index, length
  ArrayNewData(Int, Int) // type index, data index
  ArrayNewElem(Int, Int) // type index, elem index
  ArrayGet(Int) // type index
  ArrayGetS(Int) // type index (signed packed)
  ArrayGetU(Int) // type index (unsigned packed)
  ArraySet(Int) // type index
  ArrayLen // get array length
  ArrayFill(Int) // type index
  ArrayCopy(Int, Int) // dest type index, src type index
  ArrayInitData(Int, Int) // type index, data index
  ArrayInitElem(Int, Int) // type index, elem index

  // GC instructions - reference casting
  RefTest(ValueType) // test if ref matches type
  RefTestNull(ValueType) // test if ref matches nullable type
  RefCast(ValueType) // cast ref to type (trap if fails)
  RefCastNull(ValueType) // cast ref to nullable type (trap if fails)
  BrOnCast(Int, ValueType, ValueType) // label, from type, to type
  BrOnCastFail(Int, ValueType, ValueType) // label, from type, to type

  // GC instructions - i31
  RefI31 // create i31ref from i32
  I31GetS // get signed i32 from i31ref
  I31GetU // get unsigned i32 from i31ref

  // GC instructions - type conversion
  AnyConvertExtern // convert externref to anyref
  ExternConvertAny // convert anyref to externref
} derive(Eq, Show)

///|
/// Block type
pub(all) enum BlockType {
  Empty
  Value(ValueType)
  MultiValue(Array[ValueType]) // Multi-value results only (e.g., result i32 i64)
  InlineType(Array[ValueType], Array[ValueType]) // (params, results) for blocks with params
  TypeIndex(Int)
} derive(Eq, Show)

///|
/// Catch handler for try_table instruction
pub(all) enum CatchHandler {
  Catch(Int, Int) // (tag_idx, label_idx) - catch specific tag
  CatchRef(Int, Int) // (tag_idx, label_idx) - catch specific tag with exnref
  CatchAll(Int) // (label_idx) - catch any exception
  CatchAllRef(Int) // (label_idx) - catch any exception with exnref
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
/// Compute a hash for structural type equivalence.
/// Two FuncTypes with the same params and results will have the same hash.
pub fn FuncType::structural_hash(self : FuncType) -> Int {
  let mut h = 0
  // Encode params
  for param in self.params {
    h = h * 31 + param.type_code()
  }
  // Separator between params and results
  h = h * 31 + 0xFF
  // Encode results
  for result in self.results {
    h = h * 31 + result.type_code()
  }
  // Ensure non-negative
  if h < 0 {
    -h
  } else {
    h
  }
}

///|
/// Get a numeric code for a value type (for hashing)
fn ValueType::type_code(self : ValueType) -> Int {
  match self {
    I32 => 0
    I64 => 1
    F32 => 2
    F64 => 3
    V128 => 4
    FuncRef => 5
    ExternRef => 6
    RefFunc => 7
    RefExtern => 8
    RefFuncTyped(idx) => 100 + idx
    RefNullFuncTyped(idx) => 200 + idx
    AnyRef => 9
    ExnRef => 10
    NullRef => 11
    NullFuncRef => 12
    NullExnRef => 13
    NullExternRef => 14
    // GC types
    RefStruct(idx) => 300 + idx
    RefNullStruct(idx) => 400 + idx
    RefArray(idx) => 500 + idx
    RefNullArray(idx) => 600 + idx
    RefAny => 15
    RefEq => 16
    RefNullEq => 17
    RefI31 => 18
    RefNullI31 => 19
    RefNone => 20
  }
}

///|
/// Check if two FuncTypes are structurally equivalent.
/// This handles recursive types by comparing the structure rather than indices.
/// type1_idx and type2_idx are the indices of the types being compared.
pub fn FuncType::structurally_equal(
  self : FuncType,
  other : FuncType,
  self_idx : Int,
  other_idx : Int,
) -> Bool {
  // Check param count
  if self.params.length() != other.params.length() {
    return false
  }
  // Check result count
  if self.results.length() != other.results.length() {
    return false
  }
  // Check each param
  for i, p1 in self.params {
    let p2 = other.params[i]
    if not(p1.structurally_equal(p2, self_idx, other_idx)) {
      return false
    }
  }
  // Check each result
  for i, r1 in self.results {
    let r2 = other.results[i]
    if not(r1.structurally_equal(r2, self_idx, other_idx)) {
      return false
    }
  }
  true
}

///|
/// Check if two ValueTypes are structurally equivalent.
/// self_idx and other_idx are the indices of the containing types being compared.
fn ValueType::structurally_equal(
  self : ValueType,
  other : ValueType,
  self_idx : Int,
  other_idx : Int,
) -> Bool {
  match (self, other) {
    // Basic types must match exactly
    (I32, I32)
    | (I64, I64)
    | (F32, F32)
    | (F64, F64)
    | (V128, V128)
    | (FuncRef, FuncRef)
    | (ExternRef, ExternRef)
    | (RefFunc, RefFunc)
    | (RefExtern, RefExtern)
    | (AnyRef, AnyRef)
    | (ExnRef, ExnRef)
    | (NullRef, NullRef)
    | (NullFuncRef, NullFuncRef)
    | (NullExnRef, NullExnRef)
    | (NullExternRef, NullExternRef)
    | (RefAny, RefAny)
    | (RefEq, RefEq)
    | (RefNullEq, RefNullEq)
    | (RefI31, RefI31)
    | (RefNullI31, RefNullI31)
    | (RefNone, RefNone) => true
    // Typed function references: check if both are self-references or same external ref
    (RefFuncTyped(idx1), RefFuncTyped(idx2)) =>
      // Both self-references, or both reference the same external type
      (idx1 == self_idx && idx2 == other_idx) ||
      (idx1 != self_idx && idx2 != other_idx && idx1 == idx2)
    (RefNullFuncTyped(idx1), RefNullFuncTyped(idx2)) =>
      // Both self-references, or both reference the same external type
      (idx1 == self_idx && idx2 == other_idx) ||
      (idx1 != self_idx && idx2 != other_idx && idx1 == idx2)
    // Typed struct references
    (RefStruct(idx1), RefStruct(idx2)) =>
      (idx1 == self_idx && idx2 == other_idx) ||
      (idx1 != self_idx && idx2 != other_idx && idx1 == idx2)
    (RefNullStruct(idx1), RefNullStruct(idx2)) =>
      (idx1 == self_idx && idx2 == other_idx) ||
      (idx1 != self_idx && idx2 != other_idx && idx1 == idx2)
    // Typed array references
    (RefArray(idx1), RefArray(idx2)) =>
      (idx1 == self_idx && idx2 == other_idx) ||
      (idx1 != self_idx && idx2 != other_idx && idx1 == idx2)
    (RefNullArray(idx1), RefNullArray(idx2)) =>
      (idx1 == self_idx && idx2 == other_idx) ||
      (idx1 != self_idx && idx2 != other_idx && idx1 == idx2)
    _ => false
  }
}

///|
/// Limits for memory and tables
/// Uses Int64 to support memory64 proposal (limits up to 2^48 pages)
pub(all) struct Limits {
  min : Int64
  max : Int64?
} derive(Eq, Show)

///|
/// Memory type
pub(all) struct MemoryType {
  limits : Limits
  is_memory64 : Bool // true for i64-indexed memory (memory64 proposal)
} derive(Eq, Show)

///|
/// Get the address type for this memory (I32 for 32-bit, I64 for 64-bit)
pub fn MemoryType::addr_type(self : MemoryType) -> ValueType {
  if self.is_memory64 {
    I64
  } else {
    I32
  }
}

///|
/// Table type
pub(all) struct TableType {
  elem_type : ValueType
  limits : Limits
  is_table64 : Bool // true for table64 (i64-indexed table)
} derive(Eq, Show)

///|
/// Table definition with optional init expression
pub(all) struct Table {
  type_ : TableType
  init : Array[Instruction]? // Optional init expression for all elements
} derive(Eq, Show)

///|
/// Global type
pub(all) struct GlobalType {
  value_type : ValueType
  mutable : Bool
} derive(Eq, Show)

///|
/// Tag type (for exception handling)
/// Tags define the signature of exceptions - they can only have parameters, not results
pub(all) struct TagType {
  type_idx : Int // Index into the types array (must be a function type with no results)
} derive(Eq, Show)

///|
/// Import descriptor
pub(all) enum ImportDesc {
  Func(Int) // type index
  Table(TableType)
  Memory(MemoryType)
  Global(GlobalType)
  Tag(Int) // type index for exception tag
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
  Tag(Int) // tag index
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
/// Element segment mode
pub(all) enum ElemMode {
  /// Active segment: copied to table at instantiation
  Active(Int, Array[Instruction]) // table_idx, offset_expr
  /// Passive segment: can be copied via table.init
  Passive
  /// Declarative segment: only for validation
  Declarative
} derive(Eq, Show)

///|
/// Element segment
pub(all) struct Element {
  mode : ElemMode
  type_ : ValueType // element type (funcref or externref)
  init : Array[Array[Instruction]] // init expressions (each evaluates to a ref)
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
  types : Array[SubType] // GC: now stores SubType instead of FuncType
  /// For each type, stores the rec group ID it belongs to.
  /// Types in the same rec group have the same ID.
  /// Used to validate that forward type references are only within rec groups.
  type_rec_groups : Array[Int]
  imports : Array[Import]
  funcs : Array[Int] // type indices for functions
  tables : Array[Table]
  memories : Array[MemoryType]
  globals : Array[Global]
  exports : Array[Export]
  mut start : Int? // start function index
  elems : Array[Element]
  codes : Array[FunctionCode]
  datas : Array[Data]
  tags : Array[TagType] // exception tags
} derive(Show)

///|
/// Get the function type at the given index.
/// Panics if the type is not a function type.
pub fn Module::get_func_type(self : Module, idx : Int) -> FuncType {
  match self.types[idx].composite {
    Func(ft) => ft
    _ => abort("Type at index \{idx} is not a function type")
  }
}

///|
/// Get the struct type at the given index.
/// Panics if the type is not a struct type.
pub fn Module::get_struct_type(self : Module, idx : Int) -> StructType {
  match self.types[idx].composite {
    Struct(st) => st
    _ => abort("Type at index \{idx} is not a struct type")
  }
}

///|
/// Get the array type at the given index.
/// Panics if the type is not an array type.
pub fn Module::get_array_type(self : Module, idx : Int) -> ArrayType {
  match self.types[idx].composite {
    Array(at) => at
    _ => abort("Type at index \{idx} is not an array type")
  }
}

///|
/// Check if the type at the given index is a function type.
pub fn Module::is_func_type(self : Module, idx : Int) -> Bool {
  match self.types[idx].composite {
    Func(_) => true
    _ => false
  }
}

///|
/// Check if the type at the given index is a struct type.
pub fn Module::is_struct_type(self : Module, idx : Int) -> Bool {
  match self.types[idx].composite {
    Struct(_) => true
    _ => false
  }
}

///|
/// Check if the type at the given index is an array type.
pub fn Module::is_array_type(self : Module, idx : Int) -> Bool {
  match self.types[idx].composite {
    Array(_) => true
    _ => false
  }
}

///|
/// Create an empty module
pub fn Module::new() -> Module {
  {
    types: [],
    type_rec_groups: [],
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
    tags: [],
  }
}

///|
test "parse empty module" {
  let mod = Module::new()
  inspect(mod.types.length(), content="0")
  inspect(mod.funcs.length(), content="0")
  inspect(mod.start, content="None")
}
