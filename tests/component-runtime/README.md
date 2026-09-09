# Component runtime regressions

`canonical-payloads.wast` derives its producer/consumer setup from
`component-spec/upstream/async/cross-task-future.wast`. It covers tuple payloads
and string transcoding across independent component memories for both streams
and futures. The source also runs directly on Wasmtime 40.0.0.

```sh
python3 scripts/run_component_wast.py --dir tests/component-runtime
python3 scripts/run_component_wast.py --dir tests/component-runtime --no-jit
wasmtime wast -W component-model-async=y -C parallel-compilation=n tests/component-runtime/canonical-payloads.wast
```
