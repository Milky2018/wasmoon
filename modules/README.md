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
| `Milky2018/machv_regalloc` | Target VCode adapter for the reusable register allocator. | `allocate_vcode`, `VCodeAllocationEnvironment`, and structured allocation errors. |
| `Milky2018/x64_target` | x64 instruction selection, ABI, allocation, frame layout, emission, and linking. | `lower`, `allocate`, `plan_frame`, `emit`, and `prepare_x64_link`. |
| `Milky2018/aarch64_target` | AArch64 instruction selection, ABI, allocation, frame layout, emission, and linking. | `lower`, `allocate`, `plan_frame`, `emit`, and `prepare_aarch64_link`. |
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
