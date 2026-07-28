///|
fn create_capability_file(path : String) -> Bool {
  guard @wasi.native_open(path, [WriteOnly, Create, Truncate], 0o600)
    is Some(fd) else {
    return false
  }
  defer @wasi.native_close(fd) |> ignore
  let contents = FixedArray::makei(1, fn(_) { b'x' })
  @wasi.native_write(fd, contents, contents.length()) is Some(1)
}

///|
fn remove_capability_fixture(root : String, outside : String) -> Unit {
  for
    path in [
      root + "/escape",
      root + "/link",
      root + "/reenter",
      root + "/inside/nested-only",
      root + "/not-dir",
      root + "/root-only",
    ] {
    @wasi.native_unlinkat(0, path, 0) |> ignore
  }
  for
    path in [
      root + "/inside/deep",
      root + "/inside",
      root,
      outside + "/deep",
      outside,
    ] {
    @wasi.native_unlinkat(0, path, @wasi.AT_REMOVEDIR) |> ignore
  }
}

///|
fn create_capability_fixture(
  root : String,
  outside : String,
  reentry_target : String,
) -> Bool {
  remove_capability_fixture(root, outside)
  @wasi.native_mkdir(root, 0o700) &&
  @wasi.native_mkdir(root + "/inside", 0o700) &&
  @wasi.native_mkdir(root + "/inside/deep", 0o700) &&
  @wasi.native_mkdir(outside, 0o700) &&
  @wasi.native_mkdir(outside + "/deep", 0o700) &&
  create_capability_file(root + "/root-only") &&
  create_capability_file(root + "/not-dir") &&
  create_capability_file(root + "/inside/nested-only") &&
  @wasi.native_symlinkat("inside/deep", 0, root + "/link") &&
  @wasi.native_symlinkat(outside + "/deep", 0, root + "/escape") &&
  @wasi.native_symlinkat(reentry_target, 0, root + "/reenter")
}

///|
test "Preview 2 capability paths resolve each filesystem step" {
  let root = "/tmp/wasmoon-preview2-capability-path"
  let outside = "/tmp/wasmoon-preview2-capability-outside"
  guard create_capability_fixture(
    root, outside, "../wasmoon-preview2-capability-outside/deep/../../wasmoon-preview2-capability-path",
  ) else {
    remove_capability_fixture(root, outside)
    fail("could not create Preview 2 capability fixture")
  }
  defer remove_capability_fixture(root, outside)
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder()
    .preopened_directory(root, "/sandbox", false)
    .build()
  defer ctx.close()
  @wasi_component.WasiComponentHost(linker, ctx).add_preview2_filesystem()
  guard linker.get_import("wasi:filesystem/preopens@0.2.11")
    is Some(Instance(preopens)) &&
    preopens.call_exported_func("get-directories", [])
    is [List([Tuple([U32(directory), String("/sandbox")])])] &&
    linker.get_import("wasi:filesystem/types@0.2.11")
    is Some(Instance(filesystem)) else {
    fail("Preview 2 filesystem interfaces were not registered")
  }
  debug_inspect(
    filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("not-dir/../root-only"),
      U32(0),
      U32(1),
    ]),
    content="[Variant(1, Some(Variant(24, None)))]",
  )
  guard filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("link/../nested-only"),
      U32(0),
      U32(1),
    ])
    is [Variant(0, Some(U32(nested)))] else {
    fail("Preview 2 did not resolve symlink parent traversal")
  }
  debug_inspect(
    filesystem.call_exported_func("[method]descriptor.get-type", [U32(nested)]),
    content="[Variant(0, Some(Variant(6, None)))]",
  )
  debug_inspect(
    [
      filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(1),
        String("escape/../root-only"),
        U32(0),
        U32(1),
      ]),
      filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(1),
        String("reenter/root-only"),
        U32(0),
        U32(1),
      ]),
    ],
    content=(
      #|[
      #|  [Variant(1, Some(Variant(31, None)))],
      #|  [Variant(1, Some(Variant(31, None)))],
      #|]
    ),
  )
}

///|
test "Preview 3 capability paths resolve each filesystem step" {
  let root = "/tmp/wasmoon-preview3-capability-path"
  let outside = "/tmp/wasmoon-preview3-capability-outside"
  guard create_capability_fixture(
    root, outside, "../wasmoon-preview3-capability-outside/deep/../../wasmoon-preview3-capability-path",
  ) else {
    remove_capability_fixture(root, outside)
    fail("could not create Preview 3 capability fixture")
  }
  defer remove_capability_fixture(root, outside)
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder()
    .preopened_directory(root, "/sandbox", false)
    .build()
  defer ctx.close()
  @wasi_component.WasiComponentHost(linker, ctx).add_preview3_filesystem()
  guard linker.get_import("wasi:filesystem/preopens@0.3.0-rc-2025-09-16")
    is Some(Instance(preopens)) &&
    preopens.call_exported_func("get-directories", [])
    is [List([Tuple([U32(directory), String("/sandbox")])])] &&
    linker.get_import("wasi:filesystem/types@0.3.0-rc-2025-09-16")
    is Some(Instance(filesystem)) else {
    fail("Preview 3 filesystem interfaces were not registered")
  }
  debug_inspect(
    filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("not-dir/../root-only"),
      U32(0),
      U32(1),
    ]),
    content="[Variant(1, Some(U32(23)))]",
  )
  guard filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("link/../nested-only"),
      U32(0),
      U32(1),
    ])
    is [Variant(0, Some(U32(nested)))] else {
    fail("Preview 3 did not resolve symlink parent traversal")
  }
  debug_inspect(
    filesystem.call_exported_func("[method]descriptor.get-type", [U32(nested)]),
    content="[Variant(0, Some(U32(6)))]",
  )
  debug_inspect(
    [
      filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(1),
        String("escape/../root-only"),
        U32(0),
        U32(1),
      ]),
      filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(1),
        String("reenter/root-only"),
        U32(0),
        U32(1),
      ]),
    ],
    content="[[Variant(1, Some(U32(30)))], [Variant(1, Some(U32(30)))]]",
  )
}
