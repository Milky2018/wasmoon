# Algorithms Benchmark: Wasmoon vs Wasmtime

- Summary file: `target/upstream-49/algorithms/summary.json`
- Cold isolated cache root: `target/upstream-49/algorithms/jit-cache`
- Runs per engine and workload: `1`
- Wasmtime parallel compilation: `disabled`
- Total workloads: `70`
- OK: `34`
- Failures: `0`
- Perf gaps: `36`

Fresh compilation, cache hits, and writes are reported by Wasmoon itself.
Wasmtime compilation/hit/write outcomes are unknown; filesystem changes alone are not compilation evidence.

| Workload | Status | Value Ratio | Wall Ratio | Wasmoon Fresh Compile | Wasmoon Cache Hit | Wasmoon Cache Write | Wasmoon Cache Files Changed | Wasmtime Cache Files Changed |
|---|---|---:|---:|---|---|---|---|---|
| `examples/algorithms/aead_aegis128l.wasm` | ok | 0.9843 | 1.0214 | True | False | True | True | True |
| `examples/algorithms/aead_aegis256.wasm` | ok | 0.9712 | 1.0106 | True | False | True | True | True |
| `examples/algorithms/aead_chacha20poly1305.wasm` | perf_gap | 1.3172 | 1.7222 | True | False | True | True | True |
| `examples/algorithms/aead_chacha20poly13052.wasm` | perf_gap | 1.1791 | 1.4556 | True | False | True | True | True |
| `examples/algorithms/aead_xchacha20poly1305.wasm` | perf_gap | 1.2328 | 1.6293 | True | False | True | True | True |
| `examples/algorithms/auth.wasm` | perf_gap | 1.1368 | 1.8826 | True | False | True | True | True |
| `examples/algorithms/auth2.wasm` | perf_gap | 1.1065 | 1.8650 | True | False | True | True | True |
| `examples/algorithms/auth3.wasm` | perf_gap | 1.1276 | 1.8497 | True | False | True | True | True |
| `examples/algorithms/auth5.wasm` | perf_gap | 1.1114 | 1.1197 | True | False | True | True | True |
| `examples/algorithms/auth6.wasm` | perf_gap | 1.1462 | 1.7438 | True | False | True | True | True |
| `examples/algorithms/auth7.wasm` | perf_gap | 1.0660 | 1.0823 | True | False | True | True | True |
| `examples/algorithms/box.wasm` | ok | 1.0021 | 1.5077 | True | False | True | True | True |
| `examples/algorithms/box2.wasm` | ok | 1.0110 | 1.5927 | True | False | True | True | True |
| `examples/algorithms/box7.wasm` | ok | 1.0116 | 1.0126 | True | False | True | True | True |
| `examples/algorithms/box8.wasm` | ok | 1.0121 | 1.0125 | True | False | True | True | True |
| `examples/algorithms/box_easy.wasm` | ok | 1.0021 | 1.3525 | True | False | True | True | True |
| `examples/algorithms/box_easy2.wasm` | ok | 1.0276 | 1.0376 | True | False | True | True | True |
| `examples/algorithms/box_seal.wasm` | ok | 1.0170 | 1.2339 | True | False | True | True | True |
| `examples/algorithms/box_seed.wasm` | ok | 1.0465 | 1.9582 | True | False | True | True | True |
| `examples/algorithms/chacha20.wasm` | ok | 1.0059 | 1.2127 | True | False | True | True | True |
| `examples/algorithms/codecs.wasm` | perf_gap | 1.0883 | 1.2180 | True | False | True | True | True |
| `examples/algorithms/core3.wasm` | ok | 1.0136 | 1.0168 | True | False | True | True | True |
| `examples/algorithms/core_ed25519.wasm` | ok | 1.0226 | 1.0235 | True | False | True | True | True |
| `examples/algorithms/core_ed25519_h2c.wasm` | ok | 1.0035 | 1.2608 | True | False | True | True | True |
| `examples/algorithms/core_ristretto255.wasm` | ok | 1.0199 | 1.0203 | True | False | True | True | True |
| `examples/algorithms/ed25519_convert.wasm` | ok | 1.0182 | 1.0220 | True | False | True | True | True |
| `examples/algorithms/generichash.wasm` | perf_gap | 1.0986 | 1.3442 | True | False | True | True | True |
| `examples/algorithms/generichash2.wasm` | ok | 0.9666 | 1.6800 | True | False | True | True | True |
| `examples/algorithms/generichash3.wasm` | perf_gap | 1.0798 | 1.7272 | True | False | True | True | True |
| `examples/algorithms/hash.wasm` | perf_gap | 1.0565 | 1.8751 | True | False | True | True | True |
| `examples/algorithms/hash3.wasm` | perf_gap | 1.0588 | 1.8153 | True | False | True | True | True |
| `examples/algorithms/kdf.wasm` | perf_gap | 1.1025 | 1.7811 | True | False | True | True | True |
| `examples/algorithms/kdf_hkdf.wasm` | perf_gap | 1.1228 | 1.3391 | True | False | True | True | True |
| `examples/algorithms/keygen.wasm` | perf_gap | 1.1873 | 1.7210 | True | False | True | True | True |
| `examples/algorithms/kx.wasm` | ok | 1.0027 | 1.1665 | True | False | True | True | True |
| `examples/algorithms/metamorphic.wasm` | perf_gap | 1.1109 | 1.1246 | True | False | True | True | True |
| `examples/algorithms/onetimeauth.wasm` | perf_gap | 1.2308 | 1.7812 | True | False | True | True | True |
| `examples/algorithms/onetimeauth2.wasm` | ok | 1.0000 | 1.7136 | True | False | True | True | True |
| `examples/algorithms/onetimeauth7.wasm` | perf_gap | 1.0733 | 1.0937 | True | False | True | True | True |
| `examples/algorithms/pwhash_argon2i.wasm` | perf_gap | 1.1354 | 1.1363 | True | False | True | True | True |
| `examples/algorithms/pwhash_argon2id.wasm` | perf_gap | 1.1440 | 1.1448 | True | False | True | True | True |
| `examples/algorithms/pwhash_scrypt.wasm` | perf_gap | 1.0584 | 1.0586 | True | False | True | True | True |
| `examples/algorithms/pwhash_scrypt_ll.wasm` | perf_gap | 1.0720 | 1.0748 | True | False | True | True | True |
| `examples/algorithms/randombytes.wasm` | perf_gap | 2.1226 | 2.0939 | True | False | True | True | True |
| `examples/algorithms/scalarmult.wasm` | ok | 1.0073 | 1.3680 | True | False | True | True | True |
| `examples/algorithms/scalarmult2.wasm` | ok | 1.0142 | 1.8511 | True | False | True | True | True |
| `examples/algorithms/scalarmult5.wasm` | ok | 1.0100 | 1.6570 | True | False | True | True | True |
| `examples/algorithms/scalarmult6.wasm` | ok | 1.0106 | 1.6867 | True | False | True | True | True |
| `examples/algorithms/scalarmult7.wasm` | ok | 1.0113 | 1.4908 | True | False | True | True | True |
| `examples/algorithms/scalarmult8.wasm` | ok | 1.0046 | 1.0365 | True | False | True | True | True |
| `examples/algorithms/scalarmult_ed25519.wasm` | ok | 1.0157 | 1.1488 | True | False | True | True | True |
| `examples/algorithms/scalarmult_ristretto255.wasm` | ok | 1.0150 | 1.1163 | True | False | True | True | True |
| `examples/algorithms/secretbox.wasm` | perf_gap | 1.0734 | 1.8340 | True | False | True | True | True |
| `examples/algorithms/secretbox2.wasm` | perf_gap | 1.0800 | 1.8168 | True | False | True | True | True |
| `examples/algorithms/secretbox7.wasm` | perf_gap | 1.0516 | 1.0718 | True | False | True | True | True |
| `examples/algorithms/secretbox8.wasm` | perf_gap | 1.0599 | 1.0682 | True | False | True | True | True |
| `examples/algorithms/secretbox_easy.wasm` | perf_gap | 1.2587 | 1.8968 | True | False | True | True | True |
| `examples/algorithms/secretbox_easy2.wasm` | perf_gap | 1.0881 | 1.0941 | True | False | True | True | True |
| `examples/algorithms/secretstream_xchacha20poly1305.wasm` | perf_gap | 1.1352 | 1.7734 | True | False | True | True | True |
| `examples/algorithms/shorthash.wasm` | ok | 1.0000 | 1.7403 | True | False | True | True | True |
| `examples/algorithms/sign.wasm` | ok | 1.0139 | 1.0149 | True | False | True | True | True |
| `examples/algorithms/sign2.wasm` | ok | 1.0180 | 1.3605 | True | False | True | True | True |
| `examples/algorithms/siphashx24.wasm` | ok | 1.0086 | 1.7612 | True | False | True | True | True |
| `examples/algorithms/sodium_utils.wasm` | perf_gap | 1.0844 | 1.0905 | True | False | True | True | True |
| `examples/algorithms/stream.wasm` | ok | 1.0358 | 1.0402 | True | False | True | True | True |
| `examples/algorithms/stream2.wasm` | ok | 1.0392 | 1.0440 | True | False | True | True | True |
| `examples/algorithms/stream3.wasm` | perf_gap | 1.1176 | 1.8043 | True | False | True | True | True |
| `examples/algorithms/stream4.wasm` | perf_gap | 1.0714 | 1.7856 | True | False | True | True | True |
| `examples/algorithms/verify1.wasm` | perf_gap | 1.2116 | 1.2134 | True | False | True | True | True |
| `examples/algorithms/xchacha20.wasm` | ok | 1.0120 | 1.0522 | True | False | True | True | True |

