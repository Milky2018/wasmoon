# Component Model Spec Tests (Upstream)

Source: https://github.com/WebAssembly/component-model
Commit: d6b48f2f28880fbf3cbc3777fba7ac31084c7540
Tree: d323b6c4bfa5d94a222b90f8f13546ec67e8e325
Path: test/
License: Apache-2.0

Notes:
- `upstream/` is imported byte-for-byte for Wasmoon validation and runtime
  coverage. `SNAPSHOT.json` pins every imported path and SHA-256.
- `suites/` is local metadata and is not part of the upstream tree.
- The upstream repository licenses files under Apache-2.0 unless a subdirectory
  has its own LICENSE. The Apache-2.0 text is copied to `LICENSE-APACHE`.
- The `wasmtime/` subdirectory contains Wasmtime-derived tests and keeps the
  Wasmtime Apache-2.0 WITH LLVM-exception license file.

Reproduce this snapshot from an existing upstream checkout:

```bash
python3 scripts/sync_component_model_tests.py \
  --source /path/to/component-model \
  --commit d6b48f2f28880fbf3cbc3777fba7ac31084c7540 \
  --wasm-tools-version 1.254.0
```

Omit `--source` to fetch the exact commit from the recorded official
repository. The sync fails if the three suite manifests do not remain non-empty,
disjoint, and exhaustive.
