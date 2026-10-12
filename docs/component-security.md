# Component Runtime Security Validation

Wasmoon's Component Model implementation is not a security boundary and has
not completed an independent security audit. Do not use it to execute
untrusted components in production. The checks below reduce regression risk;
they are not a certification or a sandbox guarantee.

## Threat model

The hardening lanes treat component bytes, component text, WIT-shaped
arguments, canonical ABI memory, resource handles, async events, and serialized
host state as untrusted. They check that malformed input returns structured
errors instead of aborting, timing out, or terminating by signal. They also
check that repeated resource operations release logical MoonBit state, because
native leak sanitizers cannot detect entries retained in a reachable `Map`.

The current lanes do not prove memory safety, termination, side-channel
resistance, host capability confinement, or conformance for every Component
Model proposal. The stable 0.2, current 0.3 async, and future-gated conformance
suites remain separate evidence.

## Continuous integration

`scripts/audit_component_security.py` checks generated public interfaces,
reviewed source-pattern budgets, manifest consistency, tool availability and
workflow references. Its configuration is `docs/component-hardening.json`.
These are structural checks, not execution evidence. Termination and unsafe
conversion scans enforce reviewed textual budgets; they do not prove that all
runtime paths return structured errors or that conversions are safe.

Type limits are exercised by `validation_limits_wbtest.mbt` in
`wasm_component/text`: a parsed component at depth 100 or effective size 100000
is accepted, and the next value is rejected. Logical resource release is
exercised by `runtime_cleanup_wbtest.mbt`: repeated stream/future operations
return tables to baseline, cancellation/destructor callbacks run, and failed
instantiation rolls registration back. These tests run in the native suite.
The audit no longer treats error strings, cleanup symbol names or test counts
as proof of these behaviors.

Interface isolation is checked from generated `.mbti` semantics rather than
alias spellings. The audit resolves every referenced package alias to its full
import owner, compares owner path segments against the implementation roots,
and scans every generated Wasmoon interface for unreviewed exposure. The
native session and WASI host interfaces are explicit reviewed low-level seams;
adding another implementation-bearing public interface requires an intentional
manifest change.

The validation boundary check inspects generated interface signatures:
instantiation and registration require abstract `ValidatedComponent` evidence,
which exposes immutable bytes. This checks the public contract, not internal
control flow or the correctness of validation itself.

The Linux AMD64 and macOS ARM64 jobs each run the stable 0.2, current 0.3
async, and future-gated suites through both JIT and interpreter execution, in
one platform job rather than separate Component Model jobs.

A separate Linux ASan/UBSan job runs `scripts/run_sanitizers.py`. Its selected
test closure includes `wasmoon_jit/native_handles_test.mbt`, covering retained
owners, replacement, clearing, parked frames and teardown. The deleted JIT
context-name blacklist did not establish those lifetime properties. Public
ownership API changes still require review; behavioral tests and sanitizer
results are evidence for the cases they execute, not a general lifetime proof.

The component runtime whitebox cleanup suite runs under the ordinary native
test command; it is not itself part of that selected sanitizer closure.
Logical table release and native memory diagnostics remain distinct evidence.

The following tools remain available for explicit local diagnostics, but they
are not pull-request gates or scheduled CI campaigns:

```bash
python3 scripts/component_fuzz.py --mutations 64 --valid-cases 16
python3 scripts/component_differential.py \
  --wasmtime target/component-hardening/wasmtime-oracle/wasmtime \
  --cases 16
python3 scripts/component_stress.py \
  --functions 256 --instance-depth 16 \
  --type-width 128 --type-depth 32 --invocations 32
```

The fuzz harness mutates pinned valid binaries and generates valid typed
invocations. Its seed, tool versions, outcome class, counts, process results,
and retained failing binaries are recorded under
`target/component-hardening/fuzz`.

The differential harness compares successful typed results with the official
Wasmtime 49.0.1 release. The installer verifies the official archive SHA-256.
Timeout, signal, trap, ordinary tool/runtime error, and malformed output remain
distinct outcomes; two failures are never treated as semantic agreement.

The stress harness generates components with many core/lifted functions, deep
exported-instance paths, wide record types, deep type graphs, and repeated
invocation. Every subprocess has a timeout and the report records input sizes,
component sizes, elapsed time, process output, and maximum child resident set
size.

Native ASan/UBSan execution and direct logical-state assertions are both
required for resource cleanup. The logical tests currently cover host
stream/future endpoints, task ownership metadata, destructor cardinality, and
resource-handle recycling; future resource families must add equivalent
exact-release assertions when introduced.

## HTTP host adapter boundary

`wasmoon/wasi_http`, like `wasmoon/wasi_component`, is a Wasmoon-owned low-level
host adapter. Its embedding API intentionally accepts the implementation linker,
resource tables and asynchronous host callbacks so middleware shares resource
identities with the runtime. Its generated interface is explicitly reviewed in
`component-hardening.json`; the portable `wasm_component` modules and stable
`wasmoon/component` facade remain isolated from these implementation owners.