## Performance Gaps

- examples/algorithms/aead_chacha20poly1305.wasm: paired output ratio 1.3172 (threshold 1.0500)
- examples/algorithms/aead_chacha20poly13052.wasm: paired output ratio 1.1791 (threshold 1.0500)
- examples/algorithms/aead_xchacha20poly1305.wasm: paired output ratio 1.2328 (threshold 1.0500)
- examples/algorithms/auth.wasm: paired output ratio 1.1368 (threshold 1.0500)
- examples/algorithms/auth2.wasm: paired output ratio 1.1065 (threshold 1.0500)
- examples/algorithms/auth3.wasm: paired output ratio 1.1276 (threshold 1.0500)
- examples/algorithms/auth5.wasm: paired output ratio 1.1114 (threshold 1.0500)
- examples/algorithms/auth6.wasm: paired output ratio 1.1462 (threshold 1.0500)
- examples/algorithms/auth7.wasm: paired output ratio 1.0660 (threshold 1.0500)
- examples/algorithms/codecs.wasm: paired output ratio 1.0883 (threshold 1.0500)
- examples/algorithms/generichash.wasm: paired output ratio 1.0986 (threshold 1.0500)
- examples/algorithms/generichash3.wasm: paired output ratio 1.0798 (threshold 1.0500)
- examples/algorithms/hash.wasm: paired output ratio 1.0565 (threshold 1.0500)
- examples/algorithms/hash3.wasm: paired output ratio 1.0588 (threshold 1.0500)
- examples/algorithms/kdf.wasm: paired output ratio 1.1025 (threshold 1.0500)
- examples/algorithms/kdf_hkdf.wasm: paired output ratio 1.1228 (threshold 1.0500)
- examples/algorithms/keygen.wasm: paired output ratio 1.1873 (threshold 1.0500)
- examples/algorithms/metamorphic.wasm: paired output ratio 1.1109 (threshold 1.0500)
- examples/algorithms/onetimeauth.wasm: paired output ratio 1.2308 (threshold 1.0500)
- examples/algorithms/onetimeauth7.wasm: paired output ratio 1.0733 (threshold 1.0500)
- examples/algorithms/pwhash_argon2i.wasm: paired output ratio 1.1354 (threshold 1.0500)
- examples/algorithms/pwhash_argon2id.wasm: paired output ratio 1.1440 (threshold 1.0500)
- examples/algorithms/pwhash_scrypt.wasm: paired output ratio 1.0584 (threshold 1.0500)
- examples/algorithms/pwhash_scrypt_ll.wasm: paired output ratio 1.0720 (threshold 1.0500)
- examples/algorithms/randombytes.wasm: paired output ratio 2.1226 (threshold 1.0500)
- examples/algorithms/secretbox.wasm: paired output ratio 1.0734 (threshold 1.0500)
- examples/algorithms/secretbox2.wasm: paired output ratio 1.0800 (threshold 1.0500)
- examples/algorithms/secretbox7.wasm: paired output ratio 1.0516 (threshold 1.0500)
- examples/algorithms/secretbox8.wasm: paired output ratio 1.0599 (threshold 1.0500)
- examples/algorithms/secretbox_easy.wasm: paired output ratio 1.2587 (threshold 1.0500)
- examples/algorithms/secretbox_easy2.wasm: paired output ratio 1.0881 (threshold 1.0500)
- examples/algorithms/secretstream_xchacha20poly1305.wasm: paired output ratio 1.1352 (threshold 1.0500)
- examples/algorithms/sodium_utils.wasm: paired output ratio 1.0844 (threshold 1.0500)
- examples/algorithms/stream3.wasm: paired output ratio 1.1176 (threshold 1.0500)
- examples/algorithms/stream4.wasm: paired output ratio 1.0714 (threshold 1.0500)
- examples/algorithms/verify1.wasm: paired output ratio 1.2116 (threshold 1.0500)
