///|
/// Runtime operations required by WebAssembly lowering.
///
/// The helper identity stays typed throughout lowering. An embedding assigns
/// its external symbol spelling only when the operation enters MilkIR or
/// MachV.
pub(all) enum WasmRuntimeHelper {
  MemoryGrow
  MemorySize
  MemoryFill
  MemoryCopy
  MemoryInit
  DataDrop
  TableGrow
  TableFill
  TableCopy
  TableInit
  ElemDrop
  CancelPoll
  GcRefTest
  GcRefCast
  GcStructGet
  GcStructSet
  GcArrayGet
  GcArraySet
  GcArrayLen
  GcArrayFill
  GcArrayCopy
  GcArrayNewData
  GcArrayNewElem
  GcArrayInitData
  GcArrayInitElem
  GcTypeCheckSubtype
  GcRegisterStructInline
  GcRegisterArrayInline
  GcAllocStructSlow
  GcAllocArrayFromValuesSlow
  GcAllocArraySlow
  GcStructGetV128
  GcStructSetV128
  GcArrayGetV128
  GcArraySetV128
  GcArrayFillV128
  GcAllocStructWideSlow
  GcAllocArrayWideSlow
  GcAllocArrayFromSlotsSlow
  ExceptionTryBegin
  ExceptionTryEnd
  ExceptionThrow
  ExceptionThrowTag
  ExceptionThrowRef
  ExceptionDelegate
  ExceptionGetTag
  ExceptionGetValue
  ExceptionGetValueCount
  ExceptionSigsetjmp
  ExceptionSpillLocals
  ExceptionGetSpilledLocal
} derive(Debug, Eq)

///|
fn WasmRuntimeHelper::suffix(self : WasmRuntimeHelper) -> String {
  match self {
    MemoryGrow => "memory_grow"
    MemorySize => "memory_size"
    MemoryFill => "memory_fill"
    MemoryCopy => "memory_copy"
    MemoryInit => "memory_init"
    DataDrop => "data_drop"
    TableGrow => "table_grow"
    TableFill => "table_fill"
    TableCopy => "table_copy"
    TableInit => "table_init"
    ElemDrop => "elem_drop"
    CancelPoll => "cancel_poll"
    GcRefTest => "gc.ref_test"
    GcRefCast => "gc.ref_cast"
    GcStructGet => "gc.struct_get"
    GcStructSet => "gc.struct_set"
    GcArrayGet => "gc.array_get"
    GcArraySet => "gc.array_set"
    GcArrayLen => "gc.array_len"
    GcArrayFill => "gc.array_fill"
    GcArrayCopy => "gc.array_copy"
    GcArrayNewData => "gc.array_new_data"
    GcArrayNewElem => "gc.array_new_elem"
    GcArrayInitData => "gc.array_init_data"
    GcArrayInitElem => "gc.array_init_elem"
    GcTypeCheckSubtype => "gc.type_check_subtype"
    GcRegisterStructInline => "gc.register_struct_inline"
    GcRegisterArrayInline => "gc.register_array_inline"
    GcAllocStructSlow => "gc.alloc_struct_slow"
    GcAllocArrayFromValuesSlow => "gc.alloc_array_from_values_slow"
    GcAllocArraySlow => "gc.alloc_array_slow"
    GcStructGetV128 => "gc.struct_get_v128"
    GcStructSetV128 => "gc.struct_set_v128"
    GcArrayGetV128 => "gc.array_get_v128"
    GcArraySetV128 => "gc.array_set_v128"
    GcArrayFillV128 => "gc.array_fill_v128"
    GcAllocStructWideSlow => "gc.alloc_struct_wide_slow"
    GcAllocArrayWideSlow => "gc.alloc_array_wide_slow"
    GcAllocArrayFromSlotsSlow => "gc.alloc_array_from_slots_slow"
    ExceptionTryBegin => "exception.try_begin"
    ExceptionTryEnd => "exception.try_end"
    ExceptionThrow => "exception.throw"
    ExceptionThrowTag => "exception.throw_tag"
    ExceptionThrowRef => "exception.throw_ref"
    ExceptionDelegate => "exception.delegate"
    ExceptionGetTag => "exception.get_tag"
    ExceptionGetValue => "exception.get_value"
    ExceptionGetValueCount => "exception.get_value_count"
    ExceptionSigsetjmp => "exception.sigsetjmp"
    ExceptionSpillLocals => "exception.spill_locals"
    ExceptionGetSpilledLocal => "exception.get_spilled_local"
  }
}

///|
/// Embedding-specific external names for WebAssembly runtime helpers.
struct RuntimeSymbols {
  prefix : String
} derive(Debug, Eq)

///|
pub fn RuntimeSymbols::with_runtime_prefix(prefix : String) -> RuntimeSymbols {
  { prefix, }
}

///|
pub fn RuntimeSymbols::symbol_name(
  self : RuntimeSymbols,
  helper : WasmRuntimeHelper,
) -> String {
  self.prefix + "." + helper.suffix()
}
