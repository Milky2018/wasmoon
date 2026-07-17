# Compiler Modules

The `modules` workspace contains the compiler pipeline, target backends, and
Wasmoon runtime integration packages. The main public packages are:

| Package | Role | Stable entry points |
| --- | --- | --- |
| `Milky2018/wasm_core` | Root facade for WebAssembly spec-model construction. | `empty_module`, `simple_module`, `func_type`, `func_subtype`; detailed types remain in `Milky2018/wasm_core/types`. |
| `Milky2018/wasm_core/types` | WebAssembly value, instruction, module, and type-system model. | `ValueType`, `Instruction`, `Module`, `FuncType`, `SubType`, type equality/subtyping helpers. |
| `Milky2018/milkir` | Cranelift-like SSA IR. | `Function`, `FunctionBuilder`, `Signature`, `Type`, verification, CFG, and optimization passes. |
| `Milky2018/machv` | Target-neutral semantic machine IR. | `Function`, `FunctionBuilder`, typed values, blocks, semantic operations, calls, traps, effects, verification, and printing. |
| `Milky2018/milkir_machv` | Verified MilkIR-to-semantic-MachV producer. | `lower_core_function`, `lower_core_function_with_protocol`, and explicit dialect-adapter entry points. |
| `Milky2018/wasm_machv` | WebAssembly dialect adapter for semantic MachV. | `Environment`, `lower_function`, and typed runtime-capability seams. |
| `Milky2018/regalloc` | Target-independent register allocation algorithm. | `Program`, `Block`, `Instruction`, linear-scan/backtracking allocation, `verify_allocation`, live-range and move-resolution planning helpers. |
| `Milky2018/machv_regalloc` | Allocation adapter for the current private native backend. | `allocate_registers_backtracking_with_isa`, `allocate_registers_backtracking_output_with_isa`, `Output`, `Loc`, and allocation application helpers. |
| `Milky2018/machv_emit` | Machine-code emission from the allocated private native backend. | `MachineCode`, `emit_function`, `emit_function_with_regalloc`, relocation/fixup and stack-frame helpers. |
| `Milky2018/x64_target` | x64 ABI and register policy. | `target`, `abi_policy`, `build_machine_env`, and register-set helpers. |
| `Milky2018/aarch64_target` | AArch64 ABI and register policy. | `target`, `abi_policy`, `build_machine_env`, and register-set helpers. |
| `Milky2018/wasmoon_jit` | Native runtime and JIT integration for Wasmoon. | `plan_milkir_integration_for_target`, cwasm artifact construction, native runtime wrappers, Wasm entry/hostcall trampolines, VMContext layout, runtime symbols, and integration planning. |

## Tested READMEs

Each publishable module README is written as `README.mbt.md` with executable
`moonbit check` examples. Run them before publishing documentation changes:

```bash
for d in modules/*; do
  if [ -f "$d/README.mbt.md" ]; then
    moon -C "$d" test README.mbt.md --target native --warn-list +73 --diagnostic-limit=200
  fi
done
```

Use these examples as user-facing smoke tests. They should demonstrate normal
end-to-end workflows such as building MilkIR, lowering to MachV, allocating
registers, producing machine-code metadata, planning Wasmoon JIT integration,
and executing Wasm through the library API.
