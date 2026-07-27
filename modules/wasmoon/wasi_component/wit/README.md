# WASI component host WIT snapshots

This directory contains the exact WIT inputs used to generate the host contract
tables in `wit_contracts_generated.mbt`.

- `preview2` is copied from the official WebAssembly/WASI `v0.2.11` tag at
  commit `ed73919426173babd88ae145e31deca3d484bbd0`. `host.wit` is the local
  aggregation world; every file below `deps` is unmodified upstream text.
- `preview3` is pinned to the WASI 0.3 async snapshot used by Wasmtime commit
  `68a6afd4f925724fd359c13a27fac5a6163d12f4`, with package version
  `0.3.0-rc-2025-09-16`.

The Moon development build runs:

```text
python3 wasi_component/tools/generate_wasi_contracts.py \
  wasi_component/wit \
  wasi_component/wit_contracts_generated.mbt
```

The two `*.contracts.json` files are the normalized output of the public
`wasm-tools component wit --json --generate-nominal-type-ids` command. Normal
development builds generate MoonBit from those committed JSON files and do not
invoke `wasm-tools`. The generated MoonBit file is committed, so published
packages and downstream users do not need Python, `wasm-tools`, or the WIT
files at build time.

To verify a clean checkout without modifying generated source:

```text
python3 modules/wasmoon/wasi_component/tools/generate_wasi_contracts.py \
  modules/wasmoon/wasi_component/wit \
  modules/wasmoon/wasi_component/wit_contracts_generated.mbt \
  --check
```

CI additionally passes `--verify-wit`, which regenerates the normalized JSON
with pinned `wasm-tools` and rejects drift between the WIT, JSON, and MoonBit
layers.
