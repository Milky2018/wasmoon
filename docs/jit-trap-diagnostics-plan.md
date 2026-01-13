# JIT Trap Diagnostics (Unknown Trap) — Implementation Plan

## Background / Problem

Today `JIT Trap: unknown trap` is raised when the JIT runtime (C signal handlers) cannot classify the failure as a known WebAssembly trap (OOB, unreachable, div-by-zero, etc.). In practice this often means:

- a SIGSEGV/SIGBUS that is not recognized as a guard-page access (WASM memory/stack), or
- a SIGTRAP/BRK whose immediate is not mapped to a known trap code, or
- a failure happening in a trampoline/import/libcall where we lose context of “which wasm function was running”.

This makes miscompiles hard to debug because we lack actionable context (PC, fault address, function index/name).

## Goals

Implement the following diagnostics end-to-end:

1. **Trap detail reporting**: include signal kind, PC, fault address, and (for BRK) the decoded `brk_imm` in the raised error.
2. **PC → function mapping**: map the trap PC back to the wasm function index/name and compute the offset within the compiled machine code.
3. **Dump-on-trap**: on failure only, dump the *single* relevant function’s IR/VCode/regalloc/machine-code annotations (instead of printing everything).
4. **Current function tracking**: record the currently executing wasm function index inside `jit_context_t`, updated by JIT prologue code, so traps inside helpers/trampolines can still report “who was running”.

## Non-goals

- A full AArch64 disassembler for arbitrary machine code bytes.
- Guaranteeing stable PC addresses across OS versions/builds (PC values are for debugging only).
- Changing the `.cwasm` on-disk format to embed debug metadata.

## Design Overview

### A. C-side trap state (source of truth)

Extend the existing global trap state in `jit/jit_ffi/trap.c` to record:

- `trap_signal` (SIGTRAP / SIGSEGV / SIGBUS)
- `trap_pc` (faulting instruction address)
- `trap_fault_addr` (SIGSEGV/SIGBUS `si_addr`)
- `trap_brk_imm` (SIGTRAP decoded immediate; `-1` when not applicable)
- `trap_func_idx` (best-effort: copy from `ctx->debug_current_func_idx` when available)

Reset these fields at the start of each JIT call (in `wasmoon_jit_call_trampoline` and stack-switching variant).

Expose getters via MOONBIT_FFI_EXPORT in `jit/jit_ffi/jit.c`, and declare them in `jit/jit_ffi/ffi.mbt`.

### B. Current function index tracking (jit_context_t + prologue instrumentation)

1. Add `int32_t debug_current_func_idx;` into `jit_context_t` *without changing any existing VMContext offsets used by JIT code*.
   - Place it in the existing padding immediately after `memory_count` to keep all documented offsets stable.
2. Add a new VMContext offset constant in `vcode/abi/abi.mbt`, e.g. `VMCTX_DEBUG_CURRENT_FUNC_IDX_OFFSET`.
3. Modify code emission so that each compiled wasm function’s prologue writes its `func_idx` to:
   - `[vmctx + VMCTX_DEBUG_CURRENT_FUNC_IDX_OFFSET]` (32-bit store).
4. Ensure this instrumentation is only emitted for “real wasm functions” (not entry trampolines), by threading `func_idx` into `emit_function`.

### C. MoonBit-side enrichment and dump-on-trap

1. Keep the low-level trap raising in `jit/ffi_jit.mbt` minimal.
2. In `jit/jit_runtime.mbt`, catch `JITTrap` at the `JITModule` boundary (where we have module metadata) and re-raise an enriched message that includes:
   - trap code string
   - signal + PC + fault address + brk_imm
   - mapped wasm function (idx/name) and offset when possible
3. Maintain an **optional** in-memory debug database (per function) that holds strings:
   - IR dump
   - VCode before regalloc
   - VCode after regalloc
   - MachineCode dump (`MachineCode::dump_disasm()`)
4. When `dump-on-trap` is enabled and we identify the function, write these strings to a single log file (e.g. `target/jit-trap-<func_idx>-<name>.log`) and include that path in the raised error.

### D. CLI wiring

Add a user-facing switch for “dump-on-trap” without changing the existing `-D` debug flag behavior:

- `wasmoon run --dump-on-trap <module>`
  - Enables capturing per-function debug strings during compilation and attaching them to the `JITModule`.
  - On trap, writes one file for the failing function and prints a concise summary.

Optionally also enable “always include trap detail fields” (1 & 2) by default in the raised error (small and high-value).

## Implementation Steps (Concrete)

1. **Docs first**
   - Land this plan document.

2. **C: trap detail capture**
   - `jit/jit_ffi/trap.c`: add globals for `trap_signal/trap_pc/trap_fault_addr/trap_brk_imm/trap_func_idx`, set them in handlers, reset per call.
   - `jit/jit_ffi/jit_internal.h`: declare the globals.

3. **C: FFI exports**
   - `jit/jit_ffi/jit.c`: export getters for the new trap detail fields.
   - `jit/jit_ffi/ffi.mbt`: declare externs.

4. **C: current func idx in context**
   - `jit/jit_ffi/jit_ffi.h`: add `debug_current_func_idx` in padding after `memory_count`.
   - Initialize it in context allocation (`jit/jit_ffi/jit_context.c`).

5. **MoonBit: ABI constant + prologue store**
   - `vcode/abi/abi.mbt`: add `VMCTX_DEBUG_CURRENT_FUNC_IDX_OFFSET`.
   - `vcode/emit/codegen.mbt`: thread `func_idx` into `emit_function` and `emit_prologue`, emit `str w16, [x0/x19, #offset]` at function entry.

6. **MoonBit: PC→function mapping**
   - `jit/jit_runtime.mbt`: extend `JITFunction` to store `code_size` and provide helper lookup by PC range.

7. **MoonBit: dump-on-trap**
   - Introduce a `JITDebugDB` (Map[func_idx] → debug strings).
   - `cli/main/run.mbt`: when `--dump-on-trap` is set, capture per-function IR/VCode/regalloc/MC dumps during compilation into `JITDebugDB`.
   - Attach DB to `JITModule` (new setter or constructor variant).
   - On trap, write a single log file for the identified function.

8. **CLI flags**
   - `cli/main/main.mbt`: add `--dump-on-trap` to `run`.
   - `cli/main/run.mbt`: plumb to compilation/JIT setup.

9. **Validation**
   - Build + run the existing failing reproducer (`examples/aead_aegis128l.wasm`) and verify:
     - error message includes signal/PC/fault address (even for unknown trap)
     - wasm function index/name is reported when possible
     - with `--dump-on-trap`, a single log file is created and referenced

10. **STATUS.md update**
   - Record what fields are now printed and how to use the new flag.

## Acceptance Criteria

- `JIT Trap: unknown trap` becomes actionable:
  - includes `sig`, `pc`, `addr` (if applicable), and `brk_imm` (if applicable)
  - includes wasm `func_idx`/name when determinable (via PC range or `debug_current_func_idx`)
- `wasmoon run --dump-on-trap ...` produces exactly one per-trap dump file for the relevant function.
- No change to `.cwasm` file format or serializer.

