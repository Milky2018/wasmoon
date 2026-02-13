# wasmoon-puv.4 branch-threading baseline

## Context
- Branch: `milky/optimization-jit-closure`
- Task: `wasmoon-puv.4`
- Change: layout-level trivial jump threading (Cranelift MachBuffer-style branch threading alignment)
- Cranelift references:
  - `cranelift/codegen/src/machinst/buffer.rs` (branch simplification/threading)
  - `cranelift/codegen/src/machinst/blockorder.rs` (block order context)

## Validation gates
- `moon info`: pass
- `moon fmt`: pass
- `moon test --target native`: pass (1691/1691)
- `./install.sh`: pass
- `python3 scripts/run_all_wast.py --dir spec --rec`: pass
  - Interpreter: 258/258 files
  - JIT: 258/258 files

## Performance (5-run median)
Commands:
- `./wasmoon run examples/aead_aegis128l.wasm`
- `wasmtime run examples/aead_aegis128l.wasm`
- `./wasmoon run examples/benchmark.wasm`
- `wasmtime run examples/benchmark.wasm`

Results:
- AEAD wall-time
  - Wasmoon: `1.67s`
  - Wasmtime: `0.74s`
  - Ratio: `2.26x`
- AEAD program output (sample)
  - Wasmoon: `4059720000`
  - Wasmtime: `3698930000`
  - Ratio: `1.097x` (within 10%)
- benchmark.wasm wall-time
  - Wasmoon: `0.24s`
  - Wasmtime: `0.27s`
  - Ratio: `0.89x`

## Notes
- Instruction count for hot `func_56` remains near Wasmtime scale; this change mainly removes redundant branch-to-branch chains and simplifies terminators.
- The primary remaining wall-time gap for AEAD appears compile-pipeline dominated rather than steady-state wasm instruction quality.
