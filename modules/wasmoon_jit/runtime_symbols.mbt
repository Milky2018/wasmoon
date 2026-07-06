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
/// Reserve negative function-index values for cwasm runtime-helper fixups.
pub fn gc_runtime_fixup_idx(ordinal : Int) -> Int {
  -20_000 - ordinal
}

///|
/// Reserve negative function-index values for cwasm runtime-helper fixups.
pub fn jit_runtime_fixup_idx(ordinal : Int) -> Int {
  -21_000 - ordinal
}

///|
/// Reserve negative function-index values for cwasm runtime-helper fixups.
pub fn exception_runtime_fixup_idx(ordinal : Int) -> Int {
  -22_000 - ordinal
}

///|
pub fn runtime_hostcall_symbol() -> @instr.ExternalName {
  @instr.ExternalName::new("wasm.runtime.hostcall")
}

///|
pub fn RuntimeSymbolResolver::new() -> RuntimeSymbolResolver {
  { symbols: [] }
}

///|
pub fn RuntimeSymbolResolver::with_wasmoon_runtime_symbols() -> RuntimeSymbolResolver {
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.ref_test",
    @jit_ffi.c_jit_get_gc_ref_test_ptr(),
    gc_runtime_fixup_idx(0),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.ref_cast",
    @jit_ffi.c_jit_get_gc_ref_cast_ptr(),
    gc_runtime_fixup_idx(1),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.struct_new",
    @jit_ffi.c_jit_get_gc_struct_new_ptr(),
    gc_runtime_fixup_idx(2),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.struct_get",
    @jit_ffi.c_jit_get_gc_struct_get_ptr(),
    gc_runtime_fixup_idx(3),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.struct_set",
    @jit_ffi.c_jit_get_gc_struct_set_ptr(),
    gc_runtime_fixup_idx(4),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_new",
    @jit_ffi.c_jit_get_gc_array_new_ptr(),
    gc_runtime_fixup_idx(5),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_get",
    @jit_ffi.c_jit_get_gc_array_get_ptr(),
    gc_runtime_fixup_idx(6),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_set",
    @jit_ffi.c_jit_get_gc_array_set_ptr(),
    gc_runtime_fixup_idx(7),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_len",
    @jit_ffi.c_jit_get_gc_array_len_ptr(),
    gc_runtime_fixup_idx(8),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_fill",
    @jit_ffi.c_jit_get_gc_array_fill_ptr(),
    gc_runtime_fixup_idx(9),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_copy",
    @jit_ffi.c_jit_get_gc_array_copy_ptr(),
    gc_runtime_fixup_idx(10),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_new_data",
    @jit_ffi.c_jit_get_gc_array_new_data_ptr(),
    gc_runtime_fixup_idx(11),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_new_elem",
    @jit_ffi.c_jit_get_gc_array_new_elem_ptr(),
    gc_runtime_fixup_idx(12),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_init_data",
    @jit_ffi.c_jit_get_gc_array_init_data_ptr(),
    gc_runtime_fixup_idx(13),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.array_init_elem",
    @jit_ffi.c_jit_get_gc_array_init_elem_ptr(),
    gc_runtime_fixup_idx(14),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.type_check_subtype",
    @jit_ffi.c_jit_get_gc_type_check_subtype_ptr(),
    gc_runtime_fixup_idx(15),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.register_struct_inline",
    @jit_ffi.c_jit_get_gc_register_struct_inline_ptr(),
    gc_runtime_fixup_idx(16),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.register_array_inline",
    @jit_ffi.c_jit_get_gc_register_array_inline_ptr(),
    gc_runtime_fixup_idx(17),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.alloc_struct_slow",
    @jit_ffi.c_jit_get_gc_alloc_struct_slow_ptr(),
    gc_runtime_fixup_idx(18),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.alloc_array_slow",
    @jit_ffi.c_jit_get_gc_alloc_array_slow_ptr(),
    gc_runtime_fixup_idx(19),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.gc.alloc_array_from_values_slow",
    @jit_ffi.c_jit_get_gc_alloc_array_from_values_slow_ptr(),
    gc_runtime_fixup_idx(20),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_grow",
    @jit_ffi.c_jit_get_memory_grow_ptr(),
    jit_runtime_fixup_idx(0),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_size",
    @jit_ffi.c_jit_get_memory_size_ptr(),
    jit_runtime_fixup_idx(1),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_fill",
    @jit_ffi.c_jit_get_memory_fill_ptr(),
    jit_runtime_fixup_idx(2),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_fill_mem0",
    @jit_ffi.c_jit_get_memory_fill_mem0_ptr(),
    jit_runtime_fixup_idx(3),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_copy",
    @jit_ffi.c_jit_get_memory_copy_ptr(),
    jit_runtime_fixup_idx(4),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.memory_copy_mem0",
    @jit_ffi.c_jit_get_memory_copy_mem0_ptr(),
    jit_runtime_fixup_idx(5),
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
  resolver.add_symbol_fixup(
    "wasmoon.runtime.hostcall",
    @jit_ffi.c_jit_get_hostcall_ptr(),
    jit_runtime_fixup_idx(13),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.try_begin",
    @jit_ffi.c_jit_get_exception_try_begin_ptr(),
    exception_runtime_fixup_idx(0),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.try_end",
    @jit_ffi.c_jit_get_exception_try_end_ptr(),
    exception_runtime_fixup_idx(1),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.throw",
    @jit_ffi.c_jit_get_exception_throw_ptr(),
    exception_runtime_fixup_idx(2),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.throw_tag",
    @jit_ffi.c_jit_get_exception_throw_tag_ptr(),
    exception_runtime_fixup_idx(3),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.throw_ref",
    @jit_ffi.c_jit_get_exception_throw_ref_ptr(),
    exception_runtime_fixup_idx(4),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.delegate",
    @jit_ffi.c_jit_get_exception_delegate_ptr(),
    exception_runtime_fixup_idx(5),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.get_tag",
    @jit_ffi.c_jit_get_exception_get_tag_ptr(),
    exception_runtime_fixup_idx(6),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.get_value",
    @jit_ffi.c_jit_get_exception_get_value_ptr(),
    exception_runtime_fixup_idx(7),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.get_value_count",
    @jit_ffi.c_jit_get_exception_get_value_count_ptr(),
    exception_runtime_fixup_idx(8),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.sigsetjmp",
    @jit_ffi.c_jit_get_sigsetjmp_ptr(),
    exception_runtime_fixup_idx(9),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.spill_locals",
    @jit_ffi.c_jit_get_exception_spill_locals_ptr(),
    exception_runtime_fixup_idx(10),
  )
  resolver.add_symbol_fixup(
    "wasmoon.runtime.exception.get_spilled_local",
    @jit_ffi.c_jit_get_exception_get_spilled_local_ptr(),
    exception_runtime_fixup_idx(11),
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
  match runtime_symbol_wasmoon_alias(name) {
    Some(alias_name) => {
      for symbol in self.symbols {
        if symbol.name == alias_name {
          return Some(symbol)
        }
      }
      None
    }
    None => None
  }
}

///|
fn runtime_symbol_wasmoon_alias(name : String) -> String? {
  match name {
    [.. "wasm.runtime.", .. rest] => Some("wasmoon.runtime." + rest.to_owned())
    _ => None
  }
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
/// Resolve the negative cwasm runtime-helper function index used by Wasmoon
/// JIT call fixups. MachV emission uses named external-symbol relocations, and
/// the cwasm artifact stores those runtime helper targets as negative function
/// indices for the loader to patch.
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
    -20020 => Some(@jit_ffi.c_jit_get_gc_alloc_array_from_values_slow_ptr())
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
pub fn machv_reloc_target_to_cwasm_func_idx(
  target : @machv_emit.RelocTarget,
) -> Int? {
  match target {
    Func(func_idx) => Some(func_idx)
    External(symbol) => {
      let resolver = RuntimeSymbolResolver::with_wasmoon_runtime_symbols()
      match resolver.resolve_symbol(symbol.name) {
        Some(runtime_symbol) => runtime_symbol.fixup_idx
        None => None
      }
    }
  }
}

///|
fn resolve_machv_reloc_target(
  target : @machv_emit.RelocTarget,
  resolver : RuntimeSymbolResolver,
) -> ResolvedRuntimeRelocation? {
  match target {
    Func(func_idx) =>
      Some({
        offset: 0,
        symbol: "wasm.func.\{func_idx}",
        address: 0L,
        fixup_idx: Some(func_idx),
      })
    External(symbol) =>
      match resolver.resolve_symbol(symbol.name) {
        Some(runtime_symbol) =>
          Some({
            offset: 0,
            symbol: symbol.name,
            address: runtime_symbol.address,
            fixup_idx: runtime_symbol.fixup_idx,
          })
        None => None
      }
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
fn runtime_relocations_from_machine_code(
  object : @machv_emit.MachineCode,
  resolver : RuntimeSymbolResolver,
) -> Array[ResolvedRuntimeRelocation] raise LinkError {
  let runtime_relocations : Array[ResolvedRuntimeRelocation] = []
  for fixup in object.get_call_fixups() {
    match resolve_machv_reloc_target(fixup.target, resolver) {
      Some(relocation) =>
        runtime_relocations.push({
          offset: fixup.offset,
          symbol: relocation.symbol,
          address: relocation.address,
          fixup_idx: relocation.fixup_idx,
        })
      None => {
        let name = match fixup.target {
          Func(func_idx) => "wasm.func.\{func_idx}"
          External(symbol) => symbol.name
        }
        raise UnknownRuntimeSymbol(name)
      }
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
