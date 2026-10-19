# Portable interpreter and strict WAT validation: local evidence

This is **local, dirty macOS ARM64 evidence**, based on main
`8f99719a69d32e79325edf06785039f4d3fbf071`. It is not a submitted PR, clean
commit receipt, registry release, Windows result or Linux LSan acceptance.
`local.json` records the toolchain, artifact hashes and result totals;
`source-manifest.json` records the changed implementation inputs. Archived
diagnostic logs have presentation-only trailing whitespace removed; source,
artifact hashes, assertion counts and sanitizer verdicts are unchanged.

## Results

| Check | Result |
| --- | --- |
| Workspace native tests | 2,765 passed |
| Workspace wasm tests | 1,294 passed |
| Explicit wasm runtime/executor/WAST tests | 220 passed |
| Strict MoonBit checks | Native and wasm, warnings denied |
| Native C gate | 43 stubs, warnings denied |
| Script tests | 172 total; 54 existing platform skips; zero failures |
| Actual wasm embedding | Guest result 43, observed host argument 21, memory 21; budget restored |
| Core WAST | 258 files / 62,563 assertions per engine; native interpreter, wasm interpreter and native JIT |
| Component WAST | 59 files / 1,385 commands per native engine; zero skips |
| WASI03 HTTP-contract profile | 110/110 across both native engines |
| Independent package archives | Native install/WASI on both engines; actual wasm embedding |
| Fresh local ASan/UBSan | 189/189 and both ASan positive controls detected |

`sanitizer.json` explicitly records `leak_detection=false` and LSan not
applicable on this host. Ordinary sanitizer success and positive controls do
not establish Linux leak detection. Native platform CI and the new
`Wasm interpreter` job still need to accept the submitted implementation.
The wasm workspace total includes reusable compiler/specification tests;
`portable-tests.log` separately proves execution of the actual runtime,
executor and Core adapter packages rather than a target-filtered empty suite.

`embedding-imports.wat.txt` and `async-imports.wat.txt` are actual artifact import
sections. They document `moonrun` host requirements; this is not a generic
browser or WASIp1 host acceptance claim. Guest WASI, Components, JIT and shared
memory remain unavailable in the wasm embedding.

## Correcting the historical false green

`text-baseline.json` preserves the initial strict result: 628 malformed-text
false accepts in 22 files, with 61,935 passing assertions on both interpreter
hosts. It retains diagnostics for failed files. Earlier apparent full passes
used the old runner's unconditional rejection of quoted module sources.

The final `core-native-wasm.json` contains per-file hashes, counts and actual
artifact identities; `core-jit.json` is the native CLI control. These are strict
passes after repairing the frontend, not an allowlist or a change to WAST
expectations. Negative controls prove valid quoted text cannot pass
`assert_malformed`, unsupported capabilities cannot pass unlinkable assertions,
and quoted start traps must match the expected trap category. Raw Core string
spelling also survives Component reconstruction, including arbitrary data bytes
and UTF-8 names.

The initial WASI03 launch used system Python without the upstream runner's
`colorama` dependency and reported harness errors. The recorded final receipt
uses the existing runner virtual environment and passes all 110 cases.

## Native interpreter timing control

`native-performance.json` retains every sample and both binary hashes.
`benchmark.mbt` is the identical input used by baseline and candidate: one
million guest loop iterations with memory, GC or exception operations. Parsing,
validation and instantiation occur outside the timer; the final Store collection
is inside. There is no JIT, parallel compilation, performance threshold or
compilation/runtime mixture in these timings.

Both native release binaries were built before the recorded timing run, against
the same toolchain. The baseline used an archive of the base revision; the
candidate used the final runtime/parser implementation. One warmup pair was
excluded, followed by seven serial alternating pairs. No other project build or
test was launched during the recorded run. Initial exploratory samples and one
run overlapping a focused test were discarded; the JSON contains only the final
isolated run.

| Workload | Baseline median | Candidate median | Change |
| --- | ---: | ---: | ---: |
| Memory | 0.256664 s | 0.256856 s | +0.07% |
| GC | 0.516615 s | 0.494028 s | -4.37% |
| Exceptions | 0.498966 s | 0.486550 s | -2.49% |

These bounded examples show no material regression in this measurement. They do
not prove a general speedup or cover native JIT or wasm-host performance.
`measure.py` reproduces the alternating measurement after building
`target/iss641-bench-build-{baseline,candidate}/native/release/build/`
`Milky2018/portable_bench/portable_bench.exe`. The benchmark manifests are included;
use separate `moon.work` files pointing at the archived baseline and current
workspace members respectively. Native access still selects physical storage at
compile time, without a per-access storage vtable.

## Reproduce the functional gates

From the repository root:

```sh
moon info
moon fmt
moon check --target native --warn-list +73 --deny-warn
moon test --target native
moon test --target wasm
moon test modules/wasmoon_runtime/runtime modules/wasmoon_runtime/executor \
  modules/wasmoon_runtime/wast --target wasm --warn-list +73 --deny-warn
moon run modules/wasmoon_runtime/examples/embedding --target wasm
python3 scripts/run_portable_core_wast.py
python3 scripts/check_native_c.py
python3 scripts/audit_module_boundaries.py
python3 scripts/msvc/generate_guest_bridges.py --check
python3 scripts/run_sanitizers.py
python3 scripts/test_packaged_install.py
```

