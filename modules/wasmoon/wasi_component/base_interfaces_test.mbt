///|
test "WASI component contracts pin the reviewed WIT snapshots" {
  debug_inspect(
    [
      @wasi_component.preview2_wit_sha256(),
      @wasi_component.preview3_wit_sha256(),
    ],
    content="[\n" +
      "  \"b349a9c4d0b68e5e0943d355a9b8c282d9f320ce90a084a4ee44435feb276f8f\",\n" +
      "  \"8948c1651d7fc84a921565845ff9975bcac4508c54f16bb735f476ee53503f33\",\n" +
      "]",
  )
}

///|
test "Preview 2 environment host preserves configured values" {
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder()
    .args(["demo", "--verbose"])
    .env("LANG", "C")
    .initial_cwd("/workspace")
    .build()
  @wasi_component.WasiComponentHost(linker, ctx).add_preview2_cli_clocks_random()
  guard linker.get_component("unused") is None else {
    fail("host imports must not register component instances")
  }
  let environment = match linker.get_import("wasi:cli/environment@0.2.11") {
    Some(Instance(instance)) => instance
    _ => return fail("environment interface was not registered")
  }
  debug_inspect(
    environment.call_exported_func("get-environment", []),
    content="[List([([String(\"LANG\"), String(\"C\")])])]",
  )
  debug_inspect(
    environment.call_exported_func("get-arguments", []),
    content="[List([String(\"demo\"), String(\"--verbose\")])]",
  )
  debug_inspect(
    environment.call_exported_func("initial-cwd", []),
    content="[Variant(1, Some(String(\"/workspace\")))]",
  )
}

///|
test "Preview 3 uses current environment and seed export names" {
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder()
    .insecure_seed(11L, 29L)
    .build()
  @wasi_component.WasiComponentHost(linker, ctx).add_preview3_cli_clocks_random()
  guard linker.get_import("wasi:cli/environment@0.3.0-rc-2025-09-16")
    is Some(Instance(environment)) else {
    fail("Preview 3 environment interface was not registered")
  }
  debug_inspect(
    environment.call_exported_func("get-initial-cwd", []),
    content="[Variant(0, None)]",
  )
  guard linker.get_import("wasi:random/insecure-seed@0.3.0-rc-2025-09-16")
    is Some(Instance(seed)) else {
    fail("Preview 3 insecure seed interface was not registered")
  }
  debug_inspect(
    seed.call_exported_func("get-insecure-seed", []),
    content="[([U64(11), U64(29)])]",
  )
  guard linker.get_import("wasi:clocks/monotonic-clock@0.3.0-rc-2025-09-16")
    is Some(Instance(clock)) else {
    fail("Preview 3 monotonic clock interface was not registered")
  }
  debug_inspect(
    clock.call_exported_func("wait-for", [U64(1000000L)]),
    content="[]",
  )
}

///|
test "WASI component exit is structured and recorded" {
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder().build()
  @wasi_component.WasiComponentHost(linker, ctx).add_preview2_cli_clocks_random()
  guard linker.get_import("wasi:cli/exit@0.2.11") is Some(Instance(exit)) else {
    fail("exit interface was not registered")
  }
  try exit.call_exported_func("exit", [Variant(1, None)]) catch {
    e => debug_inspect(e, content="HostExit(1)")
  } noraise {
    _ => fail("expected exit to terminate the component command")
  }
  debug_inspect(ctx.exit_status(), content="Some(1)")
}

