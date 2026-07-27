# Component Model reference tests

`upstream/` is a byte-for-byte import of the official Component Model `test/`
tree at the commit recorded in `SNAPSHOT.json`. The manifest pins the upstream
commit, Git tree, parser version, complete path set, and SHA-256 of every file.
Do not edit files under `upstream/` directly.

The `.wast` files are partitioned exactly once by the manifests in `suites/`:

- `stable-0.2`: files whose valid component forms require no post-0.2
  Component Model feature.
- `async-0.3`: files that require the Component Model async proposal included
  in WASI 0.3, but no later gated proposal.
- `future-gated`: files with at least one valid form that requires a later
  gated proposal, such as additional async built-ins, the stackful async ABI,
  component threading, 64-bit canonical ABI contexts, or component
  attributes.

The partition was checked with the feature validator from the pinned
`wasm-tools` release. A file is assigned to the newest feature level required
by any of its valid component forms.

Run the suites independently:

```bash
python3 scripts/check_component_snapshot.py
python3 scripts/run_component_wast.py --suite stable-0.2 --dump-failures
python3 scripts/run_component_wast.py --suite async-0.3 --dump-failures
python3 scripts/run_component_wast.py --suite future-gated --dump-failures
```

To update the snapshot, review the upstream changes and suite classifications,
then run the exact sync command documented in `UPSTREAM.md`. The checker rejects
missing, extra, modified, multiply assigned, unassigned, and empty suites.