Component runs use `scripts/run_component_wast.py` with each pinned suite and
both execution modes. The native CLI was freshly built into
`target/iss641-cli`; its full path was passed to external runners. WASI03 uses
`scripts/run_wasi03.py --http-contract-tests --jobs 1` with the pinned corpus and
upstream runner Python requirements installed. Artifact installation tests use
actual package archives extracted into unrelated directories, without publishing.

Text-validity rules follow the official Core specification's
[lexical conventions](https://webassembly.github.io/spec/core/text/lexical.html)
and [text values](https://webassembly.github.io/spec/core/text/values.html).

## PR review follow-up

[Review fixes and clean local regression evidence](review-fixes.md) document
separate follow-up commits and the 19 hidden phase errors exposed by strict
assertion handling. The original dirty receipts above remain historical.

## Historical initial platform CI acceptance

[Historical CI receipt](ci-a25d9db5-historical.json) accepts implementation `a25d9db5` in
[run 39238063977](https://github.com/Milky2018/wasmoon/actions/runs/39238063977).
All six jobs passed. The source merge `8d80e1c9` has main `8f99719a` and
implementation `a25d9db5` as its parents; both sanitizer and portable artifacts
record this clean source. Historical receipts above retain their original scope.

Native and actual wasm adapters each pass 258 files / 62,563 strict Core
assertions. Focused wasm tests pass 226/226 and embedding result/callback/memory
are 43/21/21 with budget restoration. Linux ASan/UBSan/LSan passes 193/193 with
leak detection enabled, three detection controls, no ordinary leak/UB report and
a separate expected 17-byte leak. Both Windows compilers execute 2,783 inventoried
native tests across 60 packages, compile 43 strict C stubs and pass 110 external
HTTP-contract cases, actual MASM ABI probes and packaged wasm embedding. Their
53 native probes retain three existing privilege-dependent skips.

The complete pinned Wasmtime misc snapshot passes 692 assertion runs and 72
script-only runs per platform across both engines. `b108561e` preserves custom
page-size decoding until Core validation. `a25d9db5` explicitly selects the
upstream engine-build assertion profile while preserving strict default Core
assertions, malformed-input rejection and expected-diagnostic controls. Fixtures,
skips and deadlines were not relaxed. Latest local workspace totals are native
2,783 and wasm 1,310; they are distinct from focused wasm and CI package counts.

The acceptance documentation head is checked separately after this receipt is
committed. No further evidence-only commit is needed for that check. This PR is
not merged while user review is open. ASan instrumentation exclusions in
`ci.json` remain explicit; passing tests are bounded regression evidence.

## Review follow-up platform acceptance

Current [CI receipts](ci.json) accept implementation `cc644415` in
[run 39246263241](https://github.com/Milky2018/wasmoon/actions/runs/39246263241).
All six jobs passed. Sanitizer and portable artifacts use clean source merge
`dae81454402cc70e80438762f1ec6f5dabf13232`, whose parents are main `8f99719a`
and implementation `cc644415`. Earlier receipt files remain retrievable from
commit `353b1123`; their metadata is preserved in the historical JSON above.

- `2428dfb0` removes truncating memory/table limit encoding. Public Component
  regressions preserve rejection of oversized minimum/maximum values, including
  defined and both imported forms, while valid 32/64-bit neighbors still pass.
- `cc644415` enforces unsigned u32 syntax in the shared type-index parser.
  Signed/negative/overflowing indices fail parsing; bit-31 and u32-maximum
  indices still parse before receiving typed semantic validation errors.
- Windows Clang and MSVC each executed all 2,786 inventoried native tests in
  60 packages, 43 strict C stubs, 110 external HTTP-contract cases, the complete
  692 assertion / 72 script-only misc runs, actual MASM ABI probes and packaged
  wasm embedding. Each 53-test native probe suite retains three existing
  privilege-dependent skips.
- Linux ASan/UBSan/LSan passed 193/193, leak detection enabled, all three
  detection controls, no ordinary leak/UB report and separate expected 17-byte
  LSan leak. Native and actual wasm each passed 258 files / 62,563 Core
  assertions; focused wasm passed 226 with embedding result/callback/memory
  43/21/21 and restored budget. Linux/macOS complete jobs also passed.

Clean local `cc644415` additionally passed native 2,786, wasm 1,313, Component
59 files / 1,385 commands on each native engine without skips and complete misc
764 runs without failures. The fresh CLI rejects all four embedded-limit review
examples and both negative indirect-call type indices. The original escaped
UTF-8 alias remains accepted by Wasmoon and wasm-tools 1.254.0. These local
results remain separate from CI provenance.

This updated acceptance documentation must pass all six jobs separately.
No further evidence-only commit is needed for that final check. User review
remains open; the PR has not been merged.
