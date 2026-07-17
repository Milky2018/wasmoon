# MachV Migration Inventory

This document records the repository state that constrained the planned move from the union-style MachV pipeline to target-neutral MachV followed by target-specific VCode. It is a fact-finding artifact for [Inventory current MachV coupling and migration hazards](../issues/ISS-184.md), not an implementation plan. The inventory was taken on 2026-07-15 from branch `milky/improve-machv` after commit `9653a834`.

Status update: ISS-196 subsequently introduced verified target-neutral producers, cut production over through a product-private transition adapter, and deleted the former target-aware MilkIR and Wasm direct-lowering packages. Sections that describe those deleted packages are retained as historical coupling evidence rather than current API guidance.

## Executive finding

The current `@machv.Function` is not one compiler-stage representation. It simultaneously carries target-neutral values and control flow, target instruction selection, physical-register and ABI constraints, stack-frame inputs, and two different forms of post-register-allocation state. AArch64 and AMD64 emission then dispatch from the same opcode union.

The repository already places executable-memory allocation, runtime-symbol resolution, VMContext layout, Cwasm persistence, and final fixup installation in Wasmoon-owned packages. That product boundary should be preserved. The main migration risk is therefore not product code leaking upward; it is separating several compiler stages that currently share the same public data types and mutable block/instruction arrays.

## Current pipeline and package graph

The production CLI path is:

```text
Wasm frontend / MilkIR
  -> milkir_machv + wasm_machv
  -> verified target-neutral semantic MachV
  -> Wasmoon-private transition adapter
  -> legacy backend Function containing target-shaped Opcode and ABI state
  -> machv_regalloc returning both a rewritten MachV Function and Output side tables
  -> machv_emit(ISA, EmbeddingABI)
  -> MachineCode bytes, fixups, safepoints and disassembly
  -> wasmoon_jit CompiledFunction / Cwasm
  -> executable memory, symbol patching and runtime installation
```

The direct production sequence appears in [`run.mbt`](../modules/wasmoon/cmd/wasmoon/commands/run.mbt): target-aware lowering at lines 1666-1678, register allocation at lines 1710-1714, emission at lines 1754-1761, and Cwasm conversion at lines 1784-1804. [`native_glue.mbt`](../modules/wasmoon_jit/native_glue.mbt) exposes the same reusable-looking sequence at lines 118-241.

All packages that define or directly import the current MachV pipeline are grouped below. Transitive consumers are not repeated.

| Role | Direct packages | Current dependency |
|---|---|---|
| MachV data model | `machv`, `machv/block`, `machv/instr`, `machv/abi`, `machv/isa`, `machv/isa/spec`, `machv/isa/aarch64`, `machv/isa/amd64` | One function representation depends on the shared opcode union, physical registers, ABI records, and a closed ISA enum. |
| Semantic producers | `milkir_machv`, `wasm_machv` | MilkIR and Wasm dialect lowering produce verified target-neutral MachV without ISA or concrete embedding layout input. |
| Target facades | `aarch64_target`, `x64_target` | Own ABI and register policy; neither owns an independent VCode type yet. |
| Register allocation and layout | `machv_regalloc`, `machv_regalloc/layout` | Read and rewrite MachV instructions, introduce physical registers and spill operations, and reorder the same MachV blocks. |
| Emission | `machv_emit`, `machv_emit/isaregs` | Dispatch the same opcode union to AArch64 or AMD64 encoders and consume both MachV function metadata and regalloc side tables. |
| Product orchestration | `wasmoon_jit`, `wasmoon`, `wasmoon/jit`, `wasmoon/preflight`, `wasmoon/cmd/wasmoon/commands` | Select the target, provide Wasmoon ABI/runtime data, persist Cwasm, allocate executable memory, patch symbols, and install code. |

The package-level hard dependency direction remains clean: reusable compiler packages do not import Wasmoon product packages. Wasmoon-specific data is passed down through generic-looking ABI and callback records instead.

## Stage data classified by future owner

