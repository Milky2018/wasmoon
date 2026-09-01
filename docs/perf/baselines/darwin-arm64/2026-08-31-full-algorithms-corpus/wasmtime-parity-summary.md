# Algorithms Benchmark: Wasmoon vs Wasmtime

- Summary file: `docs/perf/baselines/darwin-arm64/2026-08-31-full-algorithms-corpus/wasmtime-parity-summary.json`
- Cold isolated cache root: `<sweep-artifacts>/jit-cache`
- Runs per engine and workload: `1`
- Total workloads: `70`
- OK: `39`
- Failures: `0`
- Perf gaps: `31`

| Workload | Status | Value Ratio | Wall Ratio | Wasmoon Fresh Compile | Wasmtime Fresh Compile |
|---|---|---:|---:|---:|---:|
| `examples/algorithms/aead_aegis128l.wasm` | ok | 1.0359 | 1.1154 | True | True |
| `examples/algorithms/aead_aegis256.wasm` | ok | 1.0472 | 1.1233 | True | True |
| `examples/algorithms/aead_chacha20poly1305.wasm` | perf_gap | 0.8716 | 2.2391 | True | True |
| `examples/algorithms/aead_chacha20poly13052.wasm` | ok | 0.9081 | 1.7329 | True | True |
| `examples/algorithms/aead_xchacha20poly1305.wasm` | perf_gap | 0.9358 | 2.2053 | True | True |
| `examples/algorithms/auth.wasm` | perf_gap | 0.9265 | 3.0440 | True | True |
| `examples/algorithms/auth2.wasm` | perf_gap | 0.8597 | 3.1969 | True | True |
| `examples/algorithms/auth3.wasm` | perf_gap | 0.5721 | 3.0894 | True | True |
| `examples/algorithms/auth5.wasm` | ok | 0.7937 | 0.8098 | True | True |
| `examples/algorithms/auth6.wasm` | perf_gap | 1.0820 | 2.9167 | True | True |
| `examples/algorithms/auth7.wasm` | ok | 0.8275 | 0.8564 | True | True |
| `examples/algorithms/box.wasm` | perf_gap | 1.0566 | 2.3460 | True | True |
| `examples/algorithms/box2.wasm` | perf_gap | 0.9982 | 2.2657 | True | True |
| `examples/algorithms/box7.wasm` | ok | 0.9636 | 0.9656 | True | True |
| `examples/algorithms/box8.wasm` | ok | 0.9916 | 0.9923 | True | True |
| `examples/algorithms/box_easy.wasm` | ok | 0.9895 | 1.7826 | True | True |
| `examples/algorithms/box_easy2.wasm` | perf_gap | 1.0683 | 1.0858 | True | True |
| `examples/algorithms/box_seal.wasm` | ok | 0.9008 | 1.2700 | True | True |
| `examples/algorithms/box_seed.wasm` | perf_gap | 0.9613 | 3.6046 | True | True |
| `examples/algorithms/chacha20.wasm` | ok | 0.7911 | 1.2024 | True | True |
| `examples/algorithms/codecs.wasm` | ok | 0.9335 | 1.2017 | True | True |
| `examples/algorithms/core3.wasm` | ok | 0.6487 | 0.6533 | True | True |
| `examples/algorithms/core_ed25519.wasm` | ok | 0.9366 | 0.9377 | True | True |
| `examples/algorithms/core_ed25519_h2c.wasm` | ok | 1.0215 | 1.5294 | True | True |
| `examples/algorithms/core_ristretto255.wasm` | ok | 1.0072 | 1.0080 | True | True |
| `examples/algorithms/ed25519_convert.wasm` | ok | 0.9832 | 0.9900 | True | True |
| `examples/algorithms/generichash.wasm` | ok | 0.7360 | 1.0894 | True | True |
| `examples/algorithms/generichash2.wasm` | ok | 0.5080 | 1.6812 | True | True |
| `examples/algorithms/generichash3.wasm` | ok | 0.4860 | 1.7432 | True | True |
| `examples/algorithms/hash.wasm` | perf_gap | 0.8699 | 3.5986 | True | True |
| `examples/algorithms/hash3.wasm` | perf_gap | 0.6981 | 2.7387 | True | True |
| `examples/algorithms/kdf.wasm` | ok | 0.6551 | 1.8257 | True | True |
| `examples/algorithms/kdf_hkdf.wasm` | ok | 0.7865 | 1.1950 | True | True |
| `examples/algorithms/keygen.wasm` | perf_gap | 0.7445 | 2.7261 | True | True |
| `examples/algorithms/kx.wasm` | ok | 0.9625 | 1.2989 | True | True |
| `examples/algorithms/metamorphic.wasm` | ok | 0.7745 | 0.8012 | True | True |
| `examples/algorithms/onetimeauth.wasm` | perf_gap | 0.8667 | 2.9003 | True | True |
| `examples/algorithms/onetimeauth2.wasm` | perf_gap | 1.0000 | 2.3371 | True | True |
| `examples/algorithms/onetimeauth7.wasm` | ok | 0.9176 | 0.9604 | True | True |
| `examples/algorithms/pwhash_argon2i.wasm` | ok | 0.9852 | 0.9868 | True | True |
| `examples/algorithms/pwhash_argon2id.wasm` | ok | 1.0281 | 1.0297 | True | True |
| `examples/algorithms/pwhash_scrypt.wasm` | perf_gap | 1.0639 | 1.0638 | True | True |
| `examples/algorithms/pwhash_scrypt_ll.wasm` | perf_gap | 1.0594 | 1.0647 | True | True |
| `examples/algorithms/randombytes.wasm` | ok | 0.4572 | 0.5202 | True | True |
| `examples/algorithms/scalarmult.wasm` | ok | 0.9839 | 1.8334 | True | True |
| `examples/algorithms/scalarmult2.wasm` | perf_gap | 0.9868 | 3.4857 | True | True |
| `examples/algorithms/scalarmult5.wasm` | perf_gap | 0.9863 | 2.7763 | True | True |
| `examples/algorithms/scalarmult6.wasm` | perf_gap | 0.9878 | 2.9347 | True | True |
| `examples/algorithms/scalarmult7.wasm` | perf_gap | 0.9792 | 2.1836 | True | True |
| `examples/algorithms/scalarmult8.wasm` | ok | 0.9985 | 1.0635 | True | True |
| `examples/algorithms/scalarmult_ed25519.wasm` | ok | 1.0019 | 1.2904 | True | True |
| `examples/algorithms/scalarmult_ristretto255.wasm` | perf_gap | 1.0560 | 1.2606 | True | True |
| `examples/algorithms/secretbox.wasm` | perf_gap | 1.2520 | 3.0983 | True | True |
| `examples/algorithms/secretbox2.wasm` | perf_gap | 1.1129 | 2.7829 | True | True |
| `examples/algorithms/secretbox7.wasm` | ok | 0.9778 | 1.0187 | True | True |
| `examples/algorithms/secretbox8.wasm` | ok | 0.9644 | 0.9801 | True | True |
| `examples/algorithms/secretbox_easy.wasm` | perf_gap | 0.9035 | 3.2974 | True | True |
| `examples/algorithms/secretbox_easy2.wasm` | perf_gap | 1.1259 | 1.1389 | True | True |
| `examples/algorithms/secretstream_xchacha20poly1305.wasm` | perf_gap | 1.0023 | 2.9502 | True | True |
| `examples/algorithms/shorthash.wasm` | perf_gap | 0.5863 | 2.6402 | True | True |
| `examples/algorithms/sign.wasm` | ok | 0.9477 | 0.9498 | True | True |
| `examples/algorithms/sign2.wasm` | ok | 0.9982 | 1.8232 | True | True |
| `examples/algorithms/siphashx24.wasm` | perf_gap | 0.7767 | 2.8562 | True | True |
| `examples/algorithms/sodium_utils.wasm` | ok | 0.9816 | 0.9935 | True | True |
| `examples/algorithms/stream.wasm` | ok | 0.7034 | 0.7108 | True | True |
| `examples/algorithms/stream2.wasm` | ok | 0.6710 | 0.6786 | True | True |
| `examples/algorithms/stream3.wasm` | perf_gap | 1.0811 | 2.9160 | True | True |
| `examples/algorithms/stream4.wasm` | perf_gap | 1.1250 | 2.8655 | True | True |
| `examples/algorithms/verify1.wasm` | ok | 0.8774 | 0.8815 | True | True |
| `examples/algorithms/xchacha20.wasm` | ok | 0.9744 | 1.0593 | True | True |

