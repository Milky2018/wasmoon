# Fingerprint buckets: PR #552 review follow-up

This follows the [PR review](https://github.com/Milky2018/wasmoon/pull/552#issuecomment-6284586968),
adapting the group fingerprint fold from [PR #554 at 727c352f](https://github.com/Milky2018/wasmoon/pull/554/commits/727c352f119f20cf4b2ca2634958922796c64671).
The original [local evidence](README.md) remains historical. The new
[receipt](fingerprints-local.json) describes a **dirty working tree based on
ccb0bfece0de11d438de3d5d5aabc889b9f5a3ec**, not clean CI acceptance.

## Remaining cause and change

The earlier optimization removed registration per allocation and reused
comparison contexts, but first registration still scanned every representative
for every type. Module canonicalization also compared recursive groups pairwise.
Both costs grew with the number of distinct types even with just one GC global.

Both paths now index complete recursive groups by a 64-bit fingerprint. Group
member order, finality, supertypes, composite kinds, function signatures, field
storage and mutability participate. Internal references use member positions;
external references use previously assigned canonical or Store identities.
Negative abstract references use a separate Int64 encoding range, including
safe arithmetic on an invalid Int32 minimum. The hash mixing uses unsigned
operations to avoid signed overflow and shift undefined behavior.

Fingerprints only select candidates. Full recursive-group equivalence decides
every match, including all members of a colliding group. This removes the
unconditional pairwise scans; it is not a cryptographic hash or a worst-case
linear-time guarantee. Unresolved forward/out-of-range references encountered
before validation retain the previous canonicalization behavior, without
indexing outside the identity array or changing assertion/validation phases.

Store buckets own representative graph/member references until Store close.
Both native and wasm close clear them. Scope-owned initialization caching,
snapshot ownership, Store isolation, nested instantiation, rollback restoration,
the terminal-close guard, and temporary comparison-context ownership are retained.
RecGroupIndex remains private; only the fold required by the runtime consumer is
newly public.

## Serial release measurements

The [harness](fingerprints-benchmark.mbt) constructs distinct singleton function
types referring to earlier groups, followed by a struct, zero or one allocating
global, and an empty exported function that is not executed. Construction and
compilation are outside the timed phases. Raw instantiation includes its own
checked validation; canonicalization is timed separately. Each instantiation
creates a fresh Store. Builds use separate output directories, and accepted runs
are serial after build/test workers finish. Every accepted trial is retained.

| Types / GC globals | Old canonicalization, ms | New canonicalization, ms | Old raw instantiation, ms | New raw instantiation, ms |
| --- | --- | --- | --- | --- |
| 1001 / 0 | 119, 114, 120 | 0, 0, 0 | 361, 346, 344 | 2, 1, 1 |
| 1001 / 1 | 118, 122, 121 | 0, 1, 1 | 493, 474, 485 | 1, 1, 1 |
| 2001 / 0 | 724, 695, 859 | 1, 1, 1 | 2053, 2605, 2792 | 2, 2, 2 |
| 2001 / 1 | 914, 790, 748 | 0, 1, 0 | 3454, 3186, 3133 | 3, 3, 3 |
| 5001 / 0 | not measured | 2, 1, 2 | not measured | 6, 6, 6 |
| 5001 / 1 | not measured | 2, 1, 2 | not measured | 7, 8, 7 |

The baseline process was intentionally stopped after all 2001-type trials;
there is no 5001-type baseline result. An earlier exploratory process overlapped
builds and was terminated; none of its timings are used. Millisecond resolution
does not support precise ratios for the new timings. This is a synthetic
comparison, not an execution of the original application's complete workload.

For replay, use the scratch project manifests described in the original README,
replacing its WAT import with `Milky2018/wasm_core/types`. Build this harness
against each checkout in separate directories. Source/binary hashes and all
measurements are in fingerprints-local.json; raw logs and the bounded serial
runner are in ignored `target/pr552-fingerprint/`.

## Regression and local validation

New coverage exercises forced bucket collisions, groups differing after their
first member, external references to equivalent earlier types, shifted recursive
groups, all value-type forms, packed/mutable storage, finality, supertype and
continuation references, and unvalidated-reference handling. Scaling controls
use 1001, 2001 and 5001 types with either a **type-section-only module** or one
allocating global. Existing repeated-global, lifecycle, CHeap and JIT/interpreter
tests remain. The permanent types-only fixture omits the harness's empty function.

A counterfactual omission of wasm `group_buckets.clear()` fails the close test
(0 passed / 1 failed); restoring it passes (1/1). Close during rollback also
asserts that the buckets remain empty.

- Native **2819/2819**, wasm **1344/1344**; the final types-only fixture also
  passed the complete executor package on native (171) and wasm (170).
- Info, fmt, strict checks on both targets with warning 73 denied, and the
  module boundary audit passed.
- Core: native interpreter, actual wasm interpreter and JIT each passed
  **258 files / 62563 assertions**, zero failures or unsupported results.
- Component: each native engine passed **59 files / 1385 commands**, zero skips.
- Full pinned misc: **692 passed / 72 script-only**, zero failures, timeouts,
  unsupported, deferred or harness errors.
- Fresh macOS ASan/UBSan: **201/201**, event-loop checks and both ASan controls
  passed. **Leak detection is unavailable locally; this is not Linux LSan
  acceptance.** MoonBit runtime objects and JIT machine code are outside the
  instrumentation scope.
- Python: **174 tests**, 54 existing platform skips.

Supported-platform CI for the submitted follow-up is still required. ISS-644
remains in progress; no merge is authorized by this local evidence.
