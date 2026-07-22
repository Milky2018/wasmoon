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
  { symbols: [] }
}

///|
pub fn RuntimeSymbolResolver::with_wasmoon_runtime_symbols() -> RuntimeSymbolResolver {
  let resolver = RuntimeSymbolResolver::RuntimeSymbolResolver()
  resolver.add_symbol(
    "wasmoon.runtime.gc.ref_test",
    c_jit_get_gc_ref_test_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.ref_cast",
    c_jit_get_gc_ref_cast_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.struct_new",
    c_jit_get_gc_struct_new_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.struct_get",
    c_jit_get_gc_struct_get_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.struct_set",
    c_jit_get_gc_struct_set_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_new",
    c_jit_get_gc_array_new_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_get",
    c_jit_get_gc_array_get_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_set",
    c_jit_get_gc_array_set_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_len",
    c_jit_get_gc_array_len_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_fill",
    c_jit_get_gc_array_fill_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_copy",
    c_jit_get_gc_array_copy_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_new_data",
    c_jit_get_gc_array_new_data_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_new_elem",
    c_jit_get_gc_array_new_elem_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_init_data",
    c_jit_get_gc_array_init_data_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.array_init_elem",
    c_jit_get_gc_array_init_elem_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.type_check_subtype",
    c_jit_get_gc_type_check_subtype_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.register_struct_inline",
    c_jit_get_gc_register_struct_inline_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.register_array_inline",
    c_jit_get_gc_register_array_inline_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.alloc_struct_slow",
    c_jit_get_gc_alloc_struct_slow_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.alloc_array_slow",
    c_jit_get_gc_alloc_array_slow_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.gc.alloc_array_from_values_slow",
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
  resolver.add_symbol(
    "wasmoon.runtime.memory_grow",
    c_jit_get_memory_grow_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.memory_size",
    c_jit_get_memory_size_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.memory_fill",
    c_jit_get_memory_fill_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.memory_copy",
    c_jit_get_memory_copy_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.memory_init",
    c_jit_get_memory_init_ptr(),
  )
  resolver.add_symbol("wasmoon.runtime.data_drop", c_jit_get_data_drop_ptr())
  resolver.add_symbol("wasmoon.runtime.table_grow", c_jit_get_table_grow_ptr())
  resolver.add_symbol("wasmoon.runtime.table_fill", c_jit_get_table_fill_ptr())
  resolver.add_symbol("wasmoon.runtime.table_copy", c_jit_get_table_copy_ptr())
  resolver.add_symbol("wasmoon.runtime.table_init", c_jit_get_table_init_ptr())
  resolver.add_symbol("wasmoon.runtime.elem_drop", c_jit_get_elem_drop_ptr())
  resolver.add_symbol("wasmoon.runtime.hostcall", c_jit_get_hostcall_ptr())
  resolver.add_symbol(
    "wasmoon.runtime.cancel_poll",
    c_jit_get_cancel_poll_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.try_begin",
    c_jit_get_exception_try_begin_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.try_end",
    c_jit_get_exception_try_end_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.throw",
    c_jit_get_exception_throw_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.throw_tag",
    c_jit_get_exception_throw_tag_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.throw_ref",
    c_jit_get_exception_throw_ref_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.delegate",
    c_jit_get_exception_delegate_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.get_tag",
    c_jit_get_exception_get_tag_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.get_value",
    c_jit_get_exception_get_value_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.get_value_count",
    c_jit_get_exception_get_value_count_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.sigsetjmp",
    c_jit_get_sigsetjmp_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.spill_locals",
    c_jit_get_exception_spill_locals_ptr(),
  )
  resolver.add_symbol(
    "wasmoon.runtime.exception.get_spilled_local",
    c_jit_get_exception_get_spilled_local_ptr(),
  )
  resolver
}

///|
/// Stable external-symbol whitelist accepted by Wasmoon artifacts.
pub fn wasmoon_runtime_external_symbols() -> Array[
  @semantic_machv.ExternalSymbol,
] {
  RuntimeSymbolResolver::with_wasmoon_runtime_symbols().symbols.map(symbol => {
    @semantic_machv.ExternalSymbol::new(symbol.name)
  })
}

///|
pub fn RuntimeSymbolResolver::add_symbol(
  self : RuntimeSymbolResolver,
  name : String,
  address : Int64,
) -> Unit {
  self.symbols.push({ name, address })
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
