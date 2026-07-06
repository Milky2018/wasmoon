///|
/// Wasm semantic extension opcodes carried by `Opcode::Wasm`.
///
/// These operations are behavior-preserving migration shims: they keep existing
/// Wasmoon lowering and optimization behavior while making the generic MilkIR
/// core opcode list explicit about which operations are not generic IR concepts.
/// TODO(ISS-065): Move these builders and validators to a Wasm-owned extension
/// package once MoonBit package boundaries can expose extension opcodes without
/// forcing Wasm concepts back into the reusable core package.
pub(all) enum WasmOpcode {
  // Linear memory operations.
  // TODO(ISS-065): Lower memory growth/size/bulk-memory operations through
  // embedding-provided runtime helper symbols or generic memory-effect calls.
  LoadMemBase(Int) // Load linear memory base pointer (memidx) - operands: vmctx
  MemoryGrow(Int, Int?) // Grow memory by delta pages (memidx, max_pages)
  MemorySize(Int) // Get current memory size in pages (memidx)
  MemoryFill(Int) // Fill memory region with a byte value (memidx)
  MemoryCopy(Int, Int) // Copy memory region (dst_memidx, src_memidx)
  MemoryInit(Int, Int) // Initialize memory from data segment (memidx, data_idx)
  DataDrop(Int) // Drop data segment (data_idx)

  // Table operations.
  // TODO(ISS-065): Lower table bulk operations through embedding-provided
  // runtime helper symbols and keep table layout in the Wasm frontend.
  TableGrow(Int) // Grow table, returns previous size or -1 (table index)
  TableFill(Int) // Fill table region with value (table_idx)
  TableCopy(Int, Int) // Copy table region (dst_table_idx, src_table_idx)
  TableInit(Int, Int) // Initialize table from elem segment (table_idx, elem_idx)
  ElemDrop(Int) // Drop element segment (elem_idx)

  // Wasm function calls and references.
  // TODO(ISS-065): Represent direct/indirect Wasm calls as generic calls with
  // call-site metadata supplied by the Wasm frontend.
  WasmCall(Int) // Direct Wasm call (function index)
  WasmCallIndirect(Int, Int) // Indirect Wasm call (type index, table index)
  CallRef(Int) // Call through function reference (type index)
  ReturnCall(Int) // Tail call (function index)
  ReturnCallIndirect(Int, Int) // Tail call indirect (type index, table index)
  ReturnCallRef(Int) // Tail call through function reference (type index)
  GetFuncRef(Int) // Get tagged function reference (function index)

  // Wasm GC struct operations.
  // TODO(ISS-065): Model these as Wasm-GC runtime/helper calls or a dedicated
  // GC extension that does not expose Wasm type indices as generic core data.
  StructNew(Int)
  StructNewDefault(Int)
  StructGet(Int, Int)
  StructGetS(Int, Int, Int)
  StructGetU(Int, Int, Int)
  StructSet(Int, Int)

  // Wasm GC array operations.
  // TODO(ISS-065): Move array/data/elem segment interpretation to the Wasm
  // frontend and leave MilkIR with generic heap operations or helper calls.
  ArrayNew(Int)
  ArrayNewDefault(Int)
  ArrayNewFixed(Int, Int)
  ArrayGet(Int)
  ArrayGetS(Int, Int)
  ArrayGetU(Int, Int)
  ArraySet(Int)
  ArrayLen
  ArrayFill(Int)
  ArrayCopy(Int, Int)
  ArrayNewData(Int, Int)
  ArrayNewElem(Int, Int)
  ArrayInitData(Int, Int)
  ArrayInitElem(Int, Int)

  // Wasm GC reference operations.
  // TODO(ISS-065): Replace Wasm reference-test/cast/type-conversion opcodes
  // with a generic reference operation model plus Wasm-owned type metadata.
  I31New
  I31GetS
  I31GetU
  RefTest(Int, Bool)
  RefCast(Int, Bool)
  AnyConvertExtern
  ExternConvertAny
  RefEq

  // Wasm exception handling operations.
  // TODO(ISS-065): Express exception state through generic EH constructs or
  // Wasm-owned runtime helper calls instead of core opcodes.
  Throw(Int)
  ThrowRef
  TryTableBegin(Int)
  TryTableEnd(Int)
  GetExceptionTag
  GetExceptionValue(Int)
  GetExceptionValueCount
  Delegate(Int)
  SpillLocalsForThrow(Int)
  GetSpilledLocal(Int)
} derive(Debug, Eq, Hash)
