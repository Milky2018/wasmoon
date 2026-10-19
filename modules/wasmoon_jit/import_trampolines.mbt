/// Import resolution for the native JIT.

///|
/// Builtins use linked host functions and the typed hostcall bridge. No raw
/// native fallback is provided; callers without a Store must supply imports.
pub fn get_import_trampoline(
  _module_name : String,
  _field_name : String,
) -> Int64? {
  None
}

///|
pub fn resolve_import_function_ptr(
  external_imports : Map[String, Map[String, Int64]],
  module_name : String,
  field_name : String,
) -> Int64? {
  external_imports
  .get(module_name)
  .bind(module_imports => module_imports.get(field_name))
}

///|
pub(all) enum ImportFunctionResolution {
  DirectImportFunction(Int64)
  HostImportFunctionAddr(Int32)
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
/// Recognize the standard spectest resources shared with the interpreter.
pub fn is_jit_supported_module(module_name : String) -> Bool {
  module_name == "spectest"
}
