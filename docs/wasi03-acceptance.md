# WASI 0.3 acceptance audit

## Follow-up implementation and verification

The initial audit below is retained as historical evidence. The fixes following
that audit allow all 55 unchanged guests to reach execution on both engines.
On macOS ARM64 the complete isolated suite reports **53 pass, 2 fail per engine**:
all CLI, clock, random, filesystem and socket cases, all 14 HTTP service cases,
and two of the four HTTP type command cases pass. Full WASI acceptance is still
not claimed. Raw release-binary results and validation metadata are retained in
[the follow-up evidence](evidence/wasi03-2026-09-18-fixes/).

The runtime fixes cover compatible import matching, typed host exits, host stream
scheduling and EOF, elapsed clock deadlines, filesystem flags/errors and socket
state/half-close/option behavior. A trailing-slash unlink regression additionally
verifies that a directory symlink is not deleted.

Reproduce with a freshly built binary and a Python environment containing the
pinned upstream runner requirements:

```sh
python scripts/run_wasi03.py --upstream /path/to/wasi-testsuite \
  --wasmoon ./wasmoon --output target/wasi03-results
```

The upstream checkout must be at `609c446139956ff30239f87cb18af1dc6128bed2`.
`scripts/wasi03-corpus.json` pins every guest, expectation and fixture checksum.
Each engine/case gets a new filesystem fixture; a process-tree watchdog bounds
upstream blocking reads. Guest assertions and binaries are unchanged.

The strict command returns failure for the two HTTP differences:

- `http-fields.rs:309`: upstream expects lowercase names from `copy-all`; the
  pinned HTTP WIT explicitly requires original casing. Wasmoon preserves it.
- `http-request.rs:157`: upstream expects an empty path to become `/`; Wasmoon
  preserves the setter value and emits `/` when constructing an HTTP request
  target. Later URI assertions also require separate contract review (ISS-571).

CI uses `--acknowledge-known-differences` as a regression gate. This keeps raw
results marked **fail**, acknowledges only the exact reviewed panic/value
fingerprints, and rejects new failures, timeouts, harness errors and unexpected
passes. It is not a conformance pass. Reports are uploaded from Linux, macOS,
Windows Clang and Windows MSVC; local evidence alone does not establish those
platforms' results.

Remaining boundaries:

- ISS-568: async exposes only `TlsError(String)`; structured certificate/protocol/
  alert categories depend on [async issue #620](https://github.com/moonbitlang/async/issues/620).
- ISS-572: command HTTP composition with concurrent native WASI I/O needs reactor
  integration. The current type-command guests and HTTP services do not prove it.
- ISS-567: the intermittent macOS misc JIT timeout is outside this repair scope.

## Original audit verdict

**Full acceptance is not established.** The pinned WASI 0.3.0 host surface is
present, and the existing targeted tests pass, but real upstream Preview 3 guests
fail during linking before their behavioral assertions execute. Interface
registration, Component Model conformance and WASI behavioral conformance are
separate evidence layers.

Audited runtime: `8d950c08d19ab90525d3cb83331cc68ddf4ac833` on macOS ARM64,
2026-09-18. No runtime implementation was changed by this audit. Two registration
regressions and an external command-world adapter were added. The freshly built
runtime and every external guest have checksums in
[evidence/manifest.json](evidence/wasi03-2026-09-18/manifest.json).

## Contract and implementation matrix

Contracts are pinned to WebAssembly/WASI `v0.3.0`, commit
`3ee2a590c766594ae44a54730fc74fc27da5c609`. Both contract generators passed
`--verify-wit --check` using wasm-tools 1.254.0. This verifies the vendored WIT,
normalized JSON and generated signatures agree, not every implementation branch.

| Interface family | Function surface | Implementation | Behavioral evidence and remaining boundary |
| --- | ---: | --- | --- |
| CLI environment, exit, stdio, terminals | 11 imports | `wasi_component/base_interfaces.mbt`, `stdio_preview3.mbt` | Local environment, exit, byte-stream, error-payload and readiness tests pass. External guests blocked by compatible Preview 2 imports. |
| Monotonic/system clocks | 6 imports | `base_interfaces.mbt`, `async_preview3.mbt` | Local timer/readiness/cancellation tests pass. External behavior not accepted. |
| Random/insecure/seed | 5 imports | `base_interfaces.mbt` | Local seed/export checks pass; external `random.wasm` fails linking in Wasmoon and passes with Wasmtime 48.0.2. |
| Filesystem/preopens | 26 imports | `filesystem_preview3.mbt` | Local capability traversal, UTF-8, errno/type/time and stream tests pass. External filesystem assertions not reached. |
| Socket types/name lookup | 41 imports | `sockets_preview3.mbt` | Local network-denial, UDP datagram, resolver-error and async tests pass. External TCP/UDP/property assertions not reached. |
| HTTP types | 35 functions | `wasi_http/fields.mbt`, `message.mbt`, `dispatch.mbt` | Local resource, ownership, receipt and URI tests pass. Four external command guests cannot access HTTP types through the command CLI. |
| HTTP client/handler | 1 function each | `client.mbt`, `driver.mbt`, `server.mbt`, `dispatch.mbt` | Fresh CLI passes interpreter/JIT streaming, middleware, trailers, proxy, denial and disconnect tests. Fourteen external services fail at first request instantiation. |

`surface_preview3_test.mbt` checks the command world's 89 functions and 41
explicitly registered type exports across 20 instances. The HTTP inventory
checks 51 functions and 32 explicit type exports across 12 instances, including
base imports and a downstream handler. These are export-presence checks; they
do not invoke every operation or prove its semantics. The inventories come from
the pinned contract JSON and need updating when that pin changes.

`wasi:clocks/types@0.3.0` is intentionally not a host registration: the linker
synthesizes its primitive `duration = u64` type equality. An initial registry-only
probe incorrectly flagged it. The independently validated
[clocks-types.wat](evidence/wasi03-2026-09-18/clocks-types.wat) imports that
interface and successfully invokes `probe` with result `[]`. See
`component/runtime_impl/build_strings.mbt:synthesize_trivial_instance_import`.
There is no demonstrated clocks/types implementation defect.

## Local acceptance results

| Check | Result |
| --- | --- |
| Strict native check, `--warn-list +73 --deny-warn` | Pass |
| Existing native tests before added inventories | 2,536/2,536 pass |
| Native tests including the two inventory tests | 2,538/2,538 pass |
| Stable Component Model, each engine | 23 files, 845 commands pass; zero skips |
| Async 0.3 Component Model, each engine | 24 files, 153 commands pass; zero skips |
| Future-gated Component Model, each engine | 12 files, 387 commands pass; zero skips |
| Freshly built HTTP CLI suite, each engine | Pass, including streaming, URI, trailers, middleware, proxy, concurrency and disconnect recovery |
| Pinned WIT drift verification, command and HTTP | Pass |

These results are not a complete per-function semantic audit. In particular,
registration inventories cannot establish cancellation ordering, all errno
mappings, filesystem races or all socket state transitions. The external
initialization failures below prevent that suite from supplying the missing
behavioral evidence.

## External Preview 3 guest results

Source: [WebAssembly/wasi-testsuite](https://github.com/WebAssembly/wasi-testsuite),
precompiled branch `prod/testsuite-base`, pinned commit
`609c446139956ff30239f87cb18af1dc6128bed2`. The suite contains 55 guests. Guest
binaries and metadata were not rewritten, and no expectations were weakened.

| Execution | Raw upstream result | Audited interpretation |
| --- | --- | --- |
| Wasmoon JIT command adapter | 2 pass, 39 fail, 14 skipped | No verified guest-level successes: both nominal passes are startup errors; 14 HTTP services are outside this adapter. |
| Wasmoon interpreter command adapter | 2 pass, 39 fail, 14 skipped | Same boundary and failure categories as JIT. |
| Separate HTTP first-request probes, both engines | 28/28 requests fail linking | All 14 services per engine fail on `wasi:io/poll@0.2.4`. These probes are not full upstream HTTP operations. |
| Wasmtime 48.0.2 with upstream adapter | 49 pass, 6 fail, 0 skipped | Reference control only, with environmental/adapter failures described below. |

Raw results are retained in [the evidence directory](evidence/wasi03-2026-09-18/).

### Compatible-version linking

The current upstream Rust components mix Preview 3 interfaces with runtime
imports such as `wasi:io/poll@0.2.4` and export both `wasi:cli/run@0.2.0` and
`wasi:cli/run@0.3.0`. Wasmoon's pinned Preview 2 host is 0.2.11. The unchanged
`random.wasm` fails with:

```text
InstantiationFailed("UnknownImport(\"wasi:io/poll@0.2.4\")")
```

The same guest passes with Wasmtime 48.0.2 and `-Wcomponent-model-async -Sp3`.
This establishes a real-world compatibility gap, not a failed random-number
assertion. Track compatible matching and structural/resource checks in ISS-564.
It does not justify blindly aliasing every version or claiming that a missing
0.2.4 import is itself a missing 0.3.0 WIT function.

### Command/HTTP composition

`http-fields`, `http-request`, `http-response` and `http-request-options` are
command components importing `wasi:http/types@0.3.0`. The command CLI installs
only the command world, so they fail with `UnknownImport` for HTTP types even
though the separate HTTP host implements them. Track the opt-in composition
path in ISS-565. This is an embedding/CLI interoperability gap beyond the exact
standard command world's import list.

### False-positive exits and harness boundaries

`cli-exit` and `run-with-err` expect process status 1. Wasmoon exits with status
1 for failed instantiation too, causing both upstream checks to report a false
pass. Direct reruns confirmed the same `UnknownImport` diagnostic. Count neither
as behavioral success. ISS-566 tracks a diagnostic-aware acceptance gate.

The audit's command adapter advertises only `wasi:cli/command`, accounting for
all 14 skips. Separate HTTP probes send a GET to each server and observe its
linking error. They do not supply the upstream mock peers/environment or run
all metadata operations. After linking is repaired, full HTTP adaptation is
still needed: the upstream harness supplies peer addresses via guest environment
variables, while `wasmoon serve` currently has no guest `--env` option; its
startup address is logged on stdout rather than the stderr expected by that
harness. Those are adapter/CLI work, not evidence of HTTP parser defects.

### Reference controls

Wasmtime's six raw failures are not all reference-runtime defects:

- TCP/UDP properties were denied network access because those test metadata
  files did not enable the adapter's socket proposal flag. Both pass when run
  separately with `-Sp3,inherit-network`.
- Directory enumeration saw a `parent.cleanup` symlink left in the shared root
  by another case. It passes with a fresh root containing only `a.txt`/`b.txt`.
- HTTP path-none, sent-receipt and service-URI cases still fail their assertions
  in the raw reference run. This audit does not adjudicate those against WIT.

The isolated control results are saved separately; the original 49/6 result is
not rewritten to imply a new complete sweep. Run external cases with isolated
fixtures and explicit capabilities before drawing behavior comparisons.

## Platform evidence and remaining limitations

Main CI [35297228469](https://github.com/Milky2018/wasmoon/actions/runs/35297228469)
at the audited commit is **not green**. Linux AMD64, Windows AMD64 Clang/MSVC and
Linux ASan/UBSan pass. macOS native tests and HTTP tests pass, but misc JIT
`simd/load_splat_out_of_bounds.wast` exceeds 120 seconds, and subsequent component
steps are skipped. Prior PR CI passed at the identical source tree, but does not
replace acceptance of this failed run. ISS-567 tracks diagnosis; local 100-run
success does not establish its cause or fix it.

TLS failures currently collapse to `TLS-protocol-error`; certificate verification
still rejects bad certificates. Track error-category fidelity in ISS-568.
HTTP/2, HTTP/3, pooling, inbound TLS, upgrades and CONNECT tunnels remain transport
scope choices, not automatically additional mandatory WASI imports. This audit
is limited to the pinned 0.3.0 contracts, not every later 0.3.x revision.

## Reproduction

Build with `./install.sh`, then run:

```sh
moon check --target native --warn-list +73 --deny-warn
moon test --target native
python3 modules/wasmoon/wasi_component/tools/generate_wasi_contracts.py \
  modules/wasmoon/wasi_component/wit \
  modules/wasmoon/wasi_component/wit_contracts_generated.mbt --verify-wit --check
python3 modules/wasmoon/wasi_http/generate_contracts.py --verify-wit --check
python3 scripts/test_wasi_http.py --wasmoon ./wasmoon
```

Run `scripts/run_component_wast.py --suite NAME --dump-failures` for each of
`stable-0.2`, `async-0.3` and `future-gated`, both with and without `--no-jit`.

For the external suite, check out the pinned upstream commit including its
precompiled binaries and install its `test-runner/requirements/prod.txt` in a
virtual environment. With `UPSTREAM` set to that checkout:

```sh
WASI03_ENGINE=jit python "$UPSTREAM/test-runner/wasi_test_runner.py" \
  -t "$UPSTREAM/tests/rust/testsuite/wasm32-wasip3" \
  -r scripts/wasi03_testsuite_adapter.py \
  --json-output-location /tmp/wasi03-jit.json --disable-colors
```

Repeat with `WASI03_ENGINE=interp` and a different JSON output. Inspect diagnostics
in addition to the raw counts. The adapter deliberately does not claim full
HTTP support or suppress the current compatibility failures.

For the synthesized type import:

```sh
wasm-tools parse docs/evidence/wasi03-2026-09-18/clocks-types.wat \
  -o /tmp/clocks-types.wasm
wasm-tools validate --features all /tmp/clocks-types.wasm
./wasmoon component --invoke probe /tmp/clocks-types.wasm
```
