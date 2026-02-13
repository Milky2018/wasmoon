# `wasmoon-puv.3` Summary

## Goal

Align Wasmoon backtracking-regalloc conflict probing with Cranelift/regalloc2's
ordered interval traversal, replacing bundle-pair overlap probing.

## Cranelift Sources Read Before Implementation

- `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/regalloc2-0.13.5/src/ion/process.rs`
- `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/regalloc2-0.13.5/src/ion/merge.rs`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/machinst/compile.rs`

## What Changed

- Replaced conflict detection path in
  `/Users/zhengyu/Documents/projects/wasmoon/vcode/regalloc/backtrack.mbt`:
  - removed bundle-index + bundle-overlap-cache probing path.
  - switched to ordered span traversal per preg occupancy (`two-pointer` scan).
  - aligned first-conflict-point detection to the same ordered traversal.
  - kept preg occupancy sorted by `span.start` during insertion.
- Reverted uncommitted experimental call-crossing-cache changes in
  `/Users/zhengyu/Documents/projects/wasmoon/vcode/regalloc/bundle.mbt`.

## Correctness Gates

All passed on this workspace after changes:

1. `moon info`
2. `moon fmt`
3. `moon test --target native` (1689/1689)
4. `./install.sh`
5. `python3 scripts/run_all_wast.py --dir spec --rec` (258/258 interpreter, 258/258 jit)

## Perf Snapshot

From `wasmtime-parity-summary.md` / `.json` in this directory:

- `examples/aead_aegis128l.wasm`
  - Wasmoon median: `1.6285s`
  - Wasmtime median: `0.7884s`
  - Ratio: `2.0656x`
- `examples/benchmark.wasm`
  - Wasmoon median: `0.2621s`
  - Wasmtime median: `0.3209s`
  - Ratio: `0.8167x`

## Notes

- This task improved the hot regalloc path while preserving full correctness,
  but AEAD parity is still not within the final target (<1.10x vs Wasmtime).
- Follow-up work remains required in lowering/codegen quality paths.
