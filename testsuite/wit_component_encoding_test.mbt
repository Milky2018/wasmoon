///|
test "wit component encode (minimal)" {
  let src =
    #|package local:demo;
    #|
    #|interface foo {
    #|  add: func(a: u32, b: u32) -> u32;
    #|}
    #|
    #|world demo {
    #|  export foo;
    #|}
  let root = @wit.parse_package(src) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let res = @wit.resolve_package(root, []) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let bytes = @wit.encode_wit_component_wasm(res) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  match @component.sniff_binary_kind(bytes) {
    Some(@component.BinaryKind::Component) => ()
    _ => fail("expected component binary kind")
  }
  let c = @component.parse_component(bytes) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  if c.exports.length() != 2 {
    fail("expected 2 type exports")
  }
  let wat = @wit.format_wit_component_wat(res) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  if !wat.has_prefix("(component") {
    fail("expected component WAT output")
  }
}

///|
test "wit component encode (non-scalar + resources + use)" {
  let src =
    #|package foo:bar@1.0.0;
    #|
    #|interface base {
    #|  record point {
    #|    x: u32,
    #|    y: u32,
    #|  }
    #|
    #|  resource thing {
    #|    get: func() -> u32;
    #|  }
    #|
    #|  flags perms { read, write }
    #|
    #|  variant maybe-point { none, some(point) }
    #|
    #|  take-perms: func(p: perms) -> perms;
    #|}
    #|
    #|interface useit {
    #|  use base.{point, thing, maybe-point};
    #|
    #|  make: func(v: u32) -> thing;
    #|  consume: func(t: thing) -> point;
    #|  borrow-get: func(t: borrow<thing>) -> u32;
    #|  opt: func(p: option<point>) -> option<point>;
    #|  res: func(x: result<point, u32>) -> result<point, u32>;
    #|  tup: func(x: tuple<u32, point>) -> tuple<u32, point>;
    #|  list-points: func(x: list<point>) -> list<point>;
    #|}
    #|
    #|world w {
    #|  export base;
    #|  export useit;
    #|}
  let root = @wit.parse_package(src) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let res = @wit.resolve_package(root, []) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let bytes = @wit.encode_wit_component_wasm(res) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  // Must parse as a component.
  let c = @component.parse_component(bytes) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  if c.exports.length() < 3 {
    fail("expected at least 3 type exports (base/useit/w)")
  }
  let wat = @wit.format_wit_component_wat(res) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  if !wat.has_prefix("(component") {
    fail("expected component WAT output")
  }
}

///|
test "wit component decode (wasm-tools fixture)" {
  let bytes = @fs.read_file_to_bytes("testsuite/fixtures/witpkg.wasm") catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let pkg = @wit.decode_wit_package_from_component(bytes) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let out = @wit.format_package(pkg)
  inspect(
    out,
    content=(
      #|package foo:bar@1.0.0;
      #|
      #|interface base {
      #|  record point {
      #|    x: u32,
      #|    y: u32,
      #|  }
      #|  flags perms {
      #|    read,
      #|    write,
      #|  }
      #|  enum color {
      #|    red,
      #|    green,
      #|    blue,
      #|  }
      #|  resource thing {
      #|    get: func() -> u32;
      #|  }
      #|  take: func(p: point, xs: list<u32>) -> tuple<u32, point>;
      #|}
      #|
      #|world w {
      #|  export base;
      #|}
      #|
    ),
  )
}

///|
test "wit component encode+decode roundtrip (parseable)" {
  let src =
    #|package foo:bar@1.0.0;
    #|
    #|interface base {
    #|  record point { x: u32, y: u32 }
    #|  variant maybe-point { none, some(point) }
    #|  resource thing {
    #|    get: func() -> u32;
    #|  }
    #|}
    #|
    #|world w {
    #|  export base;
    #|}
  let root = @wit.parse_package(src) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let res = @wit.resolve_package(root, []) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let bytes = @wit.encode_wit_component_wasm(res) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let pkg = @wit.decode_wit_package_from_component(bytes) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let out = @wit.format_package(pkg)
  // Best-effort: ensure extracted WIT is parseable and includes key items.
  let _ = @wit.parse_package(out) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  if !out.contains("variant maybe-point") {
    fail("expected extracted WIT to include variant type")
  }
  if !out.contains("resource thing") {
    fail("expected extracted WIT to include resource type")
  }
}