///|
test "Preview 2 standard streams share typed resource handles" {
  let output : Array[Bytes] = []
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder()
    .stdin(b"hello")
    .stdout(fn(bytes) { output.push(bytes) })
    .build()
  let host = @wasi_component.WasiComponentHost(linker, ctx)
  host.add_preview2_io()
  guard linker.get_import("wasi:cli/stdin@0.2.11") is Some(Instance(stdin)) else {
    fail("stdin interface was not registered")
  }
  guard stdin.call_exported_func("get-stdin", []) is [U32(input)] else {
    fail("stdin did not return an input stream")
  }
  guard linker.get_import("wasi:io/streams@0.2.11") is Some(Instance(streams)) else {
    fail("streams interface was not registered")
  }
  debug_inspect(
    streams.call_exported_func("[method]input-stream.read", [
      U32(input),
      U64(3L),
    ]),
    content="[Variant(0, Some(List([U8(104), U8(101), U8(108)])))]",
  )
  guard linker.get_import("wasi:cli/stdout@0.2.11") is Some(Instance(stdout)) else {
    fail("stdout interface was not registered")
  }
  guard stdout.call_exported_func("get-stdout", []) is [U32(output_handle)] else {
    fail("stdout did not return an output stream")
  }
  debug_inspect(
    streams.call_exported_func("[method]output-stream.check-write", [
      U32(output_handle),
    ]),
    content="[Variant(0, Some(U64(65536)))]",
  )
  debug_inspect(
    streams.call_exported_func("[method]output-stream.write", [
      U32(output_handle),
      List([U8(111), U8(107)]),
    ]),
    content="[Variant(0, None)]",
  )
  debug_inspect(output, content="[<Bytes: [0x6f, 0x6b]>]")
}

///|
test "dropping one standard stream handle preserves independent handles" {
  let linker = @runtime_impl.ComponentLinker()
  let host = @wasi_component.WasiComponentHost(
    linker,
    @wasi_component.WasiComponentCtxBuilder().stdin(b"ok").build(),
  )
  host.add_preview2_io()
  guard linker.get_import("wasi:cli/stdin@0.2.11") is Some(Instance(stdin)) else {
    fail("stdin interface was not registered")
  }
  guard stdin.call_exported_func("get-stdin", []) is [U32(first)] &&
    stdin.call_exported_func("get-stdin", []) is [U32(second)] else {
    fail("stdin did not return owned stream handles")
  }
  let table = host.runtime().resource_table()
  guard table.get(first) is Some(first_resource) &&
    first_resource.host_dtor is Some(dtor) else {
    fail("owned host resource did not carry its destructor")
  }
  dtor.destroy(first_resource.rep)
  table.free(first) |> ignore
  guard linker.get_import("wasi:io/streams@0.2.11") is Some(Instance(streams)) else {
    fail("streams interface was not registered")
  }
  debug_inspect(
    streams.call_exported_func("[method]input-stream.read", [
      U32(second),
      U64(2L),
    ]),
    content="[Variant(0, Some(List([U8(111), U8(107)])))]",
  )
}

///|
test "Preview 2 splice performs its own output readiness check" {
  let output : Array[Bytes] = []
  let linker = @runtime_impl.ComponentLinker()
  let host = @wasi_component.WasiComponentHost(
    linker,
    @wasi_component.WasiComponentCtxBuilder()
    .stdin(b"splice")
    .stdout(fn(bytes) { output.push(bytes) })
    .build(),
  )
  host.add_preview2_io()
  guard linker.get_import("wasi:cli/stdin@0.2.11") is Some(Instance(stdin)) &&
    stdin.call_exported_func("get-stdin", []) is [U32(input)] &&
    linker.get_import("wasi:cli/stdout@0.2.11") is Some(Instance(stdout)) &&
    stdout.call_exported_func("get-stdout", []) is [U32(output_handle)] &&
    linker.get_import("wasi:io/streams@0.2.11") is Some(Instance(streams)) else {
    fail("Preview 2 stream interfaces were not registered")
  }
  debug_inspect(
    streams.call_exported_func("[method]output-stream.splice", [
      U32(output_handle),
      U32(input),
      U64(4L),
    ]),
    content="[Variant(0, Some(U64(4)))]",
  )
  debug_inspect(output, content="[<Bytes: [0x73, 0x70, 0x6c, 0x69]>]")
}

