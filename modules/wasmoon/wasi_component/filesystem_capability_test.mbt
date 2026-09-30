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
  let root = @test_fs.temp_dir() + "/wasmoon-preview2-capability-path"
  let outside = @test_fs.temp_dir() + "/wasmoon-preview2-capability-outside"
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
        String("not-dir/"),
      ]),
      filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(1),
        String("not-dir/"),
        U32(0),
        U32(1),
      ]),
    ],
    content=(
      #|[
      #|  [Variant(1, Some(Variant(24, None)))],
      #|  [Variant(1, Some(Variant(24, None)))],
      #|]
    ),
  )
  guard filesystem.call_exported_func("[method]descriptor.stat-at", [
      U32(directory),
      U32(0),
      String("inside/"),
    ])
    is [Variant(0, Some(Tuple([Variant(3, None), _, _, _, _, _])))] &&
    filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("inside/"),
      U32(0),
      U32(1),
    ])
    is [Variant(0, Some(U32(_)))] else {
    fail("Preview 2 rejected a directory path with a trailing slash")
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
  let root = @test_fs.temp_dir() + "/wasmoon-preview3-capability-path"
  let outside = @test_fs.temp_dir() + "/wasmoon-preview3-capability-outside"
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
  assert_eq(
    filesystem.call_exported_func("[method]descriptor.remove-directory-at", [
      U32(directory),
      String("."),
    ]),
    [Variant(1, Some(Variant(11, None)))],
  )
  // A trailing slash requires a directory; unlink must not delete its symlink.
  assert_eq(
    filesystem.call_exported_func("[method]descriptor.unlink-file-at", [
      U32(directory),
      String("link/"),
    ]),
    [Variant(1, Some(Variant(13, None)))],
  )
  assert_eq(
    @wasi.native_readlinkat(0, root + "/link", 128),
    Some("inside/deep"),
  )
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
        String("not-dir/"),
      ]),
      filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(1),
        String("not-dir/"),
        U32(0),
        U32(1),
      ]),
    ],
    content=(
      #|[
      #|  [Variant(1, Some(Variant(23, None)))],
      #|  [Variant(1, Some(Variant(23, None)))],
      #|]
    ),
  )
  guard filesystem.call_exported_func("[method]descriptor.stat-at", [
      U32(directory),
      U32(0),
      String("inside/"),
    ])
    is [Variant(0, Some(Tuple([Variant(2, None), _, _, _, _, _])))] &&
    filesystem.call_exported_func("[method]descriptor.open-at", [
      U32(directory),
      U32(1),
      String("inside/"),
      U32(0),
      U32(1),
    ])
    is [Variant(0, Some(U32(_)))] else {
    fail("Preview 3 rejected a directory path with a trailing slash")
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
  let root = @test_fs.temp_dir() + "/wasmoon-preview2-filesystem-utf8"
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
      result => fail("unexpected Preview 2 directory entry: \{Repr(result)}")
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
  let root = @test_fs.temp_dir() + "/wasmoon-preview3-filesystem-utf8"
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

///|
// Wasmtime v49.0.1 p2_file_settime_overflow / p3_file_settime_overflow.
test "upstream timestamp overflow is an error for descriptor and path setters" {
  for version in ["0.2.11", "0.3.0"] {
    let root = @test_fs.temp_dir() + "/wasmoon-timestamp-overflow-" + version
    @wasi.native_unlinkat(0, root + "/file", 0) |> ignore
    @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
    assert_true(@wasi.native_mkdir(root, 0o700))
    defer @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
    assert_true(create_capability_file(root + "/file"))
    defer @wasi.native_unlinkat(0, root + "/file", 0) |> ignore
    let linker = @runtime_impl.ComponentLinker()
    let ctx = @wasi_component.WasiComponentCtxBuilder()
      .preopened_directory(root, "/sandbox", false)
      .build()
    defer ctx.close()
    let host = @wasi_component.WasiComponentHost(linker, ctx)
    let preview3 = version == "0.3.0"
    if preview3 {
      host.add_preview3_filesystem()
    } else {
      host.add_preview2_filesystem()
    }
    guard linker.get_import("wasi:filesystem/preopens@" + version)
      is Some(Instance(preopens)) &&
      preopens.call_exported_func("get-directories", [])
      is [List([Tuple([U32(directory), _])])] &&
      linker.get_import("wasi:filesystem/types@" + version)
      is Some(Instance(filesystem)) else {
      fail("filesystem interfaces were not registered")
    }
    guard filesystem.call_exported_func("[method]descriptor.open-at", [
        U32(directory),
        U32(0),
        String("file"),
        U32(0),
        U32(3),
      ])
      is [Variant(0, Some(U32(file)))] else {
      fail("test file did not open")
    }
    let seconds : @runtime_impl.ComponentValue = if preview3 {
      S64(9_223_372_036_854_775_807L)
    } else {
      U64(-1L)
    }
    let zero : @runtime_impl.ComponentValue = if preview3 {
      S64(0L)
    } else {
      U64(0L)
    }
    let normal : @runtime_impl.ComponentValue = Variant(
      2,
      Some(Tuple([zero, U32(0)])),
    )
    let overflow : @runtime_impl.ComponentValue = Variant(
      2,
      Some(Tuple([seconds, U32(1_000_000_000)])),
    )
    let expected : Array[@runtime_impl.ComponentValue] = [
      Variant(1, Some(Variant(if preview3 { 29 } else { 30 }, None))),
    ]
    for times in [(overflow, normal), (normal, overflow)] {
      assert_eq(
        filesystem.call_exported_func("[method]descriptor.set-times", [
          U32(file),
          times.0,
          times.1,
        ]),
        expected,
      )
      assert_eq(
        filesystem.call_exported_func("[method]descriptor.set-times-at", [
          U32(directory),
          U32(0),
          String("file"),
          times.0,
          times.1,
        ]),
        expected,
      )
    }
  }
}
