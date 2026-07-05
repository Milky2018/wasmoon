///|
pub(all) struct RuntimeSymbol {
  name : String
  address : Int64
  fixup_idx : Int?
} derive(Eq, Debug)

///|
pub(all) struct RuntimeSymbolResolver {
  symbols : Array[RuntimeSymbol]
} derive(Debug)

///|
pub suberror LinkError {
  UnknownRuntimeSymbol(String)
} derive(Debug, Eq)

///|
pub impl Show for LinkError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
/// Reserve negative function-index values for legacy runtime helper fixups.
pub fn gc_runtime_fixup_idx(ordinal : Int) -> Int {
  -20_000 - ordinal
}

///|
/// Reserve negative function-index values for legacy runtime helper fixups.
pub fn jit_runtime_fixup_idx(ordinal : Int) -> Int {
  -21_000 - ordinal
}

///|
/// Reserve negative function-index values for legacy runtime helper fixups.
pub fn exception_runtime_fixup_idx(ordinal : Int) -> Int {
  -22_000 - ordinal
}

///|
pub fn RuntimeSymbolResolver::new() -> RuntimeSymbolResolver {
  { symbols: [] }
}

///|
pub fn RuntimeSymbolResolver::with_wasmoon_runtime_symbols() -> RuntimeSymbolResolver {
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_grow",
    @jit_ffi.c_jit_get_memory_grow_ptr(),
    jit_runtime_fixup_idx(0),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_fill",
    @jit_ffi.c_jit_get_memory_fill_ptr(),
    jit_runtime_fixup_idx(2),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_copy",
    @jit_ffi.c_jit_get_memory_copy_ptr(),
    jit_runtime_fixup_idx(4),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_init",
    @jit_ffi.c_jit_get_memory_init_ptr(),
    jit_runtime_fixup_idx(6),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.data_drop",
    @jit_ffi.c_jit_get_data_drop_ptr(),
    jit_runtime_fixup_idx(7),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.table_grow",
    @jit_ffi.c_jit_get_table_grow_ptr(),
    jit_runtime_fixup_idx(8),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.table_fill",
    @jit_ffi.c_jit_get_table_fill_ptr(),
    jit_runtime_fixup_idx(9),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.table_copy",
    @jit_ffi.c_jit_get_table_copy_ptr(),
    jit_runtime_fixup_idx(10),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.table_init",
    @jit_ffi.c_jit_get_table_init_ptr(),
    jit_runtime_fixup_idx(11),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.elem_drop",
    @jit_ffi.c_jit_get_elem_drop_ptr(),
    jit_runtime_fixup_idx(12),
  )
  resolver
}

///|
pub fn RuntimeSymbolResolver::add_symbol(
  self : RuntimeSymbolResolver,
  name : String,
  address : Int64,
) -> Unit {
  self.symbols.push({ name, address, fixup_idx: None })
}

