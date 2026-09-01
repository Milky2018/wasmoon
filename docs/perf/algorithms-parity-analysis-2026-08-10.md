# Wasmoon vs Wasmtime: 70-workload Algorithm Sweep Analysis

> Historical methodology: this report used one warmup and three measured pairs,
> and did not isolate Wasmtime's global cache. New corpus sweeps must clear
> separate Wasmoon and Wasmtime caches per workload and invoke each engine
> exactly once, with no warmup or repeated aggregation. Wasmtime must also run
> with `-C parallel-compilation=n` so its cold-compilation result is comparable
> with Wasmoon's serial compiler.

## Executive summary

This sweep is correct on all 70 workloads: there are no crashes, timeouts, or
wrong results. The performance picture is mixed but favorable to Wasmoon in
several important integer-crypto kernels.

- The guest-reported number is elapsed time, not throughput. Both ratios are
  `Wasmoon / Wasmtime`; therefore **lower is faster** for both guest and wall
  ratios.
- By the raw guest ratio, Wasmoon is faster on 41 workloads, Wasmtime on 28,
  and one workload is at the guest timer floor. With a practical +/-2% band,
  the split is 35 Wasmoon wins, 22 Wasmtime wins, and 13 near ties.
- Requiring both a difference greater than 5% and pair spread no greater than
  5% leaves 26 robust Wasmoon wins and four robust Wasmtime wins:
  `aead_aegis128l`, `aead_aegis256`, `pwhash_scrypt`, and
  `pwhash_scrypt_ll`. The apparent `stream4` and `secretbox_easy2` regressions
  are not reliable under the current harness.
- Wasmoon is especially strong on BLAKE2b, Salsa20/ChaCha-style rotation
  kernels, MAC/hash tests, and `randombytes`. It is about 2.02x faster on
  `generichash2`, 1.95x on `generichash3`, 1.48x on `core3`, and 1.40-1.47x on
  `stream`/`stream2`.
- Wasmtime is 7.6-11.2% faster on AEGIS and 7.8-10.4% faster on scrypt. The
  AEGIS cause is concrete: Wasmoon reloads the linear-memory base 30 times in
  the hot function while Wasmtime loads it once.
- Wasmoon compilation is the largest remaining systemic problem. On eight
  representative modules, Wasmoon needs about 0.69-0.88 seconds versus
  Wasmtime's 0.017-0.030 seconds. Wasmoon register allocation consumes 84-88%
  of compile time in normal captures.
- Wasmoon cache artifacts are compact: 61-92 KiB in the representative set,
  versus 152-233 KiB for Wasmtime serialized modules. This is a storage/load
  advantage, but compact artifacts do not guarantee faster generated code.

## Provenance and methodology

| Item | Value |
| --- | --- |
| Host | Apple M3 Max, arm64, macOS/Darwin 25.5.0 |
| Source HEAD | `ddfa4cc8ec70160c7fc541533b6fa52b37789285` |
| Working-tree fix | `opt_cfg.mbt` jump-threading fix plus regression test; diff SHA-256 `194942104c614ee51f43914dbb0b3848bfe1fc8767333be391fba1fe56a613c5` |
| Wasmoon binary | Built 2026-08-10 18:10:42 +0800, 11,031,192 bytes |
| MoonBit | `moon 0.1.20260807 (4da23f8 2026-08-07)` |
| Wasmtime | `wasmtime 40.0.0 (68a6afd4f 2025-11-22)` |
| Workloads | Pinned `jedisct1/webassembly-benchmarks` artifacts at `7e86d68e99e60130899fbe3b3ab6e9dce9187a7c` |
| Sweep shape | One warmup, three measured pairs, alternating engine order, 300-second timeout |
| Sweep result | 70/70 successful; zero failures |

The upstream benchmarks call `xmain()` repeatedly, time only that region, and
print an average elapsed-time score. Initialization is outside that guest
timer. The upstream report also explicitly says that each Wasm file prints its
own execution time excluding initialization. Consequently:

- `guest ratio = Wasmoon guest time / Wasmtime guest time`;
- `wall ratio = Wasmoon process wall / Wasmtime process wall`;
- values below 1 favor Wasmoon, and values above 1 favor Wasmtime.

