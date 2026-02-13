# Native Strict Import Diagnostics API

Wasmoon now provides structured import diagnostics in the `executor` package:

- `validate_imports_with_diagnostics(store, module, imports) -> ImportDiagnosticsResult`
- `instantiate_module_with_import_diagnostics(store, module, imports) -> InstantiateWithImportDiagnosticsResult`

## Diagnostic model

`ImportDiagnosticsResult` contains:

- `ok : Bool`
- `diagnostics : Array[ImportDiagnostic]`

`ImportDiagnostic` fields:

- `import_index`
- `module_name`
- `name`
- `kind` (`MissingImport`, `ImportKindMismatch`, `ImportTypeMismatch`)
- `expected`
- `actual`
- `message`

## Strict instantiate behavior

`instantiate_module_with_import_diagnostics` is non-throwing and returns:

- `Ok(instance)` when import checks and instantiation succeed.
- `ImportError(diagnostics)` when imports are missing/mismatched.
- `RuntimeFailure(runtime_error)` when imports pass but instantiation/start fails at runtime.

## Compatibility

Legacy `instantiate_module_with_imports(...)` is unchanged and keeps raising `RuntimeError`.