| Current data or behavior | Current location | Future owner required by the standing architecture decisions |
|---|---|---|
| Typed SSA values, semantic operations, rooted CFG, block parameters, uniform argument-carrying edges, semantic calls, structured traps and canonical effect/trap summaries | `machv.Function`, `Block`, `Inst`, `Opcode`, `Terminator` | Target-neutral MachV core. |
| AArch64 shifted/extended forms, `ExtrImm`, multiply-accumulate/high forms, AArch64 conditions and addressing modes | Shared [`Opcode`](../modules/machv/instr/instr.mbt), especially lines 195-446 | AArch64 VCode instruction type and AArch64 lowering/legalization. |
| AMD64 parity conditions, x86 addressing/encoding choices and target-only legality | Shared `Cond`/`Opcode`, ISA checks in verifier and emitter | AMD64 VCode instruction type and AMD64 lowering/legalization. |
| `RegClass`, `PReg`, `Reg::Physical`, fixed operand constraints, machine environments and allocatable/callee-saved sets | [`machv/abi`](../modules/machv/abi) and [`machv/isa`](../modules/machv/isa) | Generic Target VCode/regalloc shell plus target-owned register universe and machine environment. None belongs in target-neutral MachV. |
| Call argument/result placement, clobber sets, outgoing stack area, incoming stack parameters, return-area pointer, prologue/epilogue requirements and frame layout | legacy backend ABI adaptation, call opcodes, legacy backend Function, [`stackframe.mbt`](../modules/machv_emit/stackframe.mbt) | Native ABI lowering and target frame lowering. Semantic MachV retains only call signatures, protocol, behavior, effects, and roots. |
| Spill/reload/move instructions, assigned physical registers, edge-copy edits and spill-slot counts | Rewritten MachV plus [`machv_regalloc.Output`](../modules/machv_regalloc/output.mbt) | One allocated Target VCode state with stable instruction/program-point identity. It must not create a second post-regalloc MachV dialect. |
| Block order, fallthrough selection, branch threading, synthetic exit labels and target peepholes | `machv_regalloc/layout`, `machv_emit` and target-aware MilkIR peepholes | Target VCode layout, branch relaxation and target emitter passes. |
| Machine bytes, target branch fixups, constant pools, generic code-symbol/external-symbol relocations, stack maps and disassembly | [`machv_emit.MachineCode`](../modules/machv_emit/machinecode.mbt) | Target emitter output. Generic relocation and stack-map records may remain reusable. |
| Wasmoon register-role choices, concrete VMContext offsets, context cache slots, trap payload policy and runtime helper names | [`embedding_roles.mbt`](../modules/wasmoon_jit/embedding_roles.mbt), [`vmcontext_abi.mbt`](../modules/wasmoon_jit/vmcontext_abi.mbt), runtime-symbol adapters | Wasmoon JIT. It supplies target/ABI lowering inputs but those facts do not become MachV core data. |
| Cwasm encoding, executable-memory ownership, runtime address resolution, fixup installation, GC table installation and code registration | `wasmoon_jit/cwasm`, `wasmoon_jit`, `wasmoon/jit` | Wasmoon JIT and runtime. Persist emitted code plus product-owned metadata, not MachV or Target VCode. |

## Coupling evidence

### One opcode union represents mutually illegal target programs

[`instr.mbt`](../modules/machv/instr/instr.mbt) calls the enum a target-independent subset at line 195, but the same enum contains AArch64-specific instructions beginning at line 352, post-regalloc stack operations beginning at line 401, ABI-lowered call forms beginning at line 458, and AArch64 NEON-shaped SIMD forms beginning at line 498. Because `Opcode`, `Cond`, registers, and constraints are shared, invalid combinations such as AMD64-only conditions in AArch64 functions are representable and rejected only by later ISA-aware checks or abort paths.

[`machv/isa/isa.mbt`](../modules/machv/isa/isa.mbt) embeds a closed `AArch64 | AMD64` target enum and physical-register policy in the MachV package. [`machv/isa/amd64/roles.mbt`](../modules/machv/isa/amd64/roles.mbt) maps the nonexistent AMD64 link-register role to `rbp`, demonstrating that a shared role interface currently requires a fabricated target fact.

### MachV Function crosses semantic, ABI, and allocation stages

[`machine_function.mbt`](../modules/machv/machine_function.mbt) defines semantic value kinds and blocks alongside spill-slot counts, parameter physical-register assignments, incoming integer stack-parameter counts, maximum outgoing-argument size, and embedding-context cache state. The public generated interface exposes all of those fields and mutators through [`pkg.generated.mbti`](../modules/machv/pkg.generated.mbti).

The current `ValueKind` also maps directly to a register class, so pointer/reference semantic types and target register-bank selection are already collapsed before target lowering. This conflicts with the decided MachV value contract, which has function-owned typed SSA values and no target register or location facts.

### The former MilkIR-to-backend lowering performed target lowering

Before ISS-196, the direct lowering package stored `ISA`, `EmbeddingABI`, runtime-symbol callbacks, trap-payload resolution, stack-parameter state, and target fusion selections in one lowering context. It assigned ABI registers and stack locations while creating function parameters and performed AMD64 shift-count register fixups before returning the function.

That package also contained AArch64 immediate and fused-instruction selection, while its call lowering emitted outgoing stack stores, physical argument/result registers, target clobbers, and fixed-register constraints. ISS-196 removed this producer after replacing it with the target-neutral `milkir_machv` and `wasm_machv` seams.

### Register allocation has two post-allocation representations