///|
test "Preview 2 blocking writes reject payloads over 4096 bytes" {
  let linker = @runtime_impl.ComponentLinker()
  let host = @wasi_component.WasiComponentHost(
    linker,
    @wasi_component.WasiComponentCtxBuilder().build(),
  )
  host.add_preview2_io()
  guard linker.get_import("wasi:cli/stdout@0.2.11") is Some(Instance(stdout)) &&
    stdout.call_exported_func("get-stdout", []) is [U32(output)] &&
    linker.get_import("wasi:io/streams@0.2.11") is Some(Instance(streams)) else {
    fail("Preview 2 output interfaces were not registered")
  }
  let contents : Array[@runtime_impl.ComponentValue] = Array::make(4097, U8(0))
  try
    streams.call_exported_func(
      "[method]output-stream.blocking-write-and-flush",
      [U32(output), List(contents)],
    )
    |> ignore
  catch {
    e =>
      debug_inspect(
        e,
        content="HostCallError(\"blocking write exceeds 4096 bytes\")",
      )
  } noraise {
    _ => fail("expected oversized blocking write to trap")
  }
}

///|
test "Preview 2 filesystem remains rooted at configured preopens" {
  let host_file = "/tmp/wasmoon-component-filesystem-test.txt"
  @wasi.native_unlinkat(0, host_file, 0) |> ignore
  guard @wasi.native_open(host_file, [WriteOnly, Create, Truncate], 0o600)
    is Some(fd) else {
    fail("could not create filesystem fixture")
  }
  let contents = FixedArray::makei(4, fn(i) { b"data"[i] })
  guard @wasi.native_write(fd, contents, contents.length()) is Some(4) else {
    @wasi.native_close(fd) |> ignore
    fail("could not write filesystem fixture")
  }
  @wasi.native_close(fd) |> ignore
  defer @wasi.native_unlinkat(0, host_file, 0) |> ignore

  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder()
    .preopened_directory("/tmp", "/sandbox", false)
    .build()
  defer ctx.close()
  let host = @wasi_component.WasiComponentHost(linker, ctx)
  host.add_preview2_io()
  host.add_preview2_filesystem()
  guard linker.get_import("wasi:filesystem/preopens@0.2.11")
    is Some(Instance(preopens)) &&
    preopens.call_exported_func("get-directories", [])
    is [List([Tuple([U32(directory), String("/sandbox")])])] &&
    linker.get_import("wasi:filesystem/types@0.2.11")
    is Some(Instance(filesystem)) else {
    fail("filesystem interfaces were not registered")
  }
  guard filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(0),
      String("wasmoon-component-filesystem-test.txt"),
      U32(0),
      U32(1),
    ])
    is [Variant(0, Some(U32(file)))] else {
    fail("preopened file could not be opened")
  }
  debug_inspect(
    filesystem.call_exported_func("[method]descriptor.read", [
      U32(file),
      U64(4L),
      U64(0L),
    ]),
    content="[\n" +
      "  Variant(\n" +
      "    0,\n" +
      "    Some(([List([U8(100), U8(97), U8(116), U8(97)]), Bool(true)])),\n" +
      "  ),\n" +
      "]",
  )
  guard filesystem.call_exported_func("[method]descriptor.read-via-stream", [
      U32(file),
      U64(0L),
    ])
    is [Variant(0, Some(U32(first_stream)))] &&
    filesystem.call_exported_func("[method]descriptor.read-via-stream", [
      U32(file),
      U64(2L),
    ])
    is [Variant(0, Some(U32(second_stream)))] &&
    linker.get_import("wasi:io/streams@0.2.11") is Some(Instance(streams)) else {
    fail("descriptor streams were not created")
  }
  debug_inspect(
    [
      streams.call_exported_func("[method]input-stream.read", [
        U32(first_stream),
        U64(2L),
      ]),
      streams.call_exported_func("[method]input-stream.read", [
        U32(second_stream),
        U64(2L),
      ]),
    ],
    content="[\n" +
      "  [Variant(0, Some(List([U8(100), U8(97)])))],\n" +
      "  [Variant(0, Some(List([U8(116), U8(97)])))],\n" +
      "]",
  )
  debug_inspect(
    filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(0),
      String("../etc/passwd"),
      U32(0),
      U32(1),
    ]),
    content="[Variant(1, Some(Variant(31, None)))]",
  )
}

