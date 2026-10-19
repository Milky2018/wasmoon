# PR #545 review fixes

These fixes were validated on clean source commit
`8c0056b67a5e8f7bfb9d1c4226271e61f421835c` on macOS ARM64. The
[local receipt](review-local.json) records that exact revision and separates it
from the historical dirty evidence in this directory. This is not Linux LSan
or Windows CI acceptance; the original PR head's green checks do not accept
these follow-up changes.

## Independent fixes

| Commit | Defect and regression |
| --- | --- |
| `956ba170` | Exception rollback releases managed byte/object leases; repeated failures, healthy admission and Store cleanup. |
| `a1e9fa05` | Failed continuation preparation releases provisional PendingWork; repeated failures, exact cancellation and root retirement. |
| `dbbadd2b` | Standalone Table close is terminal through aliases, empty operations, growth and Store adoption. |
| `aa45d5b0` | Public MarkSweepHeap.close releases standalone capacity and forbids allocation after close; collection still charges retained reusable slots. |
| `cf496267` | Both WAST runners require successful decoding before accepting a Core validation rejection. |
| `49953a0e` | Binary and text alignment decoding preserves well-formed exponents for validation; malformed flags/powers remain rejected. |
| `e79fc0d9` | Text memory/table limits retain u64 values for address-width validation; table32 comparisons are unsigned. |
| `c3ab492c` | Numeric indirect-call type indices reach validation; unresolved names and inline signature syntax remain parser checks. |
| `8c0056b6` | Table initializer global scope is validated for text and binary in both validator entry points. |

Three separate supporting commits share completed-action verdicts (`360c2539`),
include the four new runtime regressions in the sanitizer closure (`ec5801a7`),
and replace an old capability test's invalidity false positive with an exact
instantiation-error assertion (`eb4f1fee`).

## Validation

- Strict native and wasm checks, `moon info`, `moon fmt`, module boundaries and
  the full committed diff pass.
- Workspace tests: native 2,777/2,777; wasm 1,305/1,305.
- Explicit wasm runtime/executor/WAST tests: 226/226; actual embedding returns
  43, observes host argument 21, reads memory 21 and returns its budget.
- Core WAST: 258 files and 62,563 assertions on each of native interpreter,
  actual wasm interpreter and native JIT; zero failures or unsupported cases.
- Fresh local ASan/UBSan: 193/193 and both ASan positive controls detected.
  `leak_detection=false` and LSan not applicable on this host remain explicit.
- Strict native C: 43 stubs compile with warnings denied. Script tests pass in
  each commit hook (172 tests, 54 existing platform skips).

Strict phase checking initially exposed 19 hidden early rejections in six Core
files on both interpreter hosts. These were fixed at the parser/validator
boundary, without weakening assertions, skipping cases or treating parse errors
as validation errors. A separate existing test had called a valid module
invalid solely because the engine rejects continuation references in GC storage;
it now checks Core validity, the exact engine error, and failure of
`assert_invalid` as distinct properties.

The reference decoder reads unsigned LEB memarg flags and leaves natural
alignment to validation; the reference text grammar uses u64 limits and
alignment values. See the official [binary decoder](https://github.com/WebAssembly/spec/blob/main/interpreter/binary/decode.ml)
and [text grammar](https://github.com/WebAssembly/spec/blob/main/interpreter/text/parser.mly).
