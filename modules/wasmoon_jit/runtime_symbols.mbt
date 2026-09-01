///|
pub(all) struct RuntimeSymbol {
  name : String
  address : Int64
} derive(Eq, Debug)

///|
pub(all) struct RuntimeSymbolResolver {
  symbols : Array[RuntimeSymbol]
} derive(Debug)

///|
pub fn wasm_runtime_symbols() -> @wasm_milkir.RuntimeSymbols {
  @wasm_milkir.RuntimeSymbols::with_runtime_prefix("wasmoon.runtime")
}

///|
pub fn RuntimeSymbolResolver::RuntimeSymbolResolver() -> RuntimeSymbolResolver {
  { symbols: [], }
}

///|
pub fn RuntimeSymbolResolver::with_wasmoon_runtime_symbols() -> RuntimeSymbolResolver {
  let resolver = RuntimeSymbolResolver::RuntimeSymbolResolver()
  let names = wasm_runtime_symbols()
  fn add(helper : @wasm_milkir.WasmRuntimeHelper, address : Int64) {
    resolver.add_symbol(names.symbol_name(helper), address)
  }
  add(GcRefTest, c_jit_get_gc_ref_test_ptr())
  add(GcRefCast, c_jit_get_gc_ref_cast_ptr())
  resolver.add_symbol(
    "wasmoon.runtime.gc.struct_new",
    c_jit_get_gc_struct_new_ptr(),
  )
  add(GcStructGet, c_jit_get_gc_struct_get_ptr())
  add(GcStructSet, c_jit_get_gc_struct_set_ptr())
  add(GcStructGetV128, c_jit_get_gc_struct_get_v128_ptr())
  add(GcStructSetV128, c_jit_get_gc_struct_set_v128_ptr())
  add(GcArrayGetV128, c_jit_get_gc_array_get_v128_ptr())
  add(GcArraySetV128, c_jit_get_gc_array_set_v128_ptr())
  add(GcArrayFillV128, c_jit_get_gc_array_fill_v128_ptr())
  add(GcAllocStructWideSlow, c_jit_get_gc_alloc_struct_wide_slow_ptr())
  add(GcAllocArrayWideSlow, c_jit_get_gc_alloc_array_wide_slow_ptr())
  add(GcAllocArrayFromSlotsSlow, c_jit_get_gc_alloc_array_from_slots_slow_ptr())
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_new",
    c_jit_get_gc_array_new_ptr(),
  )
  add(GcArrayGet, c_jit_get_gc_array_get_ptr())
  add(GcArraySet, c_jit_get_gc_array_set_ptr())
  add(GcArrayLen, c_jit_get_gc_array_len_ptr())
  add(GcArrayFill, c_jit_get_gc_array_fill_ptr())
  add(GcArrayCopy, c_jit_get_gc_array_copy_ptr())
  add(GcArrayNewData, c_jit_get_gc_array_new_data_ptr())
  add(GcArrayNewElem, c_jit_get_gc_array_new_elem_ptr())
  add(GcArrayInitData, c_jit_get_gc_array_init_data_ptr())
  add(GcArrayInitElem, c_jit_get_gc_array_init_elem_ptr())
  add(GcTypeCheckSubtype, c_jit_get_gc_type_check_subtype_ptr())
  add(GcRegisterStructInline, c_jit_get_gc_register_struct_inline_ptr())
  add(GcRegisterArrayInline, c_jit_get_gc_register_array_inline_ptr())
  add(GcAllocStructSlow, c_jit_get_gc_alloc_struct_slow_ptr())
  add(GcAllocArraySlow, c_jit_get_gc_alloc_array_slow_ptr())
  add(
    GcAllocArrayFromValuesSlow,
    c_jit_get_gc_alloc_array_from_values_slow_ptr(),
  )
  resolver.add_symbol(
    gc_push_root_scope_symbol(),
    c_jit_get_gc_push_root_scope_ptr(),
  )
  resolver.add_symbol(
    gc_pop_root_scope_symbol(),
    c_jit_get_gc_pop_root_scope_ptr(),
  )
  add(MemoryGrow, c_jit_get_memory_grow_ptr())
  add(MemorySize, c_jit_get_memory_size_ptr())
  add(MemoryFill, c_jit_get_memory_fill_ptr())
  add(MemoryCopy, c_jit_get_memory_copy_ptr())
  add(MemoryInit, c_jit_get_memory_init_ptr())
  add(DataDrop, c_jit_get_data_drop_ptr())
  add(TableGrow, c_jit_get_table_grow_ptr())
  add(TableFill, c_jit_get_table_fill_ptr())
  add(TableCopy, c_jit_get_table_copy_ptr())
  add(TableInit, c_jit_get_table_init_ptr())
  add(ElemDrop, c_jit_get_elem_drop_ptr())
  resolver.add_symbol("wasmoon.runtime.hostcall", c_jit_get_hostcall_ptr())
  add(CancelPoll, c_jit_get_cancel_poll_ptr())
  add(ExceptionTryBegin, c_jit_get_exception_try_begin_ptr())
  add(ExceptionTryEnd, c_jit_get_exception_try_end_ptr())
  add(ExceptionThrow, c_jit_get_exception_throw_ptr())
  add(ExceptionThrowTag, c_jit_get_exception_throw_tag_ptr())
  add(ExceptionThrowRef, c_jit_get_exception_throw_ref_ptr())
  add(ExceptionDelegate, c_jit_get_exception_delegate_ptr())
  add(ExceptionGetTag, c_jit_get_exception_get_tag_ptr())
  add(ExceptionGetValue, c_jit_get_exception_get_value_ptr())
  add(ExceptionGetValueCount, c_jit_get_exception_get_value_count_ptr())
  add(ExceptionSigsetjmp, c_jit_get_sigsetjmp_ptr())
  add(ExceptionSpillLocals, c_jit_get_exception_spill_locals_ptr())
  add(ExceptionGetSpilledLocal, c_jit_get_exception_get_spilled_local_ptr())
  resolver
}

///|
/// Stable external-symbol whitelist accepted by Wasmoon artifacts.
pub fn wasmoon_runtime_external_symbols() -> Array[@native.ExternalSymbol] {
  RuntimeSymbolResolver::with_wasmoon_runtime_symbols().symbols.map(symbol => {
    @native.ExternalSymbol::new(symbol.name)
  })
}

///|
pub fn RuntimeSymbolResolver::add_symbol(
  self : RuntimeSymbolResolver,
  name : String,
  address : Int64,
) -> Unit {
  self.symbols.push({ name, address, })
}

///|
pub fn RuntimeSymbolResolver::resolve_symbol(
  self : RuntimeSymbolResolver,
  name : String,
) -> RuntimeSymbol? {
  for symbol in self.symbols {
    if symbol.name == name {
      return Some(symbol)
    }
  }
  None
}

///|
pub fn RuntimeSymbolResolver::resolve(
  self : RuntimeSymbolResolver,
  name : String,
) -> Int64? {
  match self.resolve_symbol(name) {
    Some(symbol) => Some(symbol.address)
    None => None
  }
}