///|
pub fn RuntimeSymbolResolver::add_symbol_fixup(
  self : RuntimeSymbolResolver,
  name : String,
  address : Int64,
  fixup_idx : Int,
) -> Unit {
  self.symbols.push({ name, address, fixup_idx: Some(fixup_idx) })
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

///|
fn parse_decimal_int(text : StringView) -> Int? {
  if text.length() == 0 {
    return None
  }
  let mut value = 0
  for i in 0..<text.length() {
    let ch = text.code_unit_at(i)
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10 + (ch.to_int() - '0')
  }
  Some(value)
}

///|
pub fn resolve_wasm_func_symbol(name : String) -> Int? {
  match name {
    [.. "wasm.func.", .. rest] => parse_decimal_int(rest)
    _ => None
  }
}

///|
/// Resolve the legacy negative runtime-helper fixup id used by the old VCode
/// emitter. New MachV emission should prefer named external-symbol relocations.
/// TODO(ISS-021): delete this compatibility entry once the production JIT
/// loader consumes `machv_emit` relocations end-to-end.
pub fn resolve_runtime_func_fixup_idx(idx : Int) -> Int64? {
  match idx {
    -20000 => Some(@jit_ffi.c_jit_get_gc_ref_test_ptr())
    -20001 => Some(@jit_ffi.c_jit_get_gc_ref_cast_ptr())
    -20002 => Some(@jit_ffi.c_jit_get_gc_struct_new_ptr())
    -20003 => Some(@jit_ffi.c_jit_get_gc_struct_get_ptr())
    -20004 => Some(@jit_ffi.c_jit_get_gc_struct_set_ptr())
    -20005 => Some(@jit_ffi.c_jit_get_gc_array_new_ptr())
    -20006 => Some(@jit_ffi.c_jit_get_gc_array_get_ptr())
    -20007 => Some(@jit_ffi.c_jit_get_gc_array_set_ptr())
    -20008 => Some(@jit_ffi.c_jit_get_gc_array_len_ptr())
    -20009 => Some(@jit_ffi.c_jit_get_gc_array_fill_ptr())
    -20010 => Some(@jit_ffi.c_jit_get_gc_array_copy_ptr())
    -20011 => Some(@jit_ffi.c_jit_get_gc_array_new_data_ptr())
    -20012 => Some(@jit_ffi.c_jit_get_gc_array_new_elem_ptr())
    -20013 => Some(@jit_ffi.c_jit_get_gc_array_init_data_ptr())
    -20014 => Some(@jit_ffi.c_jit_get_gc_array_init_elem_ptr())
    -20015 => Some(@jit_ffi.c_jit_get_gc_type_check_subtype_ptr())
    -20016 => Some(@jit_ffi.c_jit_get_gc_register_struct_inline_ptr())
    -20017 => Some(@jit_ffi.c_jit_get_gc_register_array_inline_ptr())
    -20018 => Some(@jit_ffi.c_jit_get_gc_alloc_struct_slow_ptr())
    -20019 => Some(@jit_ffi.c_jit_get_gc_alloc_array_slow_ptr())
    -21000 => Some(@jit_ffi.c_jit_get_memory_grow_ptr())
    -21001 => Some(@jit_ffi.c_jit_get_memory_size_ptr())
    -21002 => Some(@jit_ffi.c_jit_get_memory_fill_ptr())
    -21003 => Some(@jit_ffi.c_jit_get_memory_fill_mem0_ptr())
    -21004 => Some(@jit_ffi.c_jit_get_memory_copy_ptr())
    -21005 => Some(@jit_ffi.c_jit_get_memory_copy_mem0_ptr())
    -21006 => Some(@jit_ffi.c_jit_get_memory_init_ptr())
    -21007 => Some(@jit_ffi.c_jit_get_data_drop_ptr())
    -21008 => Some(@jit_ffi.c_jit_get_table_grow_ptr())
    -21009 => Some(@jit_ffi.c_jit_get_table_fill_ptr())
    -21010 => Some(@jit_ffi.c_jit_get_table_copy_ptr())
    -21011 => Some(@jit_ffi.c_jit_get_table_init_ptr())
    -21012 => Some(@jit_ffi.c_jit_get_elem_drop_ptr())
    -21013 => Some(@jit_ffi.c_jit_get_hostcall_ptr())
    -22000 => Some(@jit_ffi.c_jit_get_exception_try_begin_ptr())
    -22001 => Some(@jit_ffi.c_jit_get_exception_try_end_ptr())
    -22002 => Some(@jit_ffi.c_jit_get_exception_throw_ptr())
    -22003 => Some(@jit_ffi.c_jit_get_exception_throw_tag_ptr())
    -22004 => Some(@jit_ffi.c_jit_get_exception_throw_ref_ptr())
    -22005 => Some(@jit_ffi.c_jit_get_exception_delegate_ptr())
    -22006 => Some(@jit_ffi.c_jit_get_exception_get_tag_ptr())
    -22007 => Some(@jit_ffi.c_jit_get_exception_get_value_ptr())
    -22008 => Some(@jit_ffi.c_jit_get_exception_get_value_count_ptr())
    -22009 => Some(@jit_ffi.c_jit_get_sigsetjmp_ptr())
    -22010 => Some(@jit_ffi.c_jit_get_exception_spill_locals_ptr())
    -22011 => Some(@jit_ffi.c_jit_get_exception_get_spilled_local_ptr())
    _ => None
  }
}

///|
pub(all) struct ResolvedRuntimeRelocation {
  offset : Int
  symbol : String
  address : Int64
  fixup_idx : Int?
} derive(Eq, Debug)

///|
pub(all) struct LinkedCode {
  code : Array[Int]
  frame_size : Int
  runtime_relocations : Array[ResolvedRuntimeRelocation]
  func_addr_fixups : Array[@machv_emit.FuncAddrFixup]
  call_fixups : Array[@machv_emit.CallFixup]
  gc_safepoints : Array[@machv_emit.GcSafepoint]
  gc_stackmap_blob : Bytes
} derive(Debug)

///|
fn cwasm_symbol_for_fixup_idx(func_idx : Int) -> String {
  if func_idx >= 0 {
    "wasm.func.\{func_idx}"
  } else {
    "wasmoon.runtime.fixup.\{func_idx}"
  }
}

///|
fn runtime_relocations_from_machine_code(
  object : @machv_emit.MachineCode,
  resolver : RuntimeSymbolResolver,
) -> Array[ResolvedRuntimeRelocation] raise LinkError {
  let runtime_relocations : Array[ResolvedRuntimeRelocation] = []
  for fixup in object.get_call_fixups() {
    let symbol = cwasm_symbol_for_fixup_idx(fixup.func_idx)
    if fixup.func_idx >= 0 {
      runtime_relocations.push({
        offset: fixup.offset,
        symbol,
        address: 0L,
        fixup_idx: Some(fixup.func_idx),
      })
    } else if resolve_runtime_func_fixup_idx(fixup.func_idx) is Some(address) {
      runtime_relocations.push({
        offset: fixup.offset,
        symbol,
        address,
        fixup_idx: Some(fixup.func_idx),
      })
    } else if resolver.resolve_symbol(symbol) is Some(runtime_symbol) {
      runtime_relocations.push({
        offset: fixup.offset,
        symbol,
        address: runtime_symbol.address,
        fixup_idx: runtime_symbol.fixup_idx,
      })
    } else {
      raise UnknownRuntimeSymbol(symbol)
    }
  }
  runtime_relocations
}

///|
pub fn link_machine_code(
  object : @machv_emit.MachineCode,
  resolver : RuntimeSymbolResolver,
) -> LinkedCode raise LinkError {
  {
    code: object.get_bytes(),
    frame_size: 0,
    runtime_relocations: runtime_relocations_from_machine_code(object, resolver),
    func_addr_fixups: object.get_func_addr_fixups(),
    call_fixups: object.get_call_fixups(),
    gc_safepoints: @machv_emit.CompiledFunction::new("", object, 0).get_gc_safepoints(),
    gc_stackmap_blob: @machv_emit.CompiledFunction::new("", object, 0).get_gc_stackmap_blob(),
  }
}

///|
pub fn link_code_object(
  object : @machv_emit.MachineCode,
  resolver : RuntimeSymbolResolver,
) -> LinkedCode raise LinkError {
  link_machine_code(object, resolver)
}
