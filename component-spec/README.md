# Component Model reference tests

`upstream/` is a byte-for-byte import of the official Component Model `test/`
tree at the commit recorded in `SNAPSHOT.json`. The manifest pins the upstream
commit, Git tree, parser version, complete path set, and SHA-256 of every file.
Do not edit files under `upstream/` directly.

`CORRECTIONS.json` records reviewed corrections to obsolete temporary assertions.
Each entry pins both the original upstream hash and the corrected file under
`corrections/`, and states its reason. Suite runs announce and use those files;
the original snapshot remains unchanged and is still verified in full. Running
an explicit `--dir` executes the files in that directory without corrections.

The reentry correction changes two containment-based traps in
`async/trap-on-reenter.wast` into successful parent-to-child and child-to-parent
calls, matching Wasmtime 40.0.0 and the imported Wasmtime misc suite. Its recursive
callback trap remains intact. Direct probes of all three component forms used
`wasmtime run --invoke 'g()'` for the successful calls and
`wasmtime run -W component-model-async=y -W component-model-async-builtins=y
--invoke 'c()'` for the recursive trap.

The matching Wasmtime 50 oracle also permits entry after a parent callback yields.
ISS-490 tracks that remaining difference in the earlier reentry correction.

The synchronous-blocking correction updates eleven obsolete trap-precedence
assertions in `async/trap-if-block-and-sync.wast`. Immediately trapping async
callees execute, and malformed buffers or handles are validated before blocking.
Independent controls cover malformed inputs, valid blocking operations and
immediately completed operations in `tests/component-runtime/`. The complete
corrected script passes Wasmtime 50.0.0-dev, built from the exact misc corpus
revision 668016926adfd1b8a79dbce894f1e203d8892599 (see ISS-488).

The `async/sync-streams.wast` correction explicitly yields after the first stream
transfer, allowing its producer to finish and release the instance lock before
the next call. Every original assertion is preserved. This corrected script also
passes the matching Wasmtime oracle.

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
