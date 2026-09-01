# Algorithms Single-Run Performance Evidence

> Historical methodology: this report used a warmup and measured cached
> execution. New corpus sweeps must clear separate Wasmoon and Wasmtime caches
> per workload and invoke each engine exactly once, with no warmup or repeated
> aggregation. Wasmtime must also run with `-C parallel-compilation=n` so its
> cold-compilation result is comparable with Wasmoon's serial compiler.

This report compares the current Wasmoon AArch64 JIT with Wasmtime across all
70 workloads in `examples/algorithms`. Ratios are Wasmoon divided by Wasmtime;
values below 1 mean Wasmoon was faster for that observation.

Per the review decision for ISS-266, each workload used one warmup and one
measured pair. These are direct single-run ratios, not averages, medians, or
statistical bounds.

## Provenance

| Item | Value |
| --- | --- |
| Wasmoon commit | `fe00c0108ea830fb9c17c7e889b633b8c610d9b9` |
| Host | Apple Silicon, `arm64`, `ARM64_T6031` |
| OS | Darwin 25.5.0, macOS arm64 |
| MoonBit | `moon 0.1.20260717 (438c06f 2026-07-17)` |
| Wasmtime | `wasmtime 40.0.0 (68a6afd4f 2025-11-22)` |
| Python | 3.14.5 |
| Benchmark shape | one warmup, one measured pair |
| Wasmoon cache | isolated per workload; zero fresh measured compilations |
| Timeout | 300 seconds per engine invocation |

The command was:

```sh
python3 scripts/benchmark_algorithms_parity.py \
  --wasmoon ./wasmoon \
  --wasmtime wasmtime \
  --workloads-dir examples/algorithms \
  --summary-file target/perf-benchmarks/algorithms/final-single-run-20260724/summary.json \
  --markdown-file target/perf-benchmarks/algorithms/final-single-run-20260724/summary.md \
  --iterations 1 \
  --warmup 1 \
  --timeout-sec 300 \
  --value-ratio-threshold 1.15 \
  --wall-ratio-threshold 1.20
```

All 70 workloads completed without a timeout or runtime failure. Two direct
pairs exceeded the diagnostic thresholds: `aead_aegis128l` and
`aead_aegis256`.

`onetimeauth2` reported zero guest ticks in both engines, so its guest-value
ratio is not measurable. Its wall ratio remains valid. Treating `0 / 0` as
`1.0` would overstate what this sample established.

## Direct Ratios

