# Component Model Spec Tests (Upstream)

Source: https://github.com/WebAssembly/component-model
Commit: d346e5a335b772909ac4c8072f56d7ed7ea49927
Tree: cf8cfdb0ec1b2385a3452ee3380d736c2138e69a
Path: test/
License: Apache-2.0

Notes:
- `upstream/` is imported byte-for-byte for Wasmoon validation and runtime
  coverage. `SNAPSHOT.json` pins every imported path and SHA-256.
- `suites/` is local metadata and is not part of the upstream tree.
- The upstream repository licenses files under Apache-2.0 unless a subdirectory
  has its own LICENSE. The Apache-2.0 text is copied to `LICENSE-APACHE`.
- Upstream folded the former tool-specific test directories into the functional
  `async/`, `binary/`, `linking/`, `resources/`, `validation/`, and `values/`
  directories. Local suite classification is feature-based and does not depend
  on those directory names.

Reproduce this snapshot from an existing upstream checkout:

```bash
python3 scripts/sync_component_model_tests.py \
  --source /path/to/component-model \
  --commit d346e5a335b772909ac4c8072f56d7ed7ea49927 \
  --wasm-tools-version 1.254.0
```

Omit `--source` to fetch the exact commit from the recorded official
repository. The sync fails if the three suite manifests do not remain non-empty,
disjoint, and exhaustive.
