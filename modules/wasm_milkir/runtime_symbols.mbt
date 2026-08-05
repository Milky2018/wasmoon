///|
pub(all) struct RuntimeSymbols {
  memory_grow : String
  memory_size : String
  memory_fill : String
  memory_copy : String
  memory_init : String
  data_drop : String
  table_grow : String
  table_fill : String
  table_copy : String
  table_init : String
  elem_drop : String
  gc_ref_test : String
  gc_ref_cast : String
  gc_struct_get : String
  gc_struct_set : String
  gc_array_get : String
  gc_array_set : String
  gc_array_len : String
  gc_array_fill : String
  gc_array_copy : String
  gc_array_new_data : String
  gc_array_new_elem : String
  gc_array_init_data : String
  gc_array_init_elem : String
  gc_type_check_subtype : String
  gc_register_struct_inline : String
  gc_register_array_inline : String
  gc_alloc_struct_slow : String
  gc_alloc_array_from_values_slow : String
  gc_alloc_array_slow : String
  // v128 aggregate operations. A v128 is wider than the runtime word the
  // symbols above are built on, so these pass it by address instead.
  gc_struct_get_v128 : String
  gc_struct_set_v128 : String
  gc_array_get_v128 : String
  gc_array_set_v128 : String
  gc_array_fill_v128 : String
  gc_alloc_struct_wide_slow : String
  gc_alloc_array_wide_slow : String
  gc_alloc_array_from_slots_slow : String
  exception_try_begin : String
  exception_try_end : String
  exception_throw : String
  exception_throw_tag : String
  exception_throw_ref : String
  exception_delegate : String
  exception_get_tag : String
  exception_get_value : String
  exception_get_value_count : String
  exception_sigsetjmp : String
  exception_spill_locals : String
  exception_get_spilled_local : String
} derive(Debug, Eq)

///|
fn prefixed(prefix : String, name : String) -> String {
  prefix + "." + name
}

///|
fn prefixed_gc(prefix : String, name : String) -> String {
  prefixed(prefix, "gc.\{name}")
}

///|
fn prefixed_exception(prefix : String, name : String) -> String {
  prefixed(prefix, "exception.\{name}")
}

///|
pub fn RuntimeSymbols::with_runtime_prefix(prefix : String) -> RuntimeSymbols {
  {
    memory_grow: prefixed(prefix, "memory_grow"),
    memory_size: prefixed(prefix, "memory_size"),
    memory_fill: prefixed(prefix, "memory_fill"),
    memory_copy: prefixed(prefix, "memory_copy"),
    memory_init: prefixed(prefix, "memory_init"),
    data_drop: prefixed(prefix, "data_drop"),
    table_grow: prefixed(prefix, "table_grow"),
    table_fill: prefixed(prefix, "table_fill"),
    table_copy: prefixed(prefix, "table_copy"),
    table_init: prefixed(prefix, "table_init"),
    elem_drop: prefixed(prefix, "elem_drop"),
    gc_ref_test: prefixed_gc(prefix, "ref_test"),
    gc_ref_cast: prefixed_gc(prefix, "ref_cast"),
    gc_struct_get: prefixed_gc(prefix, "struct_get"),
    gc_struct_set: prefixed_gc(prefix, "struct_set"),
    gc_array_get: prefixed_gc(prefix, "array_get"),
    gc_array_set: prefixed_gc(prefix, "array_set"),
    gc_array_len: prefixed_gc(prefix, "array_len"),
    gc_array_fill: prefixed_gc(prefix, "array_fill"),
    gc_array_copy: prefixed_gc(prefix, "array_copy"),
    gc_array_new_data: prefixed_gc(prefix, "array_new_data"),
    gc_array_new_elem: prefixed_gc(prefix, "array_new_elem"),
    gc_array_init_data: prefixed_gc(prefix, "array_init_data"),
    gc_array_init_elem: prefixed_gc(prefix, "array_init_elem"),
    gc_type_check_subtype: prefixed_gc(prefix, "type_check_subtype"),
    gc_register_struct_inline: prefixed_gc(prefix, "register_struct_inline"),
    gc_register_array_inline: prefixed_gc(prefix, "register_array_inline"),
    gc_alloc_struct_slow: prefixed_gc(prefix, "alloc_struct_slow"),
    gc_alloc_array_from_values_slow: prefixed_gc(
      prefix, "alloc_array_from_values_slow",
    ),
    gc_alloc_array_slow: prefixed_gc(prefix, "alloc_array_slow"),
    gc_struct_get_v128: prefixed_gc(prefix, "struct_get_v128"),
    gc_struct_set_v128: prefixed_gc(prefix, "struct_set_v128"),
    gc_array_get_v128: prefixed_gc(prefix, "array_get_v128"),
    gc_array_set_v128: prefixed_gc(prefix, "array_set_v128"),
    gc_array_fill_v128: prefixed_gc(prefix, "array_fill_v128"),
    gc_alloc_struct_wide_slow: prefixed_gc(prefix, "alloc_struct_wide_slow"),
    gc_alloc_array_wide_slow: prefixed_gc(prefix, "alloc_array_wide_slow"),
    gc_alloc_array_from_slots_slow: prefixed_gc(
      prefix, "alloc_array_from_slots_slow",
    ),
    exception_try_begin: prefixed_exception(prefix, "try_begin"),
    exception_try_end: prefixed_exception(prefix, "try_end"),
    exception_throw: prefixed_exception(prefix, "throw"),
    exception_throw_tag: prefixed_exception(prefix, "throw_tag"),
    exception_throw_ref: prefixed_exception(prefix, "throw_ref"),
    exception_delegate: prefixed_exception(prefix, "delegate"),
    exception_get_tag: prefixed_exception(prefix, "get_tag"),
    exception_get_value: prefixed_exception(prefix, "get_value"),
    exception_get_value_count: prefixed_exception(prefix, "get_value_count"),
    exception_sigsetjmp: prefixed_exception(prefix, "sigsetjmp"),
    exception_spill_locals: prefixed_exception(prefix, "spill_locals"),
    exception_get_spilled_local: prefixed_exception(prefix, "get_spilled_local"),
  }
}