The public regalloc API returns both an allocated/rebuilt `@machv.Function` and a side-table [`Output`](../modules/machv_regalloc/pkg.generated.mbti). [`regalloc_apply.mbt`](../modules/machv_regalloc/regalloc_apply.mbt) rewrites virtual operands to physical registers and inserts target spill/reload/move operations into the same opcode union. It also contains AArch64-specific X16/X17 scratch assumptions.

At the same time, `Output` records allocation locations and edits by `(block_id, inst_idx, is_terminator)`. [`emit_function_with_regalloc`](../modules/machv_emit/prelude.mbt) looks those entries up against mutable block instruction arrays at lines 2177-2246. Any layout or instruction-list change can invalidate those coordinates without changing their types.

[`machv_regalloc/layout/layout.mbt`](../modules/machv_regalloc/layout/layout.mbt) has a special preserving-edges layout path because allocated edge copies live outside terminators. Its reorder path clones function metadata and pushes existing blocks into a new function. Both behaviors depend on raw integer block identities and object/array aliasing that the decided function-owned MachV model removes.

### Emission owns additional lowering and optimization

[`emit_function`](../modules/machv_emit/prelude.mbt) verifies and reorders MachV, calculates ABI result-area needs, callee-saved usage, context-register caching, spill/frame sizes, shared exit blocks, physical-register liveness, and peephole fusions before encoding. [`emit_function_with_regalloc`](../modules/machv_emit/prelude.mbt) repeats much of that work for the side-table allocation representation.

[`instruction.mbt`](../modules/machv_emit/instruction.mbt) dispatches to the AMD64 emitter when selected and otherwise matches the shared union as AArch64. `MachineCode` stores raw block-id labels and branch fixups together with code bytes, runtime-call relocations, GC safepoints, target constant pools, disassembly, and a Wasmoon debug-function-index spill offset. The reusable byte/fixup product is useful, but frame construction, allocation materialization, layout, and product debug state are currently entangled with it.

### Wasmoon already owns the correct product boundary

[`embedding_roles.mbt`](../modules/wasmoon_jit/embedding_roles.mbt) explicitly owns Wasmoon's historical register roles. [`vmcontext_abi.mbt`](../modules/wasmoon_jit/vmcontext_abi.mbt) owns concrete context offsets and translates them into the current generic embedding record. [`jit_runtime.mbt`](../modules/wasmoon/jit/jit_runtime.mbt) allocates executable memory, installs function pointers and GC safepoints, resolves runtime helpers, and applies target fixups after all functions are loaded.

These responsibilities do not need to move into MachV or target packages. The migration must instead replace the current broad `EmbeddingABI` data path with narrowly scoped inputs at target/ABI lowering and emission seams.

## Migration hazards and compatibility surfaces

| Severity | Hazard | Why it constrains migration | Required protection |
|---|---|---|---|
| Critical | Dual post-regalloc truth: rewritten Function plus index-keyed Output | The two forms can diverge after block layout or instruction mutation, and both are public emitter inputs. | Select one allocated Target VCode contract before changing layout or emitter ownership; compare emitted code through the transition. |
| Critical | Target instructions share one public enum | A partial move can create three semantic sources: legacy union, AArch64 VCode, and AMD64 VCode. | Migrate complete operation families behind target lowering and give every temporary adapter an explicit deletion condition. |
| High | Lowering applies ISA, ABI, traps and runtime-symbol policy before a target-neutral checkpoint | A new MachV producer cannot be proven neutral while these inputs remain required. | Establish and verify semantic MachV before target policy is supplied. |
| High | Raw block ids and instruction array indices are semantic identities across layout, regalloc and emission | Function-owned handles and canonical tables will invalidate clone/push and tuple-index assumptions. | Define stable Target VCode handles/program points before porting regalloc Output or layout. |
| High | Frame, call and context facts are split across Function, EmbeddingABI, regalloc and emitter | Moving only call opcodes leaves hidden ABI dependencies in prologue, stack args, clobber scans and context caching. | Treat native call/frame lowering as one boundary decision and verify it per target. |
| High | Public APIs expose constructors and mutable stage internals | Downstream code can construct `Opcode`, `PReg`, `Reg::Physical`, `Block`, allocated MachV and emission metadata directly. | Expect breaking minor releases for reusable modules; use generated `.mbti` diffs as the public-surface oracle. |
| High | Target wrappers are facades over shared lowering | Keeping their current signatures while adding real target lowering can hide duplicated work or bypass MachV. | Make both native targets pass the same verified MachV seam, then diverge only into their own VCode types. |
| Medium | Emitter performs layout, liveness, peepholes, frame lowering and code encoding | Moving the encoder alone will not establish a clean target backend boundary. | Inventory each emitter transform and assign it to Target VCode, regalloc materialization, frame lowering, or final encoding. |
| Medium | Debug output and CLI stages name pre/post-regalloc objects as MachV | Tests, `explore`, diagnostics and performance tooling may depend on current text even if machine behavior is unchanged. | Define replacement stage names and deliberately update snapshots/diagnostics at a named milestone. |
| Medium | Cwasm persists emitted bytes plus target-specific fixup and GC metadata | IR refactoring can change bytes, veneers, offsets or stack maps without changing Wasm results. | Keep the Cwasm schema product-owned and compare serialized artifacts/fixups where stability is required. |

