# Builtin import routing (ISS-640)

Investigation and local repair on macOS ARM64, based on merged main `aac8ce10`.
The installed stable toolchain is unchanged. These new source changes have not
received Windows or Linux CI acceptance; PR #542 validates the earlier GC and
continuation migrations, not this repair.

## Root cause and family inventory

The frontend prepends one native context to Wasm arguments. The eight C
spectest imports instead declared two obsolete integer arguments (`func_table`,
`mem_base`). The float and mixed implementations also declared Wasm floats as
integer arguments. A fresh main CLI emits NUL for `print_char(65)` while the
interpreter emits `A`. LLDB stops at the actual native entry: x1 contains 0x41,
but its instructions move x2 to x0 before calling `putchar`. See
`registers-before.log`; no timing or language-overhead claim is involved.

The complete implicit native builtin family was:

| Name | Wasm parameters | Results |
| --- | --- | --- |
| print | none | none |
| print_i32, print_char | i32 | none |
| print_i64 | i64 | none |
| print_f32 | f32 | none |
| print_f64 | f64 | none |
| print_i32_f32 | i32, f32 | none |
| print_f64_f64 | f64, f64 | none |

All original builtins return void. A second defect affects arbitrary valid
linker overrides, including non-void signatures: `build_external_imports_for_jit`
skipped the actual linked function solely because its import name matched a
builtin. The native no-op then bypassed callbacks and produced no requested
results. `callback-before.log` demonstrates the bypass on unmodified main.
The existing Microsoft bridge test validates the integer signatures it is
given, so it could not detect disagreement with the actual Wasm signature.

## Repair and boundary

Delete the duplicate native builtin implementations, private pointer getters
and their generated MSVC bridges. All resolved Store host functions now use the
existing signature-aware hostcall trampoline and the same host implementation
as the interpreter. No new ABI or builtin dispatcher is added. Import module
names no longer override a real linker binding. WASIp1 already uses this path.

Public resolution functions remain available. `get_import_trampoline` returns
None: a bare artifact loader without a Store must supply its imports explicitly.
`resolve_import_function_ptr` still accepts explicit guest-ABI native pointers
and encoded host addresses. The caller owns the signature contract of an
explicit raw pointer. Compiled Wasm-to-Wasm imports keep their existing direct
route. Standard spectest non-function resources retain their existing handling.

## Behavioral regression coverage

The shared ordinary/sanitizer fixture observes actual callbacks for all eight
names with their standard parameter signatures. It compares both engines and
fails original main before the repair (`print, native=true`).

A valid builtin-named host override round-trips 41 values: ten groups of i32,
i64, f32 and f64 plus a v128. Distinct inputs are checked at callback entry and
again at the guest result. This crosses both integer and floating register
limits, stack arguments and overflow result areas. Six guest instruction forms
are exercised independently: call, return_call, call_indirect,
return_call_indirect, call_ref and return_call_ref. These are actual executions,
not byte-shape or pointer-presence assertions.

A third test checks signed zero, infinities and noncanonical quiet-NaN payload
bits in f32/f64 arguments and results. The guest reinterprets results as integers
so floating equality cannot hide changed bits. The standard CLI repro now
prints `A` with both engines; `char-after.json` binds the release binary and raw
stdout. Private pointer-only native helpers retain their existing MSVC bridge
contract; no floating C bridge generator was introduced.

See the source/validation manifest for local gates and their exact source
provenance. New Windows Clang/MSVC acceptance remains open under ISS-640.

## Additional x64 return-register defect

The overflow-result audit found `x64_emit_load_result_from_values_vec` using
r10 as scratch after loading the eighth integer result into that same register.
Writing later integer overflow results consequently replaced that live result.
Use r11, which is call scratch and carries no guest result. No ABI layout,
register allocation policy or platform bridge contract changes.

A controlled probe executes actual locally generated x64 trampoline code under
Rosetta on this ARM64 Mac. The bridge verifies its id/slot counts and writes ten
distinct i64 results. An assembly caller captures all eight result registers and
two overflow slots. Original code returns 109 instead of 107 at result[7]; the
fixed code returns all ten correctly. Restoring only the old scratch choice in
the local source reproduces failure, then restoring the fix passes. No mutation
remains. The shared 41-value native test also exercises this path on x64 CI.
The older byte-shape helper is updated to recognize r11 stores; runtime results,
rather than that helper alone, establish correctness.

`x64-before-code.json` and `x64-after-code.json` are the actual emitted bytes.
`x64-probe.c` replaces only the unique mov-r11/call-r11 bridge target immediate
with its local C stub, allocates executable code and checks the results.
`x64-probe.S` supplies the guest result-area register and captures returns.
Reproduction uses a temporary ordinary module with a moon.work that explicitly
includes this repository's module paths and the temporary module. Its imports
are wasmoon_jit and wasm_core/types; `x64-emit.mbt.txt` is its main. Standalone
.mbtx resolution selected published dependencies, so it is not used as the
local-source control. An initial published-source diagnostic is not archived
as final evidence. Generate code.h from either byte array, then compile:

```sh
clang -arch x86_64 -Wall -Wextra -Werror x64-probe.c x64-probe.S -o probe
./probe
```

This is real x64/SysV execution under Rosetta, not Windows Clang/MSVC acceptance.
The latter remains required by ISS-640. No Linux leak-detection claim is made
from macOS sanitizer output.
