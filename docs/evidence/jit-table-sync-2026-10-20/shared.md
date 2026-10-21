# Shared native table storage for issue #553

The native interpreter, host Table API, and JIT now use one native table
descriptor after Store admission. The managed construction array is discarded
at that boundary. Entry writes, bulk operations, growth, and close update this
descriptor directly; suspension and host calls do not upload or download tables.
This supersedes the revision-based mirror protocol described in
[the earlier local evidence](local.md).

This is one interpreter with different storage backends, not separate native
and wasm instruction implementations. Both targets use the same executor and
the same Table admission, element-kind checks, unsigned bounds, declared limits,
growth checks, and terminal lifecycle. Only the backing operations differ:

| Target | Table backing |
| --- | --- |
| wasm | Managed MoonBit array |
| native, before Store admission or explicitly `use_jit=false` | Managed MoonBit array |
| native, admitted for native interoperability | Shared native descriptor and entries |

Function table entries contain stable Store function addresses. A Store-owned
registry resolves them to active native entry points at native reads and calls;
module-local function/type numbering does not become table identity. Callable
registration publishes sorted lookup views, rather than refreshing every table
at each execution boundary. The WAST selective compiler also follows table
initializer expressions, so their function references have executable entries.

Native entries retain GC words, including external-wrapper identity metadata.
Root tracing reads the authoritative backing without creating external wrappers.
The private reference arena is shared by the Store and native table codecs and
has no back-reference to the Store. Tables therefore do not create a new
Store/Table reference cycle. Native close invalidates bound context aliases;
growing a shared descriptor updates those aliases without copying another table.

Native lowering uses table runtime helpers for function-reference resolution and
indirect-call checks. The artifact code-generation revision is advanced to
`direct-vcode-10`; artifacts generated for the previous table ABI are rejected.

The direct visibility regression failed against `bdd6b7c6`: a host `I31(7)` write
left the native entry at zero instead of 15. An ownership regression also failed
while the first shared implementation captured the whole Store. Both are kept
as executable regressions. Additional coverage exercises active host callbacks,
parked cross-module readers, growth, quotas, GC roots, external-wrapper identity,
and terminal close. The existing Core table-initializer fixture protects selective
compilation of referenced functions.

Validation and measurements are recorded in [shared-local.json](shared-local.json).
They describe a dirty local working tree based on `bdd6b7c6`, not clean CI or
cross-platform acceptance. Historical receipts remain unchanged. Temporary source
workspaces, sanitizer builds, benchmark builds, and corpus scratch output are
removed after use; the repository's `_build` receives only Moon-tool output.

Local macOS ARM64 validation passed: native 2840/2840, wasm 1347/1347, strict
checks, generated interfaces, formatting, module boundaries, 43 C stubs with
warnings denied, and 175 Python tests with 54 existing platform skips. Core
passed on JIT, native interpreter, and actual wasm interpreter: each 258 files
and 62563 assertions. Component passed on both native engines: each 59 files,
1385 commands, zero skips. Full misc execution passed 692 verdicts and 72
assertion-free scripts, with no failures or deferred cases. Fresh ASan/UBSan
passed 210 tests and both ASan positive controls. Local LSan is unavailable.

The million-iteration loop remains 3–4 ms with 976 cooperative yields for unused
tables of 0, 100, 1000, and 10000 entries. Three serial processes ran three trials
per configuration after builds and corpus execution finished. A separate public
host Table API control measures one million read/write pairs: managed backing
takes 9–10 ms and shared native backing 26–29 ms. This isolates a real per-element
codec/access cost; it is not an old-versus-new interpreter benchmark or evidence
that all table workloads improve. Shared storage removes boundary copying and
duplicate authority while retaining this tradeoff.

## Late native heap activation follow-up

Review of `a0bc63df182c330c925756ec9212f414fb8cca44` found that the new codecs
captured an immutable heap selector while `enable_c_heap()` updated a separate
Store field. This is an introduced regression: valid heap references could be
read from the empty managed heap, GC returned -1, and array exception payloads
could be classified as structs. Three public-API regressions reproduced these
failures before the repair.

The native reference arena now owns the only mutable CHeap slot. Store
allocation, type metadata, budgets, rollback, tracing and reference codecs all
read that slot. Late activation publishes it only after budget binding succeeds;
close clears the same slot. No Store back-reference is added. Both table
admission orders, repeated activation, array/struct identity, GC reclamation,
exception payload decoding and terminal heap release are covered.

Local follow-up validation passed native 2843/2843, wasm 1347/1347, strict checks,
and fresh macOS ASan/UBSan 213/213 with both ASan controls detected. The original
JSON receipt remains historical; it is not acceptance of this follow-up. Linux
LSan and final-head CI remain pending.

## CLI binding follow-up

After the heap repair, an actual `run --invoke value` probe with an array table
initializer still trapped with `null reference`, while interpreter mode returned
42. The CLI had retained a separate legacy table initializer: it rewrote each
shared entry, converting non-function references to null. This was a second
migration regression, independent of the stale heap selector.

CLI preparation now only binds the authoritative Store descriptors. A permanent
regression first failed with `Null != ArrayRef(0)` and now verifies that repeated
binding preserves array references, Store function identities and native mutation
revisions. The real CLI returns 42 in both modes; the corresponding Component
script passes two commands in each engine mode. Temporary fixtures were removed.

Final local native tests pass 2844/2844. Core JIT passes 258 files/62563 assertions;
all three Component suites pass on each native engine, each 59 files/1385 commands
with zero failures or skips. Wasm 1347/1347 and the fresh 213-test sanitizer closure
were validated for the heap repair; this follow-up changes only native CLI setup
and its test. Final-head cross-platform CI remains pending.
