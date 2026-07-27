# WASI component host

This package is the Wasmoon-owned host layer for WASI components. It keeps
WASI policy outside the generic Component Model runtime and registers typed
host interface instances through `ComponentLinker`.

The implemented surface is intentionally versioned:

- Preview 2 uses the official `wasi:cli/command@0.2.11` contracts.
- Preview 3 uses the repository-pinned
  `0.3.0-rc-2025-09-16` async contracts.
- Preview 2 command environment, exit, clocks, random, standard streams, and
  polling are implemented.
- Preview 3 command environment, exit, clocks, random, and asynchronous
  monotonic waits are implemented.
- Filesystem, sockets, the complete Preview 3 stream/future surface, and CLI
  command execution are not yet implemented.

The default `WasiComponentCtxBuilder` grants no filesystem or network
authority. Standard input is closed and standard output/error are discarded
unless the embedding configures captured or inherited streams.

```moonbit nocheck
let linker = @runtime_impl.ComponentLinker()
let ctx = @wasi_component.WasiComponentCtxBuilder()
  .args(["demo", "--verbose"])
  .env("LANG", "C")
  .inherit_stdio()
  .build()
let host = @wasi_component.WasiComponentHost(linker, ctx)
host.add_preview2_cli_clocks_random()
host.add_preview2_io()
```

The WIT snapshots, normalized contracts, generator, and upstream provenance
are under `wit/`. Normal package builds consume committed generated MoonBit
source; the CI drift check uses the pinned public `wasm-tools` release to
verify that the normalized contracts still match the WIT inputs.
