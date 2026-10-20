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