The sweep warmed an isolated Wasmoon cache and every measured Wasmoon run hit
its `.cwasm`; all 70 warmups created one artifact and no measured run compiled
a fresh artifact. The runner does not isolate or inspect Wasmtime's cache. This
host had 69 Wasmtime cache files modified during the sweep, and cached short-run
wall times are below standalone `wasmtime compile` times, so the measured
Wasmtime runs were effectively warm as well. Cold compilation is therefore
measured separately below.

## Result overview

The all-workload equal-weight geometric mean guest ratio is 0.894. This is a
descriptive corpus statistic, not an application-level speedup: the workloads
have very different durations and several use randomized test shapes. On the
39 workloads with pair spread no greater than 5% and process duration of at
least 50 ms, Wasmoon has 15 wins beyond 2%, Wasmtime has 15, and nine are within
2%; the geometric mean ratio is 0.925.

### Clear Wasmoon strengths

| Family / examples | Guest ratio | Evidence and likely cause |
| --- | ---: | --- |
| BLAKE2b: `generichash2`, `generichash3` | 0.495, 0.512 | Wasmoon emits dramatically less hot code and uses a much smaller frame. |
| Salsa20 core: `core3` | 0.675 | Hot 160-rotate function is 3,912 B in Wasmoon versus 5,408 B in Wasmtime. |
| Stream ciphers: `stream2`, `stream` | 0.679, 0.712 | Same compact Salsa20-family lowering; long runs make the direction reliable. |
| Random generator: `randombytes` | 0.458 | Stable 2.18x win. The test performs many indirect implementation calls and Salsa20 work; host `random_get` is only used for seeding/stirring. |
| MAC/hash/KDF | 0.610-0.851 for the strongest cases | Integer arithmetic, rotates, and compact straight-line code favor Wasmoon. |
| Long mixed tests: `metamorphic`, `auth5`, `auth7` | 0.739, 0.803, 0.829 | Guest and wall ratios agree and pair spread is low. |

The strongest code-product evidence is `generichash2` function 27, the large
BLAKE2b-style i64-rotate kernel:

| Metric | Wasmoon | Wasmtime |
| --- | ---: | ---: |
| Function code | 6,788 B | 20,480 B |
| AArch64 instructions (code/4) | 1,697 | 5,120 |
| Stack frame evidence | 22 spill slots, 22 spills, 193 reloads | `0x860`-byte frame in disassembly |

For `core3` function 48, the 160-rotate Salsa20 core, Wasmoon emits 3,912 B
with 13 spills and 33 reloads. Wasmtime emits 5,408 B and reserves a
`0x220`-byte frame. These code-size ratios closely track the runtime advantage.

### Clear Wasmtime strengths

| Family / examples | Guest ratio | Evidence and likely cause |
| --- | ---: | --- |
| AEGIS: `aead_aegis128l`, `aead_aegis256` | 1.112, 1.076 | Repeated VMContext memory-base loads in Wasmoon hot code. |
| Scrypt: `pwhash_scrypt`, `pwhash_scrypt_ll` | 1.104, 1.078 | Memory-hard ROMix/BlockMix path dominates; Wasmtime has better outer-loop memory/address code despite worse Salsa hot-code size. |
| Argon2id | 1.038 | Small but stable memory-hard advantage for Wasmtime. Argon2i is within 2%. |
| Scalar multiplication / box cluster | roughly 1.02-1.046 | Mostly small Wasmtime wins; large Ed25519/Ristretto workloads are near parity, so this is not a broad field-arithmetic collapse. |
| `xchacha20` | 1.041 | Stable 4.1% Wasmtime win in a long run; the large module mixes stream, MAC, and utility paths. |

#### AEGIS root cause

Function 30 is the shared AEGIS hot transform in both AEGIS modules.

| Metric | Wasmoon | Wasmtime |
| --- | ---: | ---: |
| Function code | 1,288 B | 1,152 B |
| AArch64 instructions | 322 | 288 |
| Wasmoon allocation edits | 8 spills, 11 reloads | not exported by Wasmtime |
| Linear-memory-base loads | 30 | 1 |

