# Unsigned wide multiplication

Tracking: [ISS-680](../../issues/ISS-680.md), part of
[PR 582](https://github.com/Milky2018/wasmoon/pull/582).

## Diagnosis and retained change

Temporary numeric call/loop counters identify the portable 64x64-to-128 helper
as a repeated operation in the AEAD corpus guest: about 2.68 million calls.
These instrumented runs provide operation counts, not performance samples.
An initial static identification of function 73 was wrong: that function is a
cold output-path soft-float helper. The actual helper is function 76.

The generic MilkIR optimizer now recognizes the complete unsigned 32-bit limb
and carry equations and replaces the two halves with existing `Mul` and
`UnsignedMulHigh` operations. Matching follows a bounded expression shape and
requires the same source identities, mask and shift. Near misses remain
unchanged. Normal DCE removes unused intermediate arithmetic. There is no
function-name special case, new target opcode, inlining or changed store,
trap-frame or runtime contract. Codegen revision 21 invalidates revision 20.

The inspected ARM64 helper shrinks from 112 to 48 bytes: one `mul` and one
`umulh` replace the limb products, shifts, masks and carry additions. Its two
stores remain. Wasmtime 49.0.1 retains the limb sequence in this inspected
helper; this does not establish a general compiler or engine advantage.

## Measurements

Local macOS ARM64 release binaries: independently built parent `2fbb5f6d`
(SHA256 prefix `c3c34d796683`) and dirty candidate (`045b10ecdb04`). Five samples
alternate engine order, with serial execution and independent cold caches.
Wasmtime disables parallel compilation and caching; V8 uses optimized eager
serial compilation. No build or profiler runs concurrently with measurements.

`python3 scripts/benchmark_wide_multiply.py --wasmoon <candidate>
--baseline <parent> --samples 5 --scale 100` checks an independently computed
checksum over 1.024 billion pseudorandom products per invocation. Guest SHA256
is `8424993e32bc2704a6f422526d10a72638fa45fa57d71626506968f832cdb04f`.

| Boundary, seconds | Parent | Candidate | V8 / Node | Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| Invocation | 2.074271 | 1.688893 | 1.943423 | not isolated |
| Whole process | not compared | 1.697558 | 1.995239 | 1.992373 |

The candidate reduces invocation by 18.6% and is 13.1% faster than V8 in this
specific control. Wasmtime's whole-process timer must not be presented as its
invocation time. Whole-process RSS is about 6.6 MB for Wasmoon, 13.4 MB for
Wasmtime and 48.8 MB for Node; these include different host runtimes.

Five paired original corpus samples give AEAD invocation 19.591 -> 18.361 ms
and xchacha20 1.521529 -> 1.379884 s, approximately 6.3% and 9.3% reductions.
Stream is unchanged at 5.439 / 5.435 s. Cold compilation is essentially
unchanged in these controls. The very short onetimeauth invocation is too
small for a strong claim. No workload iterations or input bytes are changed.

The full 20000-iteration parse_double property remains unchanged at
1.878481 / 1.882492 s invocation and 809.234 / 812.044 ms compilation; V8
invocation is 0.726084 s. Candidate/Wasmtime whole-process times are
2.770891 / 2.366426 s. This optimization does not solve that remaining gap.
The seven asserted GC controls likewise show no material change.

The complete candidate/Wasmtime screen executes all 70 original algorithm
pairs successfully and confirms fresh compilation in every pair. Its single
sample per case gives geometric means of 1.062 for the guest-reported value
ratio and 1.400 for whole-process wall time. The guest value is the original
printed benchmark metric, not a semantic-result comparison or the CLI invoke
timer. This screen identifies targets; it is not an aggregate speedup over the
parent. Long core_ristretto255, box8 and sign cases have wall ratios about
1.003–1.004; short cases remain disproportionately affected by cold compilation.

## Validation boundary

Public regressions compare JIT/interpreter results at optimization levels 0,
2 and 3, including boundary products, an independent random checksum and
near-miss masks, shifts, signed limbs and mismatched inputs. Structural tests
verify the intended arithmetic rewrite. Ordinary and verification-enabled
native tests pass 3110/3110, wasm 1464/1464. Fresh isolated local ASan/UBSan
passes 316 tests and both positive controls on dirty parent-based sources;
macOS does not provide Linux LSan or actual x64 execution acceptance.
Current release CLI Core passes 258 files / 62563 assertions in each engine;
Component passes 59 files / 1385 commands per engine with zero skips, with
register-allocation, GC and barrier verification enabled. Strict checks on
both targets, 180 Python tests (54 existing platform skips), 44 strict C stubs
and boundary/MSVC-bridge audits pass. Exact-head platform CI remains separate.
