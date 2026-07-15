# Target VCode Shell Prototype

PROTOTYPE ONLY. This disposable package answers one question from [Prototype the generic Target VCode shell](../../../issues/ISS-185.md): can MoonBit express one shared function/block/CFG shell parameterized by two unrelated closed target instruction types, while register allocation consumes both through one small projection seam?

Run it with:

```sh
moon -C modules/machv/target_vcode_prototype run --target native .
```

The sketch uses `VCodeFunction[Inst]`, `VCodeBlock[Inst]`, and `Terminator[Inst]` as the shared shell. `AArch64Inst` and `AMD64Inst` are independent closed enums. Both implement the one-method `AllocatableInst` trait, which exposes only register-allocation operands. `project_regalloc` derives body/terminator position from the shared shell and produces a non-generic allocation view keyed by stable block and instruction handles. The TUI's separate `RenderInst` trait is display-only, so allocator-facing code does not learn target names or mnemonics.

The important compile-time property is that target instructions cannot cross:

```mbt nocheck
let a64 : VCodeFunction[AArch64Inst] = aarch64_demo()

// Does not type-check: AMD64Inst is not AArch64Inst.
a64.blocks[0].body.push({ id: InstId(99), inst: AMD64Inst::SetParity(VReg(3)) })
```

The prototype intentionally omits owner tokens, deletion/liveness tracking, verification, complete CFGs, real register classes, allocation results, mutation guards, target lowering, and emission. Those would obscure the type relationship being tested and remain decisions for later tickets.

Delete or absorb this package after the interface decision is recorded.