Wasmtime loads the linear-memory base once and keeps it in `x10`. Wasmoon
reissues a `ScalarLoad(... Ptr64, 8)` before table loads/stores throughout the
function. The 29 extra base loads account for most of the 34-instruction code
gap and explain the 7.6-11.2% runtime disadvantage much better than a generic
"bad register allocator" diagnosis. The appropriate fix is cross-block
retention/CSE of immutable VMContext fields with pressure-aware eviction, not a
special AEGIS peephole.

#### Scrypt is a different problem

Scrypt contains the same Salsa permutation where Wasmoon is normally strong.
For `pwhash_scrypt_ll` function 37, Wasmoon emits 3,912 B versus Wasmtime's
5,408 B, yet the whole workload is 7.8% slower. This falsifies the hypothesis
that the Salsa kernel is responsible. The memory-indexed outer path is the
better target: Wasmoon function 43 is 3,600 B versus 3,360 B and carries 32
spills plus 96 reloads. Bounds-check elimination, address-mode formation, and
reload pressure in ROMix/BlockMix should be profiled next.

### Inconclusive or misleading cases

- `secretbox_easy2` chooses a random message length from 1 to 10,000, then
  repeatedly decrypts every truncated length. The amount of work is roughly
  quadratic in an independently seeded random input. Its three paired ratios
  span 1.094-1.364 (24.7% spread), so the reported 1.122 median is not a fair
  same-input engine comparison.
- `stream4` lasts only about 5-7 ms, has 20.2% pair spread, and its guest ratio
  favors Wasmtime while process wall favors Wasmoon. It is dominated by timer
  granularity and fixed process costs.
- `onetimeauth2` reaches zero in the guest timer and is not a performance
  measurement, although its wall result shows Wasmoon's smaller warm-start
  overhead.
- Several other randomized-shape tests (`box_easy2`, `box_easy`, AEAD mutation
  tests, `metamorphic`, `codecs`, and utility tests) need a deterministic WASI
  random source before small differences can be treated as codegen evidence.

## Compilation analysis

Wasmoon phase metrics bypass its JIT cache. Wasmtime was measured with three
standalone `wasmtime compile` invocations per representative module. The
AEGIS-128L Wasmoon number is the median of three clean captures; the other
Wasmoon rows are clean single captures because the internal phase clock is not
the guest benchmark timer.

| Workload | Wasmoon compile | Wasmtime compile | Ratio | Wasmoon regalloc share |
| --- | ---: | ---: | ---: | ---: |
| `aead_aegis128l` | 844 ms | 18.6 ms | 45.5x | 84.3% |
| `aead_aegis256` | 877 ms | 16.9 ms | 51.9x | 83.9% |
| `randombytes` | 691 ms | 16.8 ms | 41.2x | 88.2% |
| `core3` | 743 ms | 18.2 ms | 40.8x | 86.0% |
| `generichash2` | 746 ms | 29.9 ms | 25.0x | 87.0% |
| `secretbox_easy2` | 736 ms | 17.7 ms | 41.5x | 85.5% |
| `pwhash_scrypt_ll` | 738 ms | 17.2 ms | 42.8x | 85.5% |
| `stream` | 751 ms | 17.3 ms | 43.3x | 84.5% |

The dominant compile-time outlier is the large libc-style function around
absolute function 55/56. In AEGIS-128L, function 56 alone spends about 0.56 s
in allocation, produces 15,828 B of code, and records 128 spills and 636
reloads. Register allocation is therefore a compile-time algorithm/scaling
problem even where its final runtime allocation is competitive or superior to
Cranelift's.

The original sweep's `cold warmup - cached median` difference must not be used
as pure compile time. It contains installation, cache serialization, runtime
startup, workload variance, and in two long samples is negative due to normal
run-to-run variation.

## Runtime artifact analysis

Wasmoon uses a compact custom v9 `cwas` artifact containing a compatibility
manifest, import identities, function identities, raw code, symbolic
relocations, source/trap/safepoint metadata, and unwind directives. Wasmtime
serializes an AArch64 ELF relocatable containing `.text`, `.eh_frame`, address
maps, trap/exception tables, Wasm read-only data, engine metadata, and symbol
tables.

