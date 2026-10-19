# Exception registry migration: local evidence

These receipts describe the dirty macOS ARM64 working tree after commit
`d9279052ed577537da1991ba5000bea26cd55760`. The implementation is not committed,
pushed or accepted by CI. The installed stable toolchain is unchanged.

The MoonBit `ExceptionState` owns the identity counter, immutable tag layouts,
live snapshot map, mark bits, admission decisions, sealing and reclamation.
The native adapter retains this state through RC; state and payload leases
never own the adapter. The former native registry, layout list and manual
arena reference count have been removed. Native handlers and jump buffers,
payload copying, root registrations and physical lease destruction remain C.
This is a registry migration, not removal of all native exception machinery.

## Verification

- Native: **2729/2729**, including three new public registry ownership/failure
  tests and one JIT callback failure/reuse test.
- Strict native MoonBit checking with warning 73 and warnings denied passes;
  all **43** native C stubs compile with warnings denied.
- Fresh ASan/UBSan: **171/171**, event-loop fixture and both independent ASan
  positive controls pass. macOS has `leak_detection=false` and
  `lsan_probe=not_applicable`; this does not establish Linux LSan acceptance.
- Core WAST: **258/258 files, 62563 assertions per engine**.
- Component WAST, both engines: stable **23 files / 845 commands**, async
  **24 / 153**, future **12 / 387**, with no skipped commands.
- WASI 0.3 HTTP-contract: **110/110**. Its receipt identifies the CLI digest.
- Existing script tests: **172**, with **54** platform-dependent skips.
  Module boundary and generated MSVC bridge checks also pass. Windows execution
  and Linux leak detection have not been run for this working tree.

The new public ownership test lets both the arena and heap wrappers expire
while a context retains the registry; the last context release returns the
native heap live count to its baseline. Other tests deny payload allocation,
root-registration allocation and root-buffer allocation independently, require
quota rollback, reject stale identities and require fresh identities after
release. A second arena cannot bind until the previous arena's last root lease
is gone. Removing that last-lease pointer clearing makes the new regression
fail (`root-lease-negative-control.log`); the mutation was restored.

The JIT regression arms native failure inside a host callback, then captures
an exception. It covers four real allocation sites: active payload copy,
snapshot payload copy, root registration and root buffer. The managed callback
has completed its cleanup before the native trap; the next invocation succeeds
on the same context. This runs in both native and isolated sanitizer gates.

`source-manifest.json` records the changed source hashes, CLI digest and exact
source-copy comparisons against the sanitizer workspace. Every comparison is
true. Generated C excerpts show borrowed `FuncRef` state/request parameters,
borrowed snapshot-address lookup and mark updates without allocation. Native
control transfer happens only after the insertion callback returns.

## Performance and limits

`comparison.json` records eleven serial, alternating paired CLI samples after
one warmup pair. Times include startup, loading, JIT compilation, execution and
teardown, not isolated runtime operations. The baseline is the CLI used for
the preceding GC migration; both binary digests and workload hashes are saved.
The ordinary allocation workload is
[`word-2000000.wat`](../native-runtime-policy-2026-10-16/word-2000000.wat).

| Workload | Baseline median | Candidate median | Change |
| --- | ---: | ---: | ---: |
| Capture 20k distinct exception snapshots | 6.55ms | 7.53ms | +15.0% |
| Rethrow one snapshot 200k times | 22.77ms | 24.08ms | +5.7% |
| Allocate 2M word structs | 132.23ms | 131.40ms | -0.6% |

An initial implementation measured about 30% overhead in the snapshot case
and allocated two RC reservation objects per snapshot. Admission now calls the
existing atomic quota primitives from MoonBit; the payload embeds two physical
reservation records and reuses their existing close primitive. The charge
amounts come from MoonBit. No native quota decision or byte formula was
restored. `Map.each` and `Map.retain` avoid temporary per-entry iterator tuples
and a separate dead-entry array. Intermediate measurements are retained rather
than relabeled as final results.

The remaining exception-heavy overhead is real in these samples; it is not a
zero-cost migration or a universal speedup. The registry uses a managed map
with entry objects, rather than the old packed native array. This also avoids
a registry indexed by ever-growing historical identities and supports direct
snapshot retirement without shifting all later entries. The current samples
do not isolate the remaining overhead's causes. Further tuning and platform
acceptance remain open in ISS-637.

The private per-context runtime state adds one closed factory function pointer
(8 bytes on these 64-bit targets) for lazy standalone exception state creation.
It captures no Store or arena, is installed per context, and requires no global
mutable factory. Generated-code-visible module layout offsets are unchanged;
the storage-size regression explicitly records the private 8-byte increase.
