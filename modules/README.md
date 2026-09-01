# Compiler Modules

The `modules` workspace contains the compiler pipeline, target backends, and
Wasmoon runtime integration packages. The main public packages are:

| Package | Role | Stable entry points |
| --- | --- | --- |
| `Milky2018/wasm_core` | Root facade for WebAssembly spec-model construction. | `empty_module`, `simple_module`, `func_type`, `func_subtype`; detailed types remain in `Milky2018/wasm_core/types`. |
| `Milky2018/wasm_core/types` | WebAssembly value, instruction, module, and type-system model. | `ValueType`, `Instruction`, `Module`, `FuncType`, `SubType`, type equality/subtyping helpers. |
| `Milky2018/wasm_core/validator` | Target-portable core WebAssembly validation. | `validate_module`, `validate_module_with_context`, structured validation errors, and diagnostic formatting. |
| `Milky2018/wasm_core/wat` | Target-portable WAT/WAST parsing and canonical WAT rendering. | `parse`, `parse_wast`, `render`, `render_function`, and structured text errors. |
| `Milky2018/wasm_component` | Portable Component Model types, binary decoding, and canonical ABI modeling. | `parse_component`, component section types, and canonical ABI helpers. |
| `Milky2018/wasm_component/validator` | Target-portable Component Model validation. | `validate_component`, instantiation validation evidence, configuration, and diagnostics. |
| `Milky2018/wasm_component/text` | Component Model text parsing and encoding. | `parse_component_wat` and structured text errors. |
| `Milky2018/wasm_component/wit` | Portable WIT parsing, resolution, formatting, and component encoding. | `parse_package`, `resolve_package`, `format_package`, and WIT component codecs. |
| `Milky2018/milkir` | Cranelift-like SSA IR. | `Function`, `FunctionBuilder`, `Signature`, `Type`, verification, CFG, and optimization passes. |
| `Milky2018/vcode/native_types` | Target-independent native ABI and metadata vocabulary. | `ValueType`, `Signature`, calls, symbols, traps, safepoints, and source locations. |
| `Milky2018/vcode/native_lowering` | Streaming target-lowering protocol with no retained program graph. | `TargetSink`, `DirectBuilder`, target-neutral operations, call ABI elaboration, and structured errors. |
| `Milky2018/milkir/native` | Direct MilkIR-to-native-target producer. | `lower_core_to_sink`, `function_signature`, and explicit dialect-adapter entry points. |
| `Milky2018/wasm_milkir/native` | WebAssembly MilkIR dialect adapter for native targets. | `Environment`, `lower_to_sink`, and typed runtime-capability seams. |
| `Milky2018/wasm_milkir/frontend` | Target-portable Wasm-to-MilkIR translation. | `EmbeddingEnvironment`, `translate_function`, translation contexts, and validation contexts. |
| `Milky2018/vcode` | Generic dense target VCode and allocation-side-table infrastructure. | `Builder`, `Function`, allocation verification, parallel-move resolution, and compile events. |
| `Milky2018/vcode/code_object` | Verified unlinked native code and metadata. | `build`, typed relocations, traps, safepoints, roots, and unwind directives. |
| `Milky2018/regalloc` | Target-independent register allocation algorithm. | Read-only `FunctionView`, `MachineEnv`, `RegallocConfig`, and verified `AllocationPlan`. |
| `Milky2018/vcode_regalloc` | Direct Target VCode adapter for the reusable register allocator. | `allocate_vcode`, `VCodeAllocationEnvironment`, verified allocation materialization, and structured allocation errors. |
| `Milky2018/x64_target` | x64 streaming instruction selection, ABI, allocation, frame layout, emission, and linking. | `DirectLoweringSession`, `compile_selected`, `allocate`, `plan_frame`, `emit`, and `prepare_x64_link`. |
| `Milky2018/aarch64_target` | AArch64 streaming instruction selection, ABI, allocation, frame layout, emission, and linking. | `DirectLoweringSession`, `compile_selected`, `allocate`, `plan_frame`, `emit`, and `prepare_aarch64_link`. |
| `Milky2018/wasmoon_jit` | Native runtime and JIT integration for Wasmoon. | Artifact production, bounded loading, transactional installation, Wasm entry/hostcall trampolines, VMContext layout, runtime symbols, and integration planning. |
| `Milky2018/wasmoon/component` | Stable Component Model runtime facade. | `ComponentRuntime`, opaque instances/functions, WIT-shaped `ComponentValue`, typed JSON codecs, checked export binding and invocation. |
| `Milky2018/wasmoon/wit_binding` | Runtime adapter from resolved WIT worlds to component instances. | `bind_world` and checked `WitBindings`. |

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
end-to-end workflows such as building MilkIR, lowering directly to target VCode, allocating
registers, producing machine-code metadata, planning Wasmoon JIT integration,
and executing Wasm through the library API.