| Workload | Wasmoon emitted code | Wasmoon artifact | Wasmtime artifact | Wasmtime / Wasmoon artifact |
| --- | ---: | ---: | ---: | ---: |
| `aead_aegis128l` | 60,528 B | 88,287 B | 238,528 B | 2.70x |
| `aead_aegis256` | 63,720 B | 92,112 B | 238,472 B | 2.59x |
| `randombytes` | 39,616 B | 61,255 B | 155,504 B | 2.54x |
| `core3` | 48,996 B | 69,433 B | 171,784 B | 2.47x |
| `generichash2` | 49,812 B | 71,777 B | 188,288 B | 2.62x |
| `secretbox_easy2` | 51,620 B | 77,069 B | 189,904 B | 2.46x |
| `pwhash_scrypt_ll` | 51,072 B | 73,229 B | 188,696 B | 2.58x |
| `stream` | 51,468 B | 74,943 B | 205,304 B | 2.74x |

Across all 70 workloads, median input size is 39,149 B, median Wasmoon artifact
size is 76,445 B, median Wasmtime artifact size is 205,320 B, and median
Wasmtime `.text` section allocation is 81,920 B. The formats are not directly
equivalent: Wasmtime sections are aligned and contain runtime metadata that
Wasmoon stores differently. Artifact size should therefore be interpreted as
distribution/load footprint, not a pure code-size comparison.

The hot-function comparisons are more diagnostic than whole artifacts:

- AEGIS shows that a smaller Wasmoon artifact can still contain a slower hot
  function because redundant base loads remain.
- BLAKE2b and Salsa20 show that Wasmoon can produce both smaller and faster hot
  functions than Cranelift.
- Large elliptic-curve artifacts (`core_ed25519`, `core_ristretto255`, `sign`)
  are near runtime parity despite very different serialized sizes.

## Recommended next work

1. **Fix immutable VMContext-field reuse across hot blocks.** Target the AEGIS
   function-30 pattern and verify that memory-base loads fall from 30 toward
   one without reserving a physical register globally.
2. **Fix regalloc compile-time scaling.** Function 55/56 is the primary case:
   about 0.56 s of allocation for one function is unacceptable even though the
   resulting code is usable.
3. **Profile memory-hard addressing.** Use scrypt ROMix/BlockMix and Argon2id to
   compare bounds checks, address folding, spills/reloads, and memory-level
   parallelism. The Salsa kernel itself is already better in Wasmoon.
4. **Preserve the wide straight-line allocation strengths.** BLAKE2b and Salsa
   results are valuable regression gates; compile-time improvements must not
   sacrifice their generated-code quality.
5. **Repair the benchmark harness before using small gaps as gates.** Rename
   the parsed metric to `guest_time`, document that lower is better, isolate or
   explicitly disable both engine caches for cold runs, use a deterministic
   WASI random source, raise measured pairs to at least seven for noisy cases,
   and report confidence/spread.
6. **Add symbolized hot-code reporting.** Persist function offsets/names with
   artifacts so sampling can attribute runtime costs rather than presenting
   anonymous JIT addresses.

## Appendix: all 70 measured workloads

Ratios are paired medians and are always `Wasmoon / Wasmtime`; lower is faster.
"Unstable" means the three guest ratios have more than 5% max/min spread.

