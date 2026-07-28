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
  guard filesystem.call_exported_func("[method]descriptor.stat-at", [
      U32(directory),
      U32(0),
      String("."),
    ])
    is [Variant(0, Some(Tuple([Variant(3, None), _, _, _, _, _])))] else {
    fail("Preview 2 rejected the capability root path")
  }
  guard filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("inside/.."),
      U32(2),
      U32(1),
    ])
    is [Variant(0, Some(U32(root_directory)))] &&
    filesystem.call_exported_func("[method]descriptor.get-type", [
      U32(root_directory),
    ])
    is [Variant(0, Some(Variant(3, None)))] else {
    fail("Preview 2 rejected a terminal parent within the capability root")
  }
  debug_inspect(
    [
      filesystem.call_exported_func("[method]descriptor.stat-at", [
        U32(directory),
        U32(0),
        String(".."),
      ]),
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
  guard linker.get_import("wasi:filesystem/preopens@0.3.0")
    is Some(Instance(preopens)) &&
    preopens.call_exported_func("get-directories", [])
    is [List([Tuple([U32(directory), String("/sandbox")])])] &&
    linker.get_import("wasi:filesystem/types@0.3.0")
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
    content="[Variant(1, Some(Variant(23, None)))]",
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
    content="[Variant(0, Some(Variant(5, None)))]",
  )
  guard filesystem.call_exported_func("[method]descriptor.stat-at", [
      U32(directory),
      U32(0),
      String("."),
    ])
    is [Variant(0, Some(Tuple([Variant(2, None), _, _, _, _, _])))] else {
    fail("Preview 3 rejected the capability root path")
  }
  guard filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("inside/.."),
      U32(2),
      U32(1),
    ])
    is [Variant(0, Some(U32(root_directory)))] &&
    filesystem.call_exported_func("[method]descriptor.get-type", [
      U32(root_directory),
    ])
    is [Variant(0, Some(Variant(2, None)))] else {
    fail("Preview 3 rejected a terminal parent within the capability root")
  }
  debug_inspect(
    [
      filesystem.call_exported_func("[method]descriptor.stat-at", [
        U32(directory),
        U32(0),
        String(".."),
      ]),
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
      #|  [Variant(1, Some(Variant(30, None)))],
      #|  [Variant(1, Some(Variant(30, None)))],
      #|  [Variant(1, Some(Variant(30, None)))],
      #|]
    ),
  )
}

///|
fn remove_utf8_filesystem_fixture(root : String) -> Unit {
  for name in ["中文.txt", "e\u{0301}.txt", "😀.txt"] {
    @wasi.native_unlinkat(0, root + "/" + name, 0) |> ignore
  }
  @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
}

///|
fn create_utf8_filesystem_fixture(root : String) -> Bool {
  remove_utf8_filesystem_fixture(root)
  if !@wasi.native_mkdir(root, 0o700) {
    return false
  }
  for name in ["中文.txt", "e\u{0301}.txt", "😀.txt"] {
    if !create_capability_file(root + "/" + name) {
      remove_utf8_filesystem_fixture(root)
      return false
    }
  }
  true
}

///|
test "Preview 2 directory names round-trip through UTF-8" {
  let root = "/tmp/wasmoon-preview2-filesystem-utf8"
  guard create_utf8_filesystem_fixture(root) else {
    fail("could not create Preview 2 UTF-8 filesystem fixture")
  }
  defer remove_utf8_filesystem_fixture(root)
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
    is Some(Instance(filesystem)) &&
    filesystem.call_exported_func("[method]descriptor.read-directory", [
      U32(directory),
    ])
    is [Variant(0, Some(U32(stream)))] else {
    fail("Preview 2 UTF-8 directory stream was not created")
  }
  let names : Array[String] = []
  for ;; {
    match
      filesystem.call_exported_func(
        "[method]directory-entry-stream.read-directory-entry",
        [U32(stream)],
      ) {
      [Variant(0, Some(Variant(1, Some(Tuple([_, String(name)])))))] =>
        names.push(name)
      [Variant(0, Some(Variant(0, None)))] => break
      result => fail("unexpected Preview 2 directory entry: \{to_repr(result)}")
    }
  }
  names.sort()
  debug_inspect(names, content="[\"é.txt\", \"中文.txt\", \"😀.txt\"]")
  for name in names {
    guard filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(1),
        String(name),
        U32(0),
        U32(1),
      ])
      is [Variant(0, Some(U32(_)))] else {
      fail("Preview 2 could not reopen UTF-8 directory entry \{name}")
    }
  }
}

///|
test "Preview 3 filesystem paths preserve UTF-8 names" {
  let root = "/tmp/wasmoon-preview3-filesystem-utf8"
  guard create_utf8_filesystem_fixture(root) else {
    fail("could not create Preview 3 UTF-8 filesystem fixture")
  }
  defer remove_utf8_filesystem_fixture(root)
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder()
    .preopened_directory(root, "/sandbox", false)
    .build()
  defer ctx.close()
  let host = @wasi_component.WasiComponentHost(linker, ctx)
  host.add_preview3_filesystem()
  guard linker.get_import("wasi:filesystem/preopens@0.3.0")
    is Some(Instance(preopens)) &&
    preopens.call_exported_func("get-directories", [])
    is [List([Tuple([U32(directory), String("/sandbox")])])] &&
    linker.get_import("wasi:filesystem/types@0.3.0")
    is Some(Instance(filesystem)) &&
    filesystem.call_exported_func("[method]descriptor.read-directory", [
      U32(directory),
    ])
    is [Tuple([U32(_), U32(_)])] else {
    fail("Preview 3 UTF-8 directory stream was not created")
  }
  for name in ["中文.txt", "e\u{0301}.txt", "😀.txt"] {
    guard filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(1),
        String(name),
        U32(0),
        U32(1),
      ])
      is [Variant(0, Some(U32(_)))] else {
      fail("Preview 3 could not open UTF-8 path \{name}")
    }
  }
}