///|
test "Preview 2 filesystem rejects intermediate symlink escape" {
  let root = "/tmp/wasmoon-component-filesystem-root"
  @wasi.native_unlinkat(0, root + "/escape", 0) |> ignore
  @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  guard @wasi.native_mkdir(root, 0o700) else {
    fail("could not create capability root")
  }
  guard @wasi.native_symlinkat("/etc", 0, root + "/escape") else {
    @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
    fail("could not create escape symlink")
  }
  defer {
    @wasi.native_unlinkat(0, root + "/escape", 0) |> ignore
    @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  }

  let linker = @runtime_impl.ComponentLinker()
  let host = @wasi_component.WasiComponentHost(
    linker,
    @wasi_component.WasiComponentCtxBuilder()
    .preopened_directory(root, "/sandbox", false)
    .build(),
  )
  defer host.context().close()
  host.add_preview2_filesystem()
  guard linker.get_import("wasi:filesystem/preopens@0.2.11")
    is Some(Instance(preopens)) &&
    preopens.call_exported_func("get-directories", [])
    is [List([Tuple([U32(directory), String("/sandbox")])])] &&
    linker.get_import("wasi:filesystem/types@0.2.11")
    is Some(Instance(filesystem)) else {
    fail("filesystem interfaces were not registered")
  }
  debug_inspect(
    filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("escape/passwd"),
      U32(0),
      U32(1),
    ]),
    content="[Variant(1, Some(Variant(31, None)))]",
  )
}

///|
test "Preview 2 clock subscriptions use the shared pollable identity" {
  let linker = @runtime_impl.ComponentLinker()
  let host = @wasi_component.WasiComponentHost(
    linker,
    @wasi_component.WasiComponentCtxBuilder().build(),
  )
  host.add_preview2_cli_clocks_random()
  host.add_preview2_io()
  guard linker.get_import("wasi:clocks/monotonic-clock@0.2.11")
    is Some(Instance(clock)) else {
    fail("monotonic clock interface was not registered")
  }
  guard clock.call_exported_func("subscribe-duration", [U64(0L)])
    is [U32(pollable)] else {
    fail("clock subscription did not return a pollable")
  }
  guard linker.get_import("wasi:io/poll@0.2.11") is Some(Instance(poll)) else {
    fail("poll interface was not registered")
  }
  debug_inspect(
    poll.call_exported_func("[method]pollable.ready", [U32(pollable)]),
    content="[Bool(true)]",
  )
  debug_inspect(
    poll.call_exported_func("poll", [List([U32(pollable)])]),
    content="[List([U32(0)])]",
  )
}

///|
test "Preview 2 poll waits for the earliest source" {
  let linker = @runtime_impl.ComponentLinker()
  let host = @wasi_component.WasiComponentHost(
    linker,
    @wasi_component.WasiComponentCtxBuilder().build(),
  )
  host.add_preview2_cli_clocks_random()
  host.add_preview2_io()
  guard linker.get_import("wasi:clocks/monotonic-clock@0.2.11")
    is Some(Instance(clock)) else {
    fail("monotonic clock interface was not registered")
  }
  guard clock.call_exported_func("subscribe-duration", [U64(1000000000L)])
    is [U32(slow)] else {
    fail("long clock subscription did not return a pollable")
  }
  guard clock.call_exported_func("subscribe-duration", [U64(1000000L)])
    is [U32(fast)] else {
    fail("short clock subscription did not return a pollable")
  }
  guard linker.get_import("wasi:io/poll@0.2.11") is Some(Instance(poll)) else {
    fail("poll interface was not registered")
  }
  debug_inspect(
    poll.call_exported_func("poll", [List([U32(slow), U32(fast)])]),
    content="[List([U32(1)])]",
  )
}