| Workload | Guest ratio | Wall ratio | Wasmoon wall | Wasmtime wall | Pair spread | Classification |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `randombytes` | 0.4582 | 0.4614 | 0.3293s | 0.7129s | 0.1% | Wasmoon faster |
| `generichash2` | 0.4949 | 0.6079 | 0.0112s | 0.0184s | 0.9% | Wasmoon faster |
| `generichash3` | 0.5116 | 0.5992 | 0.0110s | 0.0182s | 0.6% | Wasmoon faster |
| `kdf` | 0.6102 | 0.6435 | 0.0084s | 0.0131s | 1.8% | Wasmoon faster |
| `core3` | 0.6751 | 0.6750 | 7.5544s | 11.1912s | 3.3% | Wasmoon faster |
| `stream2` | 0.6788 | 0.6790 | 4.6528s | 6.8528s | 2.2% | Wasmoon faster |
| `keygen` | 0.6899 | 0.7052 | 0.0067s | 0.0096s | 2.0% | Wasmoon faster |
| `generichash` | 0.7038 | 0.7102 | 0.0701s | 0.0992s | 1.3% | Wasmoon faster |
| `stream` | 0.7116 | 0.7116 | 5.7011s | 8.0291s | 2.7% | Wasmoon faster |
| `auth2` | 0.7133 | 0.6920 | 0.0062s | 0.0085s | 2.3% | Wasmoon faster |
| `auth3` | 0.7348 | 0.6965 | 0.0062s | 0.0089s | 3.1% | Wasmoon faster |
| `metamorphic` | 0.7391 | 0.7393 | 2.5897s | 3.5034s | 0.7% | Wasmoon faster |
| `chacha20` | 0.7509 | 0.7475 | 0.0764s | 0.1011s | 3.7% | Wasmoon faster |
| `shorthash` | 0.7549 | 0.7043 | 0.0060s | 0.0084s | 5.4% | Wasmoon faster; unstable |
| `hash` | 0.7730 | 0.7396 | 0.0060s | 0.0084s | 6.5% | Wasmoon faster; unstable |
| `kdf_hkdf` | 0.7859 | 0.7874 | 0.1083s | 0.1375s | 1.9% | Wasmoon faster |
| `hash3` | 0.7879 | 0.6953 | 0.0054s | 0.0078s | 12.2% | Wasmoon faster; unstable |
| `auth5` | 0.8031 | 0.8029 | 2.2748s | 2.8292s | 1.2% | Wasmoon faster |
| `secretbox2` | 0.8056 | 0.7244 | 0.0059s | 0.0082s | 19.6% | Wasmoon faster; unstable |
| `auth` | 0.8237 | 0.8211 | 0.0111s | 0.0134s | 3.1% | Wasmoon faster |
| `auth7` | 0.8285 | 0.8281 | 1.2345s | 1.4908s | 1.3% | Wasmoon faster |
| `auth6` | 0.8408 | 0.7221 | 0.0061s | 0.0083s | 13.3% | Wasmoon faster; unstable |
| `siphashx24` | 0.8474 | 0.7062 | 0.0058s | 0.0081s | 0.8% | Wasmoon faster |
| `onetimeauth` | 0.8515 | 0.7142 | 0.0055s | 0.0078s | 3.7% | Wasmoon faster |
| `aead_chacha20poly1305` | 0.8574 | 0.8390 | 0.0240s | 0.0284s | 4.9% | Wasmoon faster |
| `aead_xchacha20poly1305` | 0.8670 | 0.8115 | 0.0244s | 0.0296s | 17.5% | Wasmoon faster; unstable |
| `secretstream_xchacha20poly1305` | 0.9121 | 0.8574 | 0.0182s | 0.0214s | 2.1% | Wasmoon faster |
| `aead_chacha20poly13052` | 0.9163 | 0.8822 | 0.0389s | 0.0435s | 2.6% | Wasmoon faster |
| `verify1` | 0.9216 | 0.9215 | 9.1851s | 10.0095s | 1.7% | Wasmoon faster |
| `onetimeauth7` | 0.9415 | 0.9397 | 0.7385s | 0.7868s | 1.2% | Wasmoon faster |
| `codecs` | 0.9432 | 0.9349 | 0.1496s | 0.1600s | 2.4% | Wasmoon faster |
| `secretbox7` | 0.9479 | 0.9462 | 0.9837s | 1.0399s | 0.8% | Wasmoon faster |
| `secretbox` | 0.9549 | 0.7321 | 0.0062s | 0.0082s | 3.1% | Wasmoon faster |
| `box_seed` | 0.9555 | 0.9242 | 0.0136s | 0.0145s | 1.5% | Wasmoon faster |
| `sodium_utils` | 0.9612 | 0.9607 | 3.7213s | 3.8965s | 4.3% | Wasmoon faster |
| `box_seal` | 0.9808 | 0.9775 | 0.2567s | 0.2627s | 1.5% | within 2% |
| `secretbox_easy` | 0.9819 | 0.7718 | 0.0070s | 0.0088s | 4.6% | within 2% |
| `core_ed25519_h2c` | 0.9830 | 0.9820 | 0.2969s | 0.3032s | 2.4% | within 2% |
| `ed25519_convert` | 0.9902 | 0.9902 | 19.5581s | 19.7518s | 1.7% | within 2% |
| `secretbox8` | 0.9943 | 0.9934 | 2.3556s | 2.3692s | 0.9% | within 2% |
| `core_ristretto255` | 0.9980 | 0.9979 | 189.0965s | 190.9681s | 5.6% | within 2%; unstable |
| `onetimeauth2` | 1.0000 | 0.6969 | 0.0054s | 0.0077s | 0.0% | timer floor |
| `core_ed25519` | 1.0053 | 1.0053 | 168.5598s | 168.3214s | 1.7% | within 2% |
| `sign` | 1.0093 | 1.0093 | 85.6519s | 84.7651s | 2.0% | within 2% |
| `scalarmult_ristretto255` | 1.0121 | 1.0102 | 0.5579s | 0.5527s | 0.5% | within 2% |
| `box_easy` | 1.0133 | 1.0001 | 0.1008s | 0.1008s | 19.2% | within 2%; unstable |
| `sign2` | 1.0179 | 1.0167 | 0.1505s | 0.1485s | 2.2% | within 2% |
| `pwhash_argon2i` | 1.0191 | 1.0181 | 43.0862s | 41.4374s | 4.0% | within 2% |
| `box7` | 1.0208 | 1.0208 | 46.5482s | 45.6003s | 3.7% | Wasmtime faster |
| `scalarmult2` | 1.0213 | 0.9215 | 0.0152s | 0.0167s | 3.7% | Wasmtime faster |
| `scalarmult_ed25519` | 1.0214 | 1.0188 | 0.4835s | 0.4749s | 0.1% | Wasmtime faster |
| `kx` | 1.0234 | 1.0191 | 0.2779s | 0.2731s | 0.6% | Wasmtime faster |
| `scalarmult5` | 1.0270 | 0.9639 | 0.0317s | 0.0328s | 2.9% | Wasmtime faster |
| `stream3` | 1.0294 | 0.7186 | 0.0050s | 0.0069s | 2.9% | Wasmtime faster |
| `box2` | 1.0304 | 1.0040 | 0.0552s | 0.0551s | 1.8% | Wasmtime faster |
| `scalarmult` | 1.0311 | 1.0137 | 0.0953s | 0.0942s | 0.5% | Wasmtime faster |
| `box_easy2` | 1.0340 | 1.0339 | 5.7393s | 6.0065s | 14.1% | Wasmtime faster; unstable |
| `box8` | 1.0362 | 1.0360 | 139.8008s | 135.5412s | 1.2% | Wasmtime faster |
| `pwhash_argon2id` | 1.0384 | 1.0384 | 48.9256s | 46.8422s | 2.2% | Wasmtime faster |
| `scalarmult7` | 1.0404 | 1.0002 | 0.0554s | 0.0554s | 1.6% | Wasmtime faster |
| `scalarmult6` | 1.0409 | 0.9820 | 0.0317s | 0.0322s | 2.5% | Wasmtime faster |
| `xchacha20` | 1.0412 | 1.0409 | 1.5332s | 1.4729s | 1.0% | Wasmtime faster |
| `box` | 1.0445 | 1.0166 | 0.0542s | 0.0538s | 1.2% | Wasmtime faster |
| `scalarmult8` | 1.0462 | 1.0448 | 1.4297s | 1.3684s | 0.8% | Wasmtime faster |
| `aead_aegis256` | 1.0758 | 1.0720 | 0.9014s | 0.8389s | 2.6% | Wasmtime faster |
| `pwhash_scrypt_ll` | 1.0783 | 1.0780 | 9.8556s | 9.1306s | 3.3% | Wasmtime faster |
| `stream4` | 1.0972 | 0.7105 | 0.0050s | 0.0070s | 20.2% | Wasmtime faster; unstable |
| `pwhash_scrypt` | 1.1039 | 1.1039 | 149.2275s | 136.1728s | 2.7% | Wasmtime faster |
| `aead_aegis128l` | 1.1122 | 1.1078 | 0.8375s | 0.7540s | 1.8% | Wasmtime faster |
| `secretbox_easy2` | 1.1217 | 1.1209 | 4.2359s | 3.4376s | 24.7% | Wasmtime faster; unstable |
