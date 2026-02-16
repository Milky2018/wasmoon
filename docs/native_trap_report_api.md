# Native Structured Trap Report API

Wasmoon now exposes a structured trap report for JIT execution:

- Package: `Milky2018/wasmoon/jit`
- API: `JITModule::get_last_trap_report() -> TrapReport?`

## Behavior

- `JITModule::call_with_context(...)` still raises `JITTrap(String)` with enriched text for backward compatibility.
- On trap, Wasmoon also stores a machine-readable `TrapReport` in the `JITModule`.
- On a successful call, the previous trap report is cleared.

## `TrapReport` fields

- `trap_kind`, `message`
- Native context: `signal`, `signal_name`, `pc`, `lr`, `fp`, `frame_lr`, `fault_addr`, `brk_imm`
- Resolved wasm location: `wasm_func_idx`, `wasm_func_name`, `wasm_offset`
- Caller chain: `wasm_frames : Array[WasmTrapFrame]`
- Optional host frame bucket: `host_frames` (reserved for future expansion)
- Optional dump path when dump-on-trap is enabled: `dump_path`

`WasmTrapFrame` includes:
- `pc`
- `func_idx`
- `func_name`
- `wasm_offset`