| Workload | Value ratio | Wall ratio | Status |
| --- | ---: | ---: | --- |
| `aead_aegis128l` | 1.3498 | 1.3434 | perf gap |
| `aead_aegis256` | 1.3640 | 1.3579 | perf gap |
| `aead_chacha20poly1305` | 0.8775 | 0.8258 | ok |
| `aead_chacha20poly13052` | 1.0615 | 1.0067 | ok |
| `aead_xchacha20poly1305` | 0.8931 | 0.8496 | ok |
| `auth` | 0.8827 | 0.7928 | ok |
| `auth2` | 0.7343 | 0.7299 | ok |
| `auth3` | 0.7341 | 0.6465 | ok |
| `auth5` | 0.8586 | 0.8585 | ok |
| `auth6` | 0.8142 | 0.6315 | ok |
| `auth7` | 0.8867 | 0.8858 | ok |
| `box` | 1.0419 | 1.0039 | ok |
| `box2` | 1.0383 | 1.0113 | ok |
| `box7` | 1.0381 | 1.0381 | ok |
| `box8` | 1.0583 | 1.0583 | ok |
| `box_easy` | 1.0339 | 1.0216 | ok |
| `box_easy2` | 1.0769 | 1.0765 | ok |
| `box_seal` | 1.0088 | 1.0058 | ok |
| `box_seed` | 0.9603 | 0.8741 | ok |
| `chacha20` | 0.7897 | 0.7816 | ok |
| `codecs` | 0.9162 | 0.9100 | ok |
| `core3` | 0.6997 | 0.6998 | ok |
| `core_ed25519` | 1.0499 | 1.0499 | ok |
| `core_ed25519_h2c` | 0.9140 | 0.9147 | ok |
| `core_ristretto255` | 1.0003 | 1.0003 | ok |
| `ed25519_convert` | 0.9912 | 0.9912 | ok |
| `generichash` | 0.8237 | 0.8187 | ok |
| `generichash2` | 0.5413 | 0.6263 | ok |
| `generichash3` | 0.5480 | 0.6227 | ok |
| `hash` | 0.7014 | 0.7532 | ok |
| `hash3` | 0.7838 | 0.7194 | ok |
| `kdf` | 0.6620 | 0.7152 | ok |
| `kdf_hkdf` | 0.8622 | 0.8581 | ok |
| `keygen` | 0.7041 | 0.6820 | ok |
| `kx` | 1.0201 | 1.0167 | ok |
| `metamorphic` | 0.7799 | 0.7800 | ok |
| `onetimeauth` | 0.8438 | 0.6988 | ok |
| `onetimeauth2` | n/a | 0.7197 | zero guest ticks |
| `onetimeauth7` | 0.9806 | 0.9787 | ok |
| `pwhash_argon2i` | 1.0619 | 1.0619 | ok |
| `pwhash_argon2id` | 0.9529 | 0.9529 | ok |
| `pwhash_scrypt` | 1.0941 | 1.0941 | ok |
| `pwhash_scrypt_ll` | 1.0857 | 1.0947 | ok |
| `randombytes` | 0.4836 | 0.4858 | ok |
| `scalarmult` | 0.9915 | 0.9754 | ok |
| `scalarmult2` | 0.9972 | 0.9272 | ok |
| `scalarmult5` | 1.0499 | 1.0003 | ok |
| `scalarmult6` | 1.0707 | 1.0043 | ok |
| `scalarmult7` | 1.0440 | 1.0113 | ok |
| `scalarmult8` | 1.0424 | 1.0404 | ok |
| `scalarmult_ed25519` | 1.0254 | 1.0237 | ok |
| `scalarmult_ristretto255` | 0.9740 | 0.9718 | ok |
| `secretbox` | 0.8073 | 0.7368 | ok |
| `secretbox2` | 1.0915 | 0.6924 | ok |
| `secretbox7` | 1.0025 | 1.0000 | ok |
| `secretbox8` | 0.9877 | 0.9867 | ok |
| `secretbox_easy` | 1.0120 | 0.7846 | ok |
| `secretbox_easy2` | 1.0027 | 1.0021 | ok |
| `secretstream_xchacha20poly1305` | 0.9391 | 0.9167 | ok |
| `shorthash` | 0.7887 | 0.6471 | ok |
| `sign` | 0.9915 | 0.9915 | ok |
| `sign2` | 1.0008 | 0.9995 | ok |
| `siphashx24` | 0.7270 | 0.6677 | ok |
| `sodium_utils` | 0.9752 | 0.9744 | ok |
| `stream` | 0.7093 | 0.7093 | ok |
| `stream2` | 0.6781 | 0.6782 | ok |
| `stream3` | 0.9474 | 0.7060 | ok |
| `stream4` | 0.9367 | 0.7333 | ok |
| `verify1` | 0.9710 | 0.9709 | ok |
| `xchacha20` | 1.0355 | 1.0349 | ok |

## Correctness Gates

The allocation fixes required before this run passed:

- regalloc 70/70, AArch64 target 207/207, x64 target 99/99, and
  machv_regalloc 6/6;
- native tests 2321/2321;
- recursive interpreter and JIT WAST runs, each 258/258 files and 62563 tests;
- `moon check --target all --warn-list +73`;
- reusable-module boundary audit.
