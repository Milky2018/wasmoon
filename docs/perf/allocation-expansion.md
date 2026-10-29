# Shared struct reservation expansion

Tracking: [ISS-702](../../issues/ISS-702.md).

The direct heap budget already limits large allocation expansions. Its fallback
still emits a shared reservation call, stores, a slow/join diamond and root
state for every eligible struct. A large straight-line initializer consequently
multiplies target CFG state even after direct heap expansion is disabled.

An independent estimated-work allowance bounds that shared expansion too:
32 units per reservation plus four per field, with a 1200-unit function limit.
This is separate from the existing 512-unit direct heap allowance. Over-budget
functions use the existing complete collecting constructor; no runtime API,
layout, quota, GC, trap or initialization contract changes. Unknown layouts keep
the same fallback. Codegen revision24 rejects revision23 caches; format12/ABI8
stay unchanged. Public tests exercise both target selectors, and private tests
check the budget boundary and unchanged source IR.

Fifteen alternating cold compiler pairs per input compare against 8421e726.
Compiler time excludes parsing/encoding; peak RSS is the whole fixture process.

| Live objects | Before/after compile | Before/after peak RSS | Paired compiler change, 95% interval |
| --- | --- | --- | --- |
| 512 | 90.642 / 45.848 ms | 56.6 / 26.2 MB | −49.68% to −49.17% |
| 1024 | 281.808 / 134.174 ms | 164.2 / 44.9 MB | −52.59% to −51.78% |
| 2048 | 1042.941 / 439.833 ms | 535.7 / 84.2 MB | −58.16% to −57.43% |

The largest artifact shrinks 1.398→0.794 MB. Parse/regex compilation improves
about 1.3/1.7%; the three crypto controls have no established change and identical
artifacts after only revision23/24 manifest normalization.

The tradeoff is real. Five separate invocation pairs, repeating initialization
64 times, change the 128/512/2048-object cases by roughly +18/+30/+66%; the
largest invocation is 3.306→5.532 ms. The compiler saving is about 0.61 seconds
per fresh compilation, but cached repeated initialization sacrifices throughput.
Parse and regex700/2100 invocation intervals include no change. Other controls
are reported separately; none establishes a universal runtime improvement.
This bound controls compiler resources instead of claiming a faster constructor.
A shared specialized construction stub needs a separate ownership/ABI design.

Measurements use frozen prototype binaries; clean committed rebuild, complete
integration and platform acceptance are independent gates. Raw profiles, dumps,
reports and caches are temporary rather than repository contents.
