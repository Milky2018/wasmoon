///|
test "wit: resolve use from dependency interface" {
  let dep_src = "package dep:types@1.0.0;\n\n" +
    "interface t {\n" +
    "  type a = u32;\n" +
    "}\n"
  let root_src = "package root:pkg@0.1.0;\n\n" +
    "interface i {\n" +
    "  use dep:types/t@1.0.0.{a};\n" +
    "  f: func(x: a);\n" +
    "}\n"
  let dep = @wit.parse_package(dep_src) catch { _ => panic() }
  let root = @wit.parse_package(root_src) catch { _ => panic() }
  (@wit.resolve_package(root, [dep]) catch { _ => panic() }) |> ignore
}

///|
test "wit: toplevel-use alias participates in resolve" {
  let dep_src = "package dep:types@1.0.0;\n\n" +
    "interface t {\n" +
    "  type a = u32;\n" +
    "}\n"
  let root_src = "package root:pkg@0.1.0;\n\n" +
    "use dep:types/t@1.0.0;\n\n" +
    "interface i {\n" +
    "  use t.{a};\n" +
    "  f: func(x: a);\n" +
    "}\n"
  let dep = @wit.parse_package(dep_src) catch { _ => panic() }
  let root = @wit.parse_package(root_src) catch { _ => panic() }
  (@wit.resolve_package(root, [dep]) catch { _ => panic() }) |> ignore
}

///|
test "wit: resolve fails when dependency package missing" {
  let root_src = "package root:pkg@0.1.0;\n\n" +
    "interface i {\n" +
    "  use dep:types/t@1.0.0.{a};\n" +
    "  f: func(x: a);\n" +
    "}\n"
  let root = @wit.parse_package(root_src) catch { _ => panic() }
  let err = try? @wit.resolve_package(root, [])
  match err {
    Ok(_) => fail("expected resolve failure")
    Err(_) => ()
  }
}

///|
test "wit: toplevel-use is file-scoped (no leakage across merged docs)" {
  let dep_src = "package dep:types@1.0.0;\n\n" +
    "interface t {\n" +
    "  type x = u32;\n" +
    "}\n"
  let a_src = "package root:pkg@0.1.0;\n\n" +
    "use dep:types/t@1.0.0;\n\n" +
    "interface a {\n" +
    "  use t.{x};\n" +
    "}\n"
  let b_src = "package root:pkg@0.1.0;\n\n" +
    "interface b {\n" +
    "  use t.{x};\n" +
    "}\n"
  let dep = @wit.parse_package(dep_src) catch { _ => panic() }
  let a = @wit.parse_package(a_src) catch { _ => panic() }
  let b = @wit.parse_package(b_src) catch { _ => panic() }
  let root = @wit.merge_package_files([a, b]) catch { _ => panic() }
  let r = try? @wit.resolve_package(root, [dep])
  if r is Ok(_) {
    fail("expected resolve failure due to missing file-scoped alias")
  }
}

///|
test "wit: resolve flattens world include + adds transitive interface imports" {
  let src = "package local:demo;\n\n" +
    "interface a {\n" +
    "  resource r;\n" +
    "}\n\n" +
    "interface b {\n" +
    "  use a.{r};\n" +
    "  foo: func() -> r;\n" +
    "}\n\n" +
    "world w1 {\n" +
    "  export b;\n" +
    "}\n\n" +
    "world w2 {\n" +
    "  include w1;\n" +
    "}\n"
  let pkg = @wit.parse_package(src) catch { _ => panic() }
  let res = @wit.resolve_package(pkg, []) catch { _ => panic() }
  let out_pkg : @wit.Package = {
    name: res.root.name,
    version: res.root.version,
    items: res.root.items,
    nested: res.deps,
  }
  inspect(
    @wit.format_package(out_pkg),
    content="package local:demo;\n\n" +
      "interface a {\n" +
      "  resource r;\n" +
      "}\n\n" +
      "interface b {\n" +
      "  use a.{r};\n\n" +
      "  foo: func() -> r;\n" +
      "}\n\n" +
      "world w1 {\n" +
      "  import a;\n\n" +
      "  export b;\n" +
      "}\n" +
      "world w2 {\n" +
      "  import a;\n\n" +
      "  export b;\n" +
      "}\n",
  )
}