The generated interfaces most directly affected are the semantic `machv` and `milkir_machv` interfaces, the legacy backend interfaces, `machv_regalloc`, `machv_emit`, and both target-policy packages. Product consumers include `wasmoon_jit`, `wasmoon`, `wasmoon/preflight`, and the CLI commands package.

## Existing behavior tests to preserve

| Layer | Current protection | Migration relevance |
|---|---|---|
| MachV structure and verifier | [`machv_test.mbt`](../modules/machv/machv_test.mbt), [`verify_test.mbt`](../modules/machv/verify_test.mbt) | Builder/printing, terminators, edge arguments, SSA dominance, duplicate ids, opcode arity/classes, call metadata, vector memory and ISA physical-register rejection. These tests encode both desired semantic invariants and legacy target leakage; they must be split rather than copied wholesale. |
| MilkIR and Wasm lowering | [`semantic_lower_test.mbt`](../modules/milkir_machv/semantic_lower_test.mbt), [`lower_test.mbt`](../modules/wasm_machv/lower_test.mbt) | Protect verified-input seams, edge arguments, 64-bit carriers, float bit identity, dialect errors, semantic calls, roots, and table32/table64 indirect calls. |
| Target policy | [`aarch64_target_test.mbt`](../modules/aarch64_target/aarch64_target_test.mbt), [`x64_target_test.mbt`](../modules/x64_target/x64_target_test.mbt) | Protect ABI and machine-environment policy. They should become target-VCode boundary tests. |
| Regalloc and layout | [`machv_regalloc_test.mbt`](../modules/machv_regalloc/machv_regalloc_test.mbt), [`layout_wbtest.mbt`](../modules/machv_regalloc/layout/layout_wbtest.mbt) | Protect fixed constraints, allocation locations, invalid-input rejection, block-id assumptions, edge-copy preservation and loop/layout ordering. |
| Emitter | [`machv_emit/verify_test.mbt`](../modules/machv_emit/verify_test.mbt) and documentation tests in [`machv_emit/README.mbt.md`](../modules/machv_emit/README.mbt.md) | Only a small direct seam suite exists: invalid MachV rejection and basic AArch64 bytes/fixups. Target VCode migration needs per-target legality and allocated-form negative tests before the legacy union disappears. |
| Wasmoon JIT integration | [`wasmoon_jit_test.mbt`](../modules/wasmoon_jit/wasmoon_jit_test.mbt), trampoline white-box tests, and [`cwasm_wbtest.mbt`](../modules/wasmoon_jit/cwasm/cwasm_wbtest.mbt) | Broad coverage of target fixups, runtime-symbol ownership, Cwasm metadata, AArch64/X64 integration, calls, memory, SIMD, entry/hostcall trampolines, stack arguments and multi-value results. |
| End-to-end native behavior | `modules/wasmoon/testsuite` differential tests plus `scripts/run_all_wast.py` | `compare_jit_interp` covers arithmetic, calls, branches, memory64, SIMD, GC, exceptions, stack arguments and indirect calls. The WAST runner is the broad native-JIT acceptance gate for both target configurations available in CI. |

Current tests are strong at end-to-end behavior but weak at the intended new seams because those seams do not exist yet. In particular, there is no type-level test proving that AArch64 instructions cannot enter AMD64 VCode, no allocated-VCode verifier suite, and only one direct emitter invalid-input test.

## Constraints for the later migration route

This inventory does not choose the migration order. It establishes constraints that [Choose the migration and compatibility route](../issues/ISS-192.md) must satisfy:

1. Preserve one mandatory, verified MilkIR-to-MachV seam for both native targets.
2. Introduce stable Target VCode block, instruction and program-point identities before adapting register allocation or layout.
3. Eliminate one of the two current post-regalloc representations before allowing target emitters to depend on the replacement.
4. Move target operation families with their verifier, lowering, printer and emitter behavior together; do not maintain a long-lived legacy union alongside two complete target dialects.
5. Keep Wasmoon VMContext, runtime symbols, executable memory, Cwasm and fixup installation product-owned.
6. Use generated interface diffs, target-specific unit tests, JIT/interpreter differential tests, WAST tests and emitted artifact comparisons as explicit milestone gates.

No production source was changed while producing this inventory.
