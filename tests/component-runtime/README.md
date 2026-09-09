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

`stream-handle-isolation.wast` contrasts a raw integer from another component
with a canonically transferred stream value. Only the stream value grants access
to the readable endpoint. Both controls pass Wasmtime 40 after binary encoding
with the pinned wasm-tools parser.
