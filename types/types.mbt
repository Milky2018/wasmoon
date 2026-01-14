// Wasmoon - A WebAssembly Runtime in MoonBit
// Core data structures and type definitions

// ============================================================
// Reference Encoding Constants
// ============================================================
// These constants define how references are encoded in JIT mode.
// They must match the encoding in jit/jit_ffi/jit.c

///|
/// Null reference value in JIT/reference encodings.
///
/// This is also used by GC encodings to avoid collisions with non-null refs.
pub const NULL_REF : Int64 = 0L

///|
/// Legacy constant kept for compatibility.
///
/// Do not use this as a "null reference" value.
/// JIT/reference encodings use `NULL_REF` (=0) for null, and `-1` is commonly
/// used by the JIT ABI to encode funcref index 0 as `-(idx+1)`.
pub const FUNCREF_NULL_SENTINEL : Int64 = -1L

///|
/// Tag for externref values: bit 62 set
pub const EXTERNREF_TAG : Int64 = 0x4000000000000000L

///|
/// Tag for funcref pointer values: bit 61 set
pub const FUNCREF_TAG : Int64 = 0x2000000000000000L

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
  StructRef // nullable struct reference (ref null struct)
  ArrayRef // nullable array reference (ref null array)
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
  RefStructAbs // non-null struct reference (ref struct)
  RefArrayAbs // non-null array reference (ref array)
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
    FuncRef | ExternRef | AnyRef | ExnRef | StructRef | ArrayRef => true
    RefNullFuncTyped(_) | RefNullStruct(_) | RefNullArray(_) => true
    RefNullEq | RefNullI31 => true
    NullRef | NullFuncRef | NullExnRef | NullExternRef => true
    // Non-nullable reference types
    RefFunc
    | RefExtern
    | RefAny
    | RefEq
    | RefI31
    | RefStructAbs
    | RefArrayAbs
    | RefNone => false
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
  V128(Bytes) // SIMD 128-bit vector (16 bytes)
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

  // Atomic instructions (0xFE prefix)
  // subopcode: wasm threads/atomics subopcode
  // memarg: (memidx, align, offset)
  Atomic(Int, Int, Int, Int64)

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
  I64MulWideS
  I64MulWideU
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

  // ============================================================
  // SIMD Instructions (128-bit packed SIMD)
  // ============================================================

  // SIMD constants
  V128Const(Bytes) // 16-byte constant

  // SIMD load/store - (memidx, align, offset)
  V128Load(Int, Int, Int64)
  V128Load8x8S(Int, Int, Int64)
  V128Load8x8U(Int, Int, Int64)
  V128Load16x4S(Int, Int, Int64)
  V128Load16x4U(Int, Int, Int64)
  V128Load32x2S(Int, Int, Int64)
  V128Load32x2U(Int, Int, Int64)
  V128Load8Splat(Int, Int, Int64)
  V128Load16Splat(Int, Int, Int64)
  V128Load32Splat(Int, Int, Int64)
  V128Load64Splat(Int, Int, Int64)
  V128Load32Zero(Int, Int, Int64)
  V128Load64Zero(Int, Int, Int64)
  V128Store(Int, Int, Int64)

  // SIMD load/store lane - (memidx, align, offset, lane)
  V128Load8Lane(Int, Int, Int64, Int)
  V128Load16Lane(Int, Int, Int64, Int)
  V128Load32Lane(Int, Int, Int64, Int)
  V128Load64Lane(Int, Int, Int64, Int)
  V128Store8Lane(Int, Int, Int64, Int)
  V128Store16Lane(Int, Int, Int64, Int)
  V128Store32Lane(Int, Int, Int64, Int)
  V128Store64Lane(Int, Int, Int64, Int)

  // SIMD shuffle/swizzle
  I8x16Shuffle(FixedArray[Int]) // 16 lane indices
  I8x16Swizzle

  // SIMD splat (scalar -> vector)
  I8x16Splat
  I16x8Splat
  I32x4Splat
  I64x2Splat
  F32x4Splat
  F64x2Splat

  // SIMD extract lane (vector -> scalar)
  I8x16ExtractLaneS(Int)
  I8x16ExtractLaneU(Int)
  I16x8ExtractLaneS(Int)
  I16x8ExtractLaneU(Int)
  I32x4ExtractLane(Int)
  I64x2ExtractLane(Int)
  F32x4ExtractLane(Int)
  F64x2ExtractLane(Int)

  // SIMD replace lane (vector, scalar -> vector)
  I8x16ReplaceLane(Int)
  I16x8ReplaceLane(Int)
  I32x4ReplaceLane(Int)
  I64x2ReplaceLane(Int)
  F32x4ReplaceLane(Int)
  F64x2ReplaceLane(Int)

  // i8x16 comparisons
  I8x16Eq
  I8x16Ne
  I8x16LtS
  I8x16LtU
  I8x16GtS
  I8x16GtU
  I8x16LeS
  I8x16LeU
  I8x16GeS
  I8x16GeU

  // i16x8 comparisons
  I16x8Eq
  I16x8Ne
  I16x8LtS
  I16x8LtU
  I16x8GtS
  I16x8GtU
  I16x8LeS
  I16x8LeU
  I16x8GeS
  I16x8GeU

  // i32x4 comparisons
  I32x4Eq
  I32x4Ne
  I32x4LtS
  I32x4LtU
  I32x4GtS
  I32x4GtU
  I32x4LeS
  I32x4LeU
  I32x4GeS
  I32x4GeU

  // i64x2 comparisons
  I64x2Eq
  I64x2Ne
  I64x2LtS
  I64x2GtS
  I64x2LeS
  I64x2GeS

  // f32x4 comparisons
  F32x4Eq
  F32x4Ne
  F32x4Lt
  F32x4Gt
  F32x4Le
  F32x4Ge

  // f64x2 comparisons
  F64x2Eq
  F64x2Ne
  F64x2Lt
  F64x2Gt
  F64x2Le
  F64x2Ge

  // v128 bitwise operations
  V128Not
  V128And
  V128AndNot
  V128Or
  V128Xor
  V128Bitselect
  V128AnyTrue

  // i8x16 operations
  I8x16Abs
  I8x16Neg
  I8x16Popcnt
  I8x16AllTrue
  I8x16Bitmask
  I8x16NarrowI16x8S
  I8x16NarrowI16x8U
  I8x16Shl
  I8x16ShrS
  I8x16ShrU
  I8x16Add
  I8x16AddSatS
  I8x16AddSatU
  I8x16Sub
  I8x16SubSatS
  I8x16SubSatU
  I8x16MinS
  I8x16MinU
  I8x16MaxS
  I8x16MaxU
  I8x16AvgrU

  // i16x8 operations
  I16x8ExtAddPairwiseI8x16S
  I16x8ExtAddPairwiseI8x16U
  I16x8Abs
  I16x8Neg
  I16x8Q15MulrSatS
  I16x8AllTrue
  I16x8Bitmask
  I16x8NarrowI32x4S
  I16x8NarrowI32x4U
  I16x8ExtendLowI8x16S
  I16x8ExtendHighI8x16S
  I16x8ExtendLowI8x16U
  I16x8ExtendHighI8x16U
  I16x8Shl
  I16x8ShrS
  I16x8ShrU
  I16x8Add
  I16x8AddSatS
  I16x8AddSatU
  I16x8Sub
  I16x8SubSatS
  I16x8SubSatU
  I16x8Mul
  I16x8MinS
  I16x8MinU
  I16x8MaxS
  I16x8MaxU
  I16x8AvgrU
  I16x8ExtMulLowI8x16S
  I16x8ExtMulHighI8x16S
  I16x8ExtMulLowI8x16U
  I16x8ExtMulHighI8x16U

  // i32x4 operations
  I32x4ExtAddPairwiseI16x8S
  I32x4ExtAddPairwiseI16x8U
  I32x4Abs
  I32x4Neg
  I32x4AllTrue
  I32x4Bitmask
  I32x4ExtendLowI16x8S
  I32x4ExtendHighI16x8S
  I32x4ExtendLowI16x8U
  I32x4ExtendHighI16x8U
  I32x4Shl
  I32x4ShrS
  I32x4ShrU
  I32x4Add
  I32x4Sub
  I32x4Mul
  I32x4MinS
  I32x4MinU
  I32x4MaxS
  I32x4MaxU
  I32x4DotI16x8S
  I32x4ExtMulLowI16x8S
  I32x4ExtMulHighI16x8S
  I32x4ExtMulLowI16x8U
  I32x4ExtMulHighI16x8U

  // i64x2 operations
  I64x2Abs
  I64x2Neg
  I64x2AllTrue
  I64x2Bitmask
  I64x2ExtendLowI32x4S
  I64x2ExtendHighI32x4S
  I64x2ExtendLowI32x4U
  I64x2ExtendHighI32x4U
  I64x2Shl
  I64x2ShrS
  I64x2ShrU
  I64x2Add
  I64x2Sub
  I64x2Mul
  I64x2ExtMulLowI32x4S
  I64x2ExtMulHighI32x4S
  I64x2ExtMulLowI32x4U
  I64x2ExtMulHighI32x4U

  // f32x4 operations
  F32x4Ceil
  F32x4Floor
  F32x4Trunc
  F32x4Nearest
  F32x4Abs
  F32x4Neg
  F32x4Sqrt
  F32x4Add
  F32x4Sub
  F32x4Mul
  F32x4Div
  F32x4Min
  F32x4Max
  F32x4Pmin
  F32x4Pmax

  // f64x2 operations
  F64x2Ceil
  F64x2Floor
  F64x2Trunc
  F64x2Nearest
  F64x2Abs
  F64x2Neg
  F64x2Sqrt
  F64x2Add
  F64x2Sub
  F64x2Mul
  F64x2Div
  F64x2Min
  F64x2Max
  F64x2Pmin
  F64x2Pmax

  // SIMD conversions
  I32x4TruncSatF32x4S
  I32x4TruncSatF32x4U
  F32x4ConvertI32x4S
  F32x4ConvertI32x4U
  I32x4TruncSatF64x2SZero
  I32x4TruncSatF64x2UZero
  F64x2ConvertLowI32x4S
  F64x2ConvertLowI32x4U
  F32x4DemoteF64x2Zero
  F64x2PromoteLowF32x4

  // Relaxed SIMD instructions
  I8x16RelaxedSwizzle
  I32x4RelaxedTruncF32x4S
  I32x4RelaxedTruncF32x4U
  I32x4RelaxedTruncF64x2SZero
  I32x4RelaxedTruncF64x2UZero
  F32x4RelaxedMadd
  F32x4RelaxedNmadd
  F64x2RelaxedMadd
  F64x2RelaxedNmadd
  I8x16RelaxedLaneselect
  I16x8RelaxedLaneselect
  I32x4RelaxedLaneselect
  I64x2RelaxedLaneselect
  F32x4RelaxedMin
  F32x4RelaxedMax
  F64x2RelaxedMin
  F64x2RelaxedMax
  I16x8RelaxedQ15mulrS
  I16x8RelaxedDotI8x16I7x16S
  I32x4RelaxedDotI8x16I7x16AddS
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
    StructRef => 21
    ArrayRef => 22
    RefStructAbs => 23
    RefArrayAbs => 24
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
    | (RefNone, RefNone)
    | (StructRef, StructRef)
    | (ArrayRef, ArrayRef)
    | (RefStructAbs, RefStructAbs)
    | (RefArrayAbs, RefArrayAbs) => true
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
  page_size_log2 : Int // custom-page-sizes proposal (default: 16 for 64KiB)
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
  /// Function index -> internal name (e.g., 0 -> "some_func" from $some_func)
  /// Populated from WAT parsing, empty for binary modules without name section
  func_names : Map[Int, String]
} derive(Show)

///|
/// Create an empty module with all fields set to empty arrays/None.
pub fn Module::empty() -> Module {
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
    func_names: {},
  }
}

///|
/// Create a simple module with one function.
/// This is useful for tests that need a minimal valid module.
pub fn Module::simple(
  params : Array[ValueType],
  results : Array[ValueType],
  body : Array[Instruction],
  export_name : String,
) -> Module {
  let func_type : FuncType = { params, results }
  {
    types: [SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: export_name, desc: ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [{ locals: [], body }],
    datas: [],
    tags: [],
    func_names: {},
  }
}

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
    func_names: {},
  }
}

///|
test "parse empty module" {
  let mod = Module::new()
  inspect(mod.types.length(), content="0")
  inspect(mod.funcs.length(), content="0")
  inspect(mod.start, content="None")
}
