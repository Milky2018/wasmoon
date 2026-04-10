# Component Model Examples

This directory contains focused component-model `.wast` examples for validating
Wasmoon behavior.

## Run All Examples

```bash
python3 scripts/run_component_wast.py --dir examples/component-model --rec
```

## Example List

1. `01-hello-component.wast`
   - String parameter/return through canonical lift/lower.
2. `02-abi-types-matrix.wast`
   - Type declarations for record/variant/flags/enum/option/result/list/tuple.
3. `03-resource-lifecycle.wast`
   - Resource create/rep/drop and invalid-handle trap behavior.
4. `04-cross-component-compose.wast`
   - Composition of nested components and instance wiring.
5. `05-error-and-trap-boundary.wast`
   - Recoverable code-path return vs hard trap path.
6. `06-async-future-stream-smoke.wast`
   - Async future read plus stream create/drop smoke coverage.
7. `07-wasi-cli-status.wast`
   - Current root-level WASI CLI import status (expected invalid for now).
8. `08-large-payload-stress.wast`
   - 512-byte string lowering stress check.

## Optional Cross-Check With Wasmtime

```bash
wasmtime wast examples/component-model/01-hello-component.wast
```
