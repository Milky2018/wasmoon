# JIT ↔ Interpreter Shared Memory/Table (Route B) — TODO

This document tracks the work to make JIT and interpreter share the same underlying `memory`/`table` backing safely across module import/export, with a forward-compatible path for `threads`/`shared memory`.

## Problem Statement
Today, JIT is conservatively disabled for modules that *export* `memory`/`table` (`exports_shared_resources`) because cross-module sharing can lead to state divergence (stale pointers/lengths, unsynced grow, or duplicated backings). This blocks JIT for single-module programs that happen to export memory/table (e.g. `examples/benchmark.wat`).

## Non‑Negotiable Invariants
- **Single source of truth**: each Store memory/table has exactly one authoritative “descriptor” used by both interpreter and JIT.
- **No stale pointers**: JIT must never dereference a pointer that could have been invalidated by `grow`/realloc.
- **Immediate visibility**: after `memory.grow`/`table.grow`, subsequent loads/stores/gets/sets in either mode must observe the updated backing + bounds.
- **No silent wrong results**: on any guard failure, execution must take a safe slowpath or trap/deopt, never proceed with stale metadata.
- **Threads-ready**: design keeps room for atomicity and shared-memory semantics (even if initially unimplemented).

## Scope (Phase 1: Memory)
- Implement shared memory descriptor (stable address) and route all JIT memory accesses through it.
- Ensure cross-module import/export shares the same descriptor pointer.
- Ensure `memory.grow`, bulk ops, and bounds checks update/consult the descriptor.

## Out of Scope (Phase 1)
- Full table sharing (Phase 2)
- Full threads + shared memory runtime semantics (Phase 3)

## Design Sketch (Route B)
### `MemDesc` (stable pointer)
Fields (exact layout TBD; must be C-ABI stable if read by JIT C/FFI):
- `base_ptr: *mut u8` (may change on grow)
- `byte_len: u64` (current accessible bytes)
- `max_byte_len: u64` (or max pages)
- `is_memory64: bool`
- `page_size_log2: u32`
- `version: u64` (increment on grow / realloc / key property change)
- `shared: bool` (future)

### JIT access pattern
- **Baseline**: each memory op loads `base_ptr` + `byte_len` from `MemDesc` and performs bounds check.
- **Optional caching**: if caching metadata in registers, must guard on `version` (or reload after any instruction that can grow).

### `memory.grow`
- Must update the shared descriptor and bump `version`.
- Interpreter and JIT must both call the same implementation path.

## Milestones

### M1 — Audit current state (owner: TBD)
- [x] Locate current JIT memory metadata layout and how loads/stores compute address.
- [x] Locate all paths that modify memory backing/size: `memory.grow`, bulk ops, init, etc.
- [x] Identify cross-module linking points where memory is shared.

### M2 — Implement `MemDesc` plumbing
- [x] Introduce C-side `wasmoon_memory_t` (base + atomic length).
- [x] Store allocates `MemDesc` per memory.
- [x] Instances reference `MemDesc*` for each memory index.
- [x] Imported memories share the same `MemDesc*`.

### M3 — JIT uses `MemDesc` for bounds+base
- [x] Update lowering/codegen to consult descriptor for every memory op (at least for correctness).
- [x] Add/keep a safe slowpath (helper call) if needed for tricky cases.

### M4 — Tests + regression
- [x] Update `testsuite/` to pass memory descriptors into JIT (no legacy `set_memory(ptr, size)`).
- [x] Add a two-module test: module A exports memory, module B imports it.
  - [x] A writes, B reads; B grows, A reads/writes again.
  - [x] Verify interpreter-only, JIT-only, and mixed execution results match.
- [x] Fix flaky `testsuite` SIGSEGV by making JIT trap handling thread-safe.
- [x] Extend smith-diff harness to allow multi-module runs (if not already supported).

### M5 — Remove/relax `exports_shared_resources` gate
- [x] Once cross-module sharing is correct, remove memory-related gating.
- [ ] Keep table gating until Phase 2.

## Phase 2 (Table)
- [ ] Create `TableDesc` with stable pointer + `version`.
- [ ] Unify element encoding between interpreter and JIT.
- [ ] Handle `table.grow`, `table.copy`, `call_indirect` coherently.

## Phase 3 (Threads/shared)
- [ ] Define atomicity requirements on `MemDesc` fields (e.g. atomic loads of `base_ptr`/`byte_len` or versioned reads).
- [ ] Implement shared-memory semantics and ensure JIT uses correct atomic instructions.

## Acceptance Criteria (Phase 1)
- Running a module that exports memory no longer disables JIT solely due to export.
- Cross-module import/export of memory is correct under:
  - loads/stores
  - `memory.grow`
  - `memory.size`
  - bulk operations already supported
- No new failures in `testsuite/` and no new failures in smith-diff baseline runs.

## Notes / Links
- `docs/jit-abi.md`
- `docs/jit-trap-diagnostics-plan.md`
- `wast/jit_support.mbt` (current gating rules)
