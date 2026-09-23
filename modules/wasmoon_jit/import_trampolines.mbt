/// Built-in import trampolines supported by the native JIT.

///|
/// Trampoline registry - maps (module, field) to function pointer getter.
let import_trampolines : Map[String, Map[String, () -> Int64]] = {
  let m : Map[String, Map[String, () -> Int64]] = Map([])
  m["spectest"] = {
    "print": get_spectest_print_ptr,
    "print_i32": get_spectest_print_i32_ptr,
    "print_i64": get_spectest_print_i64_ptr,
    "print_f32": get_spectest_print_f32_ptr,
    "print_f64": get_spectest_print_f64_ptr,
    "print_i32_f32": get_spectest_print_i32_f32_ptr,
    "print_f64_f64": get_spectest_print_f64_f64_ptr,
    "print_char": get_spectest_print_char_ptr,
  }
  m
}

///|
/// Get trampoline function pointer for an import.
/// Returns None if the import is not supported by JIT.
pub fn get_import_trampoline(
  module_name : String,
  field_name : String,
) -> Int64? {
  // All platforms share the portable WASI host implementation across engines.
  // Returning None selects the existing hostcall bridge, not interpretation.
  if module_name == "wasi_snapshot_preview1" {
    return None
  }
  import_trampolines
  .get(module_name)
  .bind(fn(m) { m.get(field_name) })
  .map(fn(f) { f() })
}

///|
pub fn resolve_import_function_ptr(
  external_imports : Map[String, Map[String, Int64]],
  module_name : String,
  field_name : String,
) -> Int64? {
  match external_imports.get(module_name) {
    Some(module_imports) =>
      match module_imports.get(field_name) {
        Some(ptr) => Some(ptr)
        None => get_import_trampoline(module_name, field_name)
      }
    None => get_import_trampoline(module_name, field_name)
  }
}

///|
pub(all) enum ImportFunctionResolution {
  DirectImportFunction(Int64)
  HostImportFunctionAddr(Int)
  UnsupportedImportFunction
} derive(Eq, Debug)

///|
pub fn classify_import_function_ptr(ptr : Int64) -> ImportFunctionResolution {
  if ptr < 0L {
    HostImportFunctionAddr((-(ptr + 1L)).to_int())
  } else {
    DirectImportFunction(ptr)
  }
}

///|
pub fn resolve_import_function(
  external_imports : Map[String, Map[String, Int64]],
  module_name : String,
  field_name : String,
) -> ImportFunctionResolution {
  match resolve_import_function_ptr(external_imports, module_name, field_name) {
    Some(ptr) => classify_import_function_ptr(ptr)
    None => UnsupportedImportFunction
  }
}

///|
/// Check if a module is known to JIT (has trampoline support).
pub fn is_jit_supported_module(module_name : String) -> Bool {
  import_trampolines.contains(module_name)
}
