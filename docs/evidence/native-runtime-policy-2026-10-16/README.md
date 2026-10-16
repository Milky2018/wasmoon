# Native runtime policy migration: local evidence

These are uncommitted macOS ARM64 working-tree receipts based on
`5490d6bf1cc293c1a3adc42dd3583e607b1ec631`. They do not establish clean-head CI,
Linux LSan or Windows Clang/MSVC acceptance. The configured stable toolchain
was not changed. ISS-634's separate work remains present.

- Strict native MoonBit checking denies warnings, including warning 73.
- All 43 declared C stubs compile with warnings denied.
- Native tests pass 2725/2725, including four new public-behavior tests that
  exercise six allocation layouts, transient/persistent failure, reuse, visitor
  abort and byte/object quota classifications. One of these tests also keeps
  child references staged in scalar and mixed-vector aggregate payloads alive
  during the forced retry.
- Restoring the previous word-path error collapse fails the new regression:
  `"out of memory" != "gc precise roots unavailable"`. The mutation was removed.
- Fresh ASan/UBSan runs 167/167 and detects both independent ASan positive
  controls. On macOS `leak_detection=false`; no Linux LSan claim is made.
- Core WAST: 258/258 files and 62563 assertions per engine. Component suites
  in both engines: stable 23/23 (845 commands), async 24/24 (153), future
  12/12 (387),
  no skipped commands. WASI 0.3 HTTP-contract passes 110/110 cases.
- GC differential: 17/17 files in interpreter, JIT, stress/verification and
  small-heap modes. The additional first-allocation fault mode has eight
  non-passing files because global initialization can fail before guest calls;
  baseline/candidate exit status and tallies match on all 17 files. It is not
  reported as a passing fault-injection corpus.
- Expanding the existing exception failure probe to first arena creation
  reproduces a SIGSEGV. With the two null-status reads fixed, both current
  exception and explicit-payload capture report OOM and the context is reusable.
  The new probe runs in the ordinary and isolated sanitizer closures.
- Existing script tests: 172 run, 54 platform skips; bridge generation is fresh.
- Native helpers are separate members of `libjit_ffi.a`; no `wasmoon_test_`
  symbol occurs in the linked local release executable. Windows MASM execution
  remains unverified locally.

`comparison.json` records paired, alternating serial CLI runs, including module
loading/compilation, with the first pair excluded. It is not an isolated
allocator benchmark or cross-platform performance proof. Workload sources and
binary digests are included for reproduction; binaries remain under ignored
`target/native-policy`. The code migration leaves generated inline allocation
unchanged. An intermediate version entered MoonBit on every allocation helper
call; its normal wide-allocation measurement showed roughly 9% overhead in one
paired run (`comparison-before-success-bypass.json`). The current bridge tries
the physical allocation directly and enters MoonBit only after failure. A
later forced-collection
intermediate also measured roughly 22% across binaries. Equal root/collection
counts, native sampling, and a same-executable C/MoonBit control (about 1.3%
policy overhead) do not establish a precise hardware-level cause. Preserving
old descriptor offsets alone did not remove that gap. Non-callback native
scan phases now snapshot their stable spans, eliminating avoidable descriptor
reloads caused by potential C aliasing. The final paired results are in
`comparison.json`; these are not isolated allocator measurements.

`source-manifest.json` records hashes of the exact current native/MoonBit/test
sources; logs and sanitizer summary retain dirty-source provenance. Exception
and continuation registry migration is not part of these acceptance results.

Final local medians (11 paired samples after warmup):

| CLI workload | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Word structs, 2M | 126.55ms | 127.68ms | +0.9% |
| Wide structs, 1M | 24.82ms | 25.42ms | +2.4% |
| Wide structs, 30k, every second attempt denied | 536.84ms | 485.97ms | -9.5% |

`same-binary-policy-comparison.json` is an isolated pre-scan-optimization
experiment. Its native control exists only in the ignored experimental
workspace, never in the production sources. `experiment-control.patch` records
that control; source hashes identify the two experimental C files. The
field-placement comparison retains the unsuccessful offset hypothesis. These
controls are not additional production implementations or passing CI receipts.
