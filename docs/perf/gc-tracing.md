# Independently owned native graph traces

Tracking: [ISS-694](../../issues/ISS-694.md).

An earlier generational regex2100 diagnostic examined137 million candidate edges,77 million already
seen. Discovery stored a32-bit visit epoch per identity; interleaved read-only
traces overwrote each other's epochs. A public reproduction returned duplicate
identities `[4,2,2]` rather than `[4,2]`. Collector marking separately touched every
object header. Instrumented profiles identify these costs; they are not timing.

## Ownership and lifetime

Each trace now owns sparse1024-bit visited pages through a two-level directory.
Its existing BFS worklist and public object order are retained. Ownership lists
free every partially allocated directory/page after native allocation failure.
Read-only discovery never changes collector marks. Incomplete discovery cannot
publish any marks or permit collection.

Identity pages hold a separate128-byte collector bitmap instead of the4KiB visit
array. Every mark writer, query, seed, clear, sweep, rollback and verifier uses
this one representation; header flags remain reserved. Completed graph marks
are combined by bitwise union. Young marks exclude mature identities, including
mixed words/pages. Dead-header writes and precise-root/auxiliary semantics remain.

Structural epochs advance before reclamation; page incarnations distinguish
retired/recreated identity storage. Unchanged epochs admit early duplicate checks
and preflighted page-wise mark union. Older full graph handles resolve each live
identity through the original checked fallback. Young handles retain their
existing collector-attempt scope. No physical address crosses a safepoint or
reentry, and MoonBit still owns collection policy and root coordination.

All56 generated-code native layout fields are identical before/after, despite
the private metadata change. Every compared guest artifact is byte-identical;
there is no public API, payload representation or codegen revision change.

## Controlled comparison

Parent116d11e binary`1dd20ebb13b7`; explicitly dirty working-tree candidate
`243660fce4df`. Five serial alternating cold pairs across14 asserted workloads
and155 fresh processes include a separate per-object-marking ablation for three
cases. Compilation, invocation and whole-process peak RSS are separate. MB is
decimal; no new cross-engine ratio is inferred.

| Workload | Parent invoke | Change invoke | Parent/change peak RSS |
| --- | ---: | ---: | ---: |
|2M retained nodes,100K churn |109.94ms|100.16ms|311.2/291.3MB|
| Regex GC n2100 |17.331s|16.771s|2113/1983MB|
| Regex GC n700 |1.439s|1.433s|316.2/301.7MB|
| Parse-double20k |1.620s|1.616s|280.9/274.6MB|

Invocation ratio95% intervals are0.8876–0.9483 for the large graph and
0.9653–0.9708 for regex2100. Regex700, parse, tiny/dense scalar/vector arrays,
small surviving graphs and large static/mutated reference arrays do not establish
an invocation change. Allocation-placement outliers remain in the RSS samples;
RSS medians are not deterministic capacity guarantees. The large-graph RSS ratio
interval is0.9359–0.9362; regex2100 is wider at0.9172–0.9842.

Keeping the new storage but disabling batch marks gives regex2100 a17.059s
median; batch/per-object invocation ratio interval is0.9786–0.9862. The two smaller
ablation controls do not establish an execution benefit. Compilation medians are
385/376ms for regex2100 and796/778ms for parse, with ratio intervals below1;
other compilation controls include no change. This does not establish a new
compiler algorithm improvement or an aggregate corpus speedup.

## Validation boundary

Seven public regressions protect independent traces, mark union/clearing,
read-only discovery, partial faults, rollback identity reuse, sparse directory
growth and exact young word/page boundaries. One private fixture models retired
identity history with two real payloads, avoiding a million allocations under
the verifier. Directory/chunk/page growth failures cannot publish partial marks.
The earlier40-node failure test still covers queue growth after32 discovered
objects, in addition to the new metadata allocation boundaries.

Deliberately replacing mark union with assignment loses a live object; omitting
incarnation reset misses a reused identity's new child. Both actual assertions
fail, and exact restoration passes. Full native3160 ordinary/verified, Wasm1465,
strict both, info/fmt, C45 and boundary/MSVC gates pass. Final clean integration,
sanitizer and exact-head platform acceptance remain separate gates. Raw fixtures,
logs, profiles, samples, sources and caches stay in automatically cleaned OS
scratch workspaces.
