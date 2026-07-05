# Reusable Compiler Infrastructure Modules

This workspace splits Wasmoon into reusable compiler infrastructure plus
Wasmoon-specific integration packages. The public package boundary is:

| Package | Role | Stable entry points |
| --- | --- | --- |
| `Milky2018/wasm_core` | Root facade for WebAssembly spec-model construction. | `empty_module`, `simple_module`, `func_type`, `func_subtype`; detailed types remain in `Milky2018/wasm_core/types`. |
| `Milky2018/wasm_core/types` | WebAssembly value, instruction, module, and type-system model. | `ValueType`, `Instruction`, `Module`, `FuncType`, `SubType`, type equality/subtyping helpers. |
| `Milky2018/milkir` | Cranelift-like SSA IR. | `Function`, `IRBuilder`, `Signature`, `Type`, verification, CFG, and optimization passes. |
| `Milky2018/machv` | Virtual-register machine IR. | `Function`, `Block`, `Instruction`, `Opcode`, `Operand`, `PReg`, `VReg`, ABI locations, stack effects, verification, and printing. |
| `Milky2018/regalloc` | Target-independent register allocation algorithm. | `Program`, `Block`, `Instruction`, `MachineEnv`, `allocate`, `verify_allocation`, live-range and move-resolution planning helpers. |
| `Milky2018/machv_regalloc` | Adapter from MachV to the pure register allocator. | `project_function`, `allocate_function`, `allocate_and_apply`. |
| `Milky2018/machv_emit` | Machine-code emission from allocated MachV. | `EmitTarget`, `CodeObject`, `emit_function_for_target`, relocation/fixup and stack-frame helpers. |
| `Milky2018/x64_target` | x64 target lowering and ABI policy. | `target`, `abi_policy`, `build_machine_env`, `lower_function`, `lower_wasm_body_function`. |
| `Milky2018/aarch64_target` | AArch64 target lowering and ABI policy. | `target`, `abi_policy`, `build_machine_env`, `lower_function`, `lower_wasm_body_function`. |
| `Milky2018/wasmoon_jit` | Wasmoon-specific native runtime and JIT integration. | cwasm artifact construction, native runtime wrappers, Wasm entry/hostcall trampolines, VMContext layout, runtime symbols, and integration planning. |

Generic packages (`milkir`, `machv`, `regalloc`, `machv_regalloc`,
`machv_emit`, and ISA target packages) must not import `Milky2018/wasmoon`.
Wasmoon-specific runtime ABI, VMContext layout, helper symbols, WASI bridge
hooks, and native FFI remain in `Milky2018/wasmoon_jit` or
`Milky2018/wasmoon`.

The current public surfaces still include some low-level planning helpers
because they are useful for compiler authors debugging allocation, emission,
and ABI integration. Prefer adding smaller wrappers before removing such
helpers, so downstream users have a migration path.
