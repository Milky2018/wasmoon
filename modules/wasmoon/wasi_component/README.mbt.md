# WASI component host

This package is the Wasmoon-owned host layer for WASI components. It keeps
WASI policy outside the generic Component Model runtime and registers typed
host interface instances through `ComponentLinker`.

The implemented surface is intentionally versioned:

- Preview 2 uses the official `wasi:cli/command@0.2.11` contracts.
- Preview 3 uses the official `wasi:cli/command@0.3.0` contracts.
- Preview 2 command environment, exit, clocks, random, standard streams,
  polling, capability-rooted filesystem, and socket interfaces are
  implemented.
- Preview 3 command environment, exit, clocks, random, standard streams,
  capability-rooted filesystem, and socket interfaces are implemented.
- Preview 3 waits, TCP/UDP operations, streams, and completion futures are
  driven by the host reactor and do not block the cooperative component task.
- CLI component-command execution and the final pinned conformance matrix
  remain tracked separately.

The default `WasiComponentCtxBuilder` grants no filesystem or network
authority. Standard input is closed and standard output/error are discarded
unless the embedding configures captured or inherited streams.

```moonbit nocheck
let linker = @runtime_impl.ComponentLinker()
let ctx = @wasi_component.WasiComponentCtxBuilder()
  .args(["demo", "--verbose"])
  .env("LANG", "C")
  .inherit_stdio()
  .preopened_directory("/srv/data", "/data", true)
  .build()
let host = @wasi_component.WasiComponentHost(linker, ctx)
host.add_preview2_cli_clocks_random()
host.add_preview2_io()
host.add_preview2_filesystem()
host.add_preview2_sockets()
defer ctx.close()
```

Preview 3 embeddings register the corresponding async interfaces explicitly:

```moonbit nocheck
let host = @wasi_component.WasiComponentHost(linker, ctx)
host.add_preview3_cli_clocks_random()
host.add_preview3_filesystem()
host.add_preview3_sockets()
```

Preopens are directory-descriptor capabilities, not ambient path prefixes.
Guest `..` traversal and symlink resolution are checked against the live
directory ancestry before a native operation can mutate the filesystem.

The WIT snapshots, normalized contracts, generator, and upstream provenance
are under `wit/`. Normal package builds consume committed generated MoonBit
source; the CI drift check uses the pinned public `wasm-tools` release to
verify that the normalized contracts still match the WIT inputs.
