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

## Pull-request gates

`scripts/audit_component_security.py` validates the stable facade boundary,
validation-before-instantiation ordering, explicit type-size/depth limits,
structured termination policy, resource cleanup seams, and the presence of all
hardening lanes. Its source of truth is `docs/component-hardening.json`.

The blocking Component Model hardening job additionally runs:

```bash
python3 -m unittest discover -s scripts/tests -p "test_component_*.py"
moon test modules/wasmoon/component/runtime_impl/runtime_cleanup_wbtest.mbt
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

## Scheduled campaign

`.github/workflows/component-hardening.yml` runs a larger fixed-seed campaign
weekly and on demand. It retains all reports and failing cases for 90 days. The
pull-request lane uses smaller deterministic budgets so a change cannot bypass
hardening through an empty or impractically expensive campaign.

Native ASan/UBSan execution and direct logical-state assertions are both
required for resource cleanup. The logical tests currently cover host
stream/future endpoints, task ownership metadata, destructor cardinality, and
resource-handle recycling; future resource families must add equivalent
exact-release assertions when introduced.
