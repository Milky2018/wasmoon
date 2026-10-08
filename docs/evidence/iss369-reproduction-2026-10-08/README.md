# ISS-369: spilling loop reproduction

## Finding

The avoidable back-edge move described by ISS-369 was **not reproduced** in
this experiment. Real spilling is present, including spills inside the loop,
but the conflict-free `x += 3` chain coalesces on both AArch64 and x64.

A paired control does emit a back-edge transfer when old and new `x` are
simultaneously live. That transfer is not evidence of a failed legal merge:
merging these two values at the add would overwrite an old value still needed
by a later instruction. No allocator or instruction-scheduling changes were
made. After reviewing this evidence, the user agreed to close ISS-369 as an
unconfirmed historical defect. This is a bounded reproduction result, not a
proof that every spilling loop coalesces optimally or a performance acceptance.
Reopen with a concrete failing input if an avoidable move returns under spilling.

## Scope

- Source: `e9bf7118217a370c3a8f5c151f0938ba614825a7`.
- Host execution: macOS 26.7 ARM64, MoonBit `0.1.20260920`.
- Fresh release CLI build, default exploration optimization level 2.
- Basic family: 0, 8, 16, 24, 32, 40 and 64 memory-loaded carried locals,
  with the `x += 3` update placed first or last in the loop (14 modules).
- Control pairs: 8, 24, 32 and 40 carried locals, with a later use of either
  new `x` or old `x` (8 modules).
- All 22 modules compile for both targets: 44 allocation/code-generation
  inspections. All 18 conflict-free modules have no back-edge edits on either
  target. The four genuine-conflict controls have transfers on both targets.
- Both interpreter and host AArch64 JIT execute all 22 modules with 12 expected
  results each: 528 passing assertions. Inputs use 1, 2 and 17 iterations and
  seeds 0, 7, -3 and 2147483647, including wrapping arithmetic.
- x64 evidence is cross-target compilation and disassembly, **not x64 runtime
  execution**. No timing benchmark or algorithm corpus sweep was performed.

Memory loads initialize the pressure locals; the loop updates every local and
the returned sum consumes them. The input and output values therefore remain
observable. The 32-local fixtures below all spill inside the loop, so they do
not repeat the old audit's mistake of treating non-spilling pressure as proof.

## Saved fixtures and allocations

| Fixture | Target | Spill-slot IDs | Loop spill/reload edits | `x` input -> result home | Back-edge transfer for `x` |
| --- | --- | ---: | --- | --- | --- |
| `spilling-loop.wast` | AArch64 | 19 | 27 / 27 | p28 -> p28 | none |
| `spilling-loop.wast` | x64 | 32 | 72 / 72 | p6 -> p6 | none |
| `spilling-new-only.wast` | AArch64 | 19 | 27 / 27 | p2 -> p2 | none |
| `spilling-new-only.wast` | x64 | 32 | 72 / 72 | p3 -> p3 | none |
| `spilling-conflict.wast` | AArch64 | 19 | 18 / 19 | p0 -> p28 | p28 -> p0 |
| `spilling-conflict.wast` | x64 | 33 | 48 / 49 | p8 -> stack30 | stack30 -> p8 |

Counts describe static allocation edits, not measured memory traffic. Spill-slot
counts include allocator scratch slots. Loop edit counts exclude entry and exit
blocks and separately represented edge edits. Physical-register IDs come from
the target VCode, not a shared architectural register-number convention.

The positive AArch64 machine code has `add w28, w28, #3`; the x64 code has
`addl %r9d, %esi` after materializing 3 in r9. Both keep the result in the same
register as the loop parameter and emit no back-edge move for it.

The paired controls differ in whether the second dependent update reads old or
new `x`:

```text
old = x
x = x + 3
p0 = p0 + x
p1 = p1 + old   // conflict control; new-only control uses x here
```

For the AArch64 conflict control, the actual emitted instructions include:

```asm
0x180: add w28, w0, #3
0x184: add w27, w27, w28
0x188: add w22, w22, w0
...
0x2a4: mov w0, w28
0x2a8: b 0x180
```

Changing the first add to write w0 would make the third instruction read the
wrong value. Reordering instructions or preserving old `x` elsewhere would be
a different transformation, not justification for merging overlapping live
ranges. In the new-only control the compiler instead emits
`add w2, w2, #3`, with no back-edge transfer.

## Replay and raw evidence

The three adjacent WAST files are standalone correctness fixtures:

```sh
./wasmoon test docs/evidence/iss369-reproduction-2026-10-08/spilling-loop.wast
./wasmoon test docs/evidence/iss369-reproduction-2026-10-08/spilling-loop.wast --no-jit
```

Repeat for `spilling-new-only.wast` and `spilling-conflict.wast`. To inspect
compilation, copy the module portion before the first `assert_return` into a
`.wat` file, then run:

```sh
./wasmoon explore fixture.wat --stage allocated-vcode --stage mc --target aarch64
./wasmoon explore fixture.wat --stage allocated-vcode --stage mc --target x64
```

`evidence.json.gz` retains all 22 module inputs and WAST fixtures, 44 compiler
reports, 44 execution logs, summary tables, build/toolchain metadata, and the
six disassemblies for the saved 32-local fixtures. Its `files` object also
contains the temporary generation/inspection/replay scripts. These are bounded
diagnostic artifacts, not a new repository audit framework or CI gate.

Disassembly wraps the exact emitted bytes in a target object with `clang -arch`
and reads it with `llvm-objdump --disassemble`; addresses are offsets within the
function. Absolute paths in the archived scripts identify this local run and
must be adjusted for replay.
