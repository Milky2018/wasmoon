///|
fn external_symbol(name : String) -> @instr.ExternalName {
  @instr.ExternalName::new(name)
}

///|
fn rt(name : String) -> @instr.ExternalName {
  external_symbol("wasm.runtime.\{name}")
}

///|
fn rt_gc(name : String) -> @instr.ExternalName {
  external_symbol("wasm.runtime.gc.\{name}")
}

///|
fn rt_exception(name : String) -> @instr.ExternalName {
  external_symbol("wasm.runtime.exception.\{name}")
}

///|
fn rt_memory_grow() -> @instr.ExternalName {
  rt("memory_grow")
}

///|
fn rt_memory_size() -> @instr.ExternalName {
  rt("memory_size")
}

///|
fn rt_memory_fill() -> @instr.ExternalName {
  rt("memory_fill")
}

///|
fn rt_memory_fill_mem0() -> @instr.ExternalName {
  rt("memory_fill_mem0")
}

///|
fn rt_memory_copy() -> @instr.ExternalName {
  rt("memory_copy")
}

///|
fn rt_memory_copy_mem0() -> @instr.ExternalName {
  rt("memory_copy_mem0")
}

///|
fn rt_memory_init() -> @instr.ExternalName {
  rt("memory_init")
}

///|
fn rt_data_drop() -> @instr.ExternalName {
  rt("data_drop")
}

///|
fn rt_table_grow() -> @instr.ExternalName {
  rt("table_grow")
}

///|
fn rt_table_fill() -> @instr.ExternalName {
  rt("table_fill")
}

///|
fn rt_table_copy() -> @instr.ExternalName {
  rt("table_copy")
}

///|
fn rt_table_init() -> @instr.ExternalName {
  rt("table_init")
}

///|
fn rt_elem_drop() -> @instr.ExternalName {
  rt("elem_drop")
}

///|
fn rt_gc_ref_test() -> @instr.ExternalName {
  rt_gc("ref_test")
}

///|
fn rt_gc_ref_cast() -> @instr.ExternalName {
  rt_gc("ref_cast")
}

///|
fn rt_gc_struct_get() -> @instr.ExternalName {
  rt_gc("struct_get")
}

///|
fn rt_gc_struct_set() -> @instr.ExternalName {
  rt_gc("struct_set")
}

///|
fn rt_gc_array_get() -> @instr.ExternalName {
  rt_gc("array_get")
}

///|
fn rt_gc_array_set() -> @instr.ExternalName {
  rt_gc("array_set")
}

///|
fn rt_gc_array_len() -> @instr.ExternalName {
  rt_gc("array_len")
}

///|
fn rt_gc_array_fill() -> @instr.ExternalName {
  rt_gc("array_fill")
}

///|
fn rt_gc_array_copy() -> @instr.ExternalName {
  rt_gc("array_copy")
}

///|
fn rt_gc_array_new_data() -> @instr.ExternalName {
  rt_gc("array_new_data")
}

///|
fn rt_gc_array_new_elem() -> @instr.ExternalName {
  rt_gc("array_new_elem")
}

///|
fn rt_gc_array_init_data() -> @instr.ExternalName {
  rt_gc("array_init_data")
}

///|
fn rt_gc_array_init_elem() -> @instr.ExternalName {
  rt_gc("array_init_elem")
}

///|
fn rt_gc_type_check_subtype() -> @instr.ExternalName {
  rt_gc("type_check_subtype")
}

///|
fn rt_gc_register_struct_inline() -> @instr.ExternalName {
  rt_gc("register_struct_inline")
}

///|
fn rt_gc_register_array_inline() -> @instr.ExternalName {
  rt_gc("register_array_inline")
}

///|
fn rt_gc_alloc_struct_slow() -> @instr.ExternalName {
  rt_gc("alloc_struct_slow")
}

///|
fn rt_gc_alloc_array_from_values_slow() -> @instr.ExternalName {
  rt_gc("alloc_array_from_values_slow")
}

///|
fn rt_gc_alloc_array_slow() -> @instr.ExternalName {
  rt_gc("alloc_array_slow")
}

///|
fn rt_exception_try_begin() -> @instr.ExternalName {
  rt_exception("try_begin")
}

///|
fn rt_exception_try_end() -> @instr.ExternalName {
  rt_exception("try_end")
}

///|
fn rt_exception_throw() -> @instr.ExternalName {
  rt_exception("throw")
}

///|
fn rt_exception_throw_tag() -> @instr.ExternalName {
  rt_exception("throw_tag")
}

///|
fn rt_exception_throw_ref() -> @instr.ExternalName {
  rt_exception("throw_ref")
}

///|
fn rt_exception_delegate() -> @instr.ExternalName {
  rt_exception("delegate")
}

///|
fn rt_exception_get_tag() -> @instr.ExternalName {
  rt_exception("get_tag")
}

///|
fn rt_exception_get_value() -> @instr.ExternalName {
  rt_exception("get_value")
}

///|
fn rt_exception_get_value_count() -> @instr.ExternalName {
  rt_exception("get_value_count")
}

///|
fn rt_exception_sigsetjmp() -> @instr.ExternalName {
  rt_exception("sigsetjmp")
}

///|
fn rt_exception_spill_locals() -> @instr.ExternalName {
  rt_exception("spill_locals")
}

///|
fn rt_exception_get_spilled_local() -> @instr.ExternalName {
  rt_exception("get_spilled_local")
}
