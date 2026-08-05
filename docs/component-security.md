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

`scripts/audit_component_security.py` validates the stable facade boundary,
validation-before-instantiation ordering, explicit type-size/depth limits,
structured termination policy, resource cleanup seams, and the platform CI
coverage. Its source of truth is `docs/component-hardening.json`.

Interface isolation is checked from generated `.mbti` semantics rather than
alias spellings. The audit resolves every referenced package alias to its full
import owner, compares owner path segments against the implementation roots,
and scans every generated Wasmoon interface for unreviewed exposure. The
native session and WASI host interfaces are explicit reviewed low-level seams;
adding another implementation-bearing public interface requires an intentional
manifest change.

Validation ordering is checked inside the effective code of
`ComponentRuntime::instantiate_component`: comments and literals are removed,
the function body is isolated with balanced braces, and every linker
instantiation must follow an unconditional function-body-level component
validation. Validation inside a nested control-flow block does not establish
evidence for the gate.

The Linux AMD64 and macOS ARM64 jobs each run the stable 0.2, current 0.3
async, and future-gated suites through both JIT and interpreter execution, in
one platform job rather than separate Component Model jobs.

Neither job runs ASan or UBSan. The gate that did was removed with the
compiler wrapper it depended on; the tests it covered, including
`runtime_cleanup_wbtest.mbt`, still run under `moon test --target native`,
but uninstrumented. Treat leak and use-after-free claims about the component
runtime as unverified by CI until ISS-390 restores that coverage.

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
Wasmtime 45.0.0 release. The installer verifies the official archive SHA-256.
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