## Performance Gaps

- examples/algorithms/aead_chacha20poly1305.wasm: paired wall ratio 2.2391 (threshold 2.0000)
- examples/algorithms/aead_xchacha20poly1305.wasm: paired wall ratio 2.2053 (threshold 2.0000)
- examples/algorithms/auth.wasm: paired wall ratio 3.0440 (threshold 2.0000)
- examples/algorithms/auth2.wasm: paired wall ratio 3.1969 (threshold 2.0000)
- examples/algorithms/auth3.wasm: paired wall ratio 3.0894 (threshold 2.0000)
- examples/algorithms/auth6.wasm: paired output ratio 1.0820 (threshold 1.0500)
- examples/algorithms/box.wasm: paired output ratio 1.0566 (threshold 1.0500)
- examples/algorithms/box2.wasm: paired wall ratio 2.2657 (threshold 2.0000)
- examples/algorithms/box_easy2.wasm: paired output ratio 1.0683 (threshold 1.0500)
- examples/algorithms/box_seed.wasm: paired wall ratio 3.6046 (threshold 2.0000)
- examples/algorithms/hash.wasm: paired wall ratio 3.5986 (threshold 2.0000)
- examples/algorithms/hash3.wasm: paired wall ratio 2.7387 (threshold 2.0000)
- examples/algorithms/keygen.wasm: paired wall ratio 2.7261 (threshold 2.0000)
- examples/algorithms/onetimeauth.wasm: paired wall ratio 2.9003 (threshold 2.0000)
- examples/algorithms/onetimeauth2.wasm: paired wall ratio 2.3371 (threshold 2.0000)
- examples/algorithms/pwhash_scrypt.wasm: paired output ratio 1.0639 (threshold 1.0500)
- examples/algorithms/pwhash_scrypt_ll.wasm: paired output ratio 1.0594 (threshold 1.0500)
- examples/algorithms/scalarmult2.wasm: paired wall ratio 3.4857 (threshold 2.0000)
- examples/algorithms/scalarmult5.wasm: paired wall ratio 2.7763 (threshold 2.0000)
- examples/algorithms/scalarmult6.wasm: paired wall ratio 2.9347 (threshold 2.0000)
- examples/algorithms/scalarmult7.wasm: paired wall ratio 2.1836 (threshold 2.0000)
- examples/algorithms/scalarmult_ristretto255.wasm: paired output ratio 1.0560 (threshold 1.0500)
- examples/algorithms/secretbox.wasm: paired output ratio 1.2520 (threshold 1.0500)
- examples/algorithms/secretbox2.wasm: paired output ratio 1.1129 (threshold 1.0500)
- examples/algorithms/secretbox_easy.wasm: paired wall ratio 3.2974 (threshold 2.0000)
- examples/algorithms/secretbox_easy2.wasm: paired output ratio 1.1259 (threshold 1.0500)
- examples/algorithms/secretstream_xchacha20poly1305.wasm: paired wall ratio 2.9502 (threshold 2.0000)
- examples/algorithms/shorthash.wasm: paired wall ratio 2.6402 (threshold 2.0000)
- examples/algorithms/siphashx24.wasm: paired wall ratio 2.8562 (threshold 2.0000)
- examples/algorithms/stream3.wasm: paired output ratio 1.0811 (threshold 1.0500)
- examples/algorithms/stream4.wasm: paired output ratio 1.1250 (threshold 1.0500)
