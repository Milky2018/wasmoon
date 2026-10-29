# Live-set materialization

Tracking: [ISS-699](../../issues/ISS-699.md).

After [function-root lowering](function-roots.md), a valid 8192-object initializer
still spends 11.970s building live ranges out of 16.694s compilation. Its effective
3856-sample CPU trace includes bitmap enumeration and sorting under live-set
propagation. Shorter samples have empty call graphs and are not CPU evidence.

A sorted-word enumeration prototype is rejected after 15 alternating cold pairs
across eight inputs: the primary 2048-object case changes only −0.46%, with its
95% interval crossing zero and unchanged RSS. Parse/regex are flat. Some smaller
controls improve by about 0.3–1%, but do not justify the added specialization.
The original bitmap representation and enumeration are restored exactly.

The retained change removes unused output instead. Production range construction
consumes only sorted live-out arrays, yet propagation also serializes every
live-in bitmap. Propagation now returns only live-out; caller-owned live-in sets
retain the same fixed point. Existing diamond, loop, sparse-ID and unreachable
CFG tests inspect those owned inputs directly. No threshold, liveness equation,
register assignment, runtime policy or cache revision changes.

The obsolete opaque `DenseLiveSets` Debug snapshot loses its final producer and
is removed, including its generated interface entries. It had no public
constructor or producer. This is an explicit compiler-library interface cleanup;
other APIs and native/artifact ABIs stay unchanged.

Fifteen alternating cold pairs per input, against 72b8d00, give compiler-only
medians in microseconds and whole-fixture peak RSS in decimal MB:

| Live objects | Before compile | After compile | Before/after RSS | Paired change, 95% interval |
| --- | --- | --- | --- | --- |
| 512 | 94722 | 89937 | 67.2 / 56.6 | −6.30% to −4.46% |
| 1024 | 299605 | 281078 | 190.0 / 164.2 | −7.09% to −4.87% |
| 2048 | 1103195 | 1039341 | 600.1 / 535.7 | −7.17% to −5.26% |

Parse, regex and three crypto controls change by at most about 0.5%; most
intervals include no change. All 240 fresh measured processes produce exactly
identical guest artifacts across both variants, without manifest normalization.
RSS and wall time include parsing and artifact encoding; compiler time excludes
them. This change establishes no invocation speedup.
