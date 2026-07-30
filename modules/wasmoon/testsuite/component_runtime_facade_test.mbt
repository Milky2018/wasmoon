///|
fn component_runtime_facade_fixture() -> Bytes raise @component_text.ComponentTextError {
  @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m
      #|    (func (export "increment") (param i32) (result i32)
      #|      local.get 0
      #|      i32.const 1
      #|      i32.add))
      #|  (core instance $i (instantiate $m))
      #|  (func $increment (param "value" u32) (result u32)
      #|    (canon lift (core func $i "increment")))
      #|  (instance $math (export "increment" (func $increment)))
      #|  (export "increment" (func $increment))
      #|  (export "math" (instance $math))
      #|  (export "dep:math/math@1.0.0" (instance $math)))
      #|
    ),
  )
}

///|
test "component runtime facade binds and invokes nested exports" {
  let instance = @component.ComponentRuntime().instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let function = instance.bind("math#increment")
  debug_inspect(
    function.type_(),
    content=(
      #|{
      #|  is_async: false,
      #|  params: [{ name: "value", ty: U32 }],
      #|  result: Some(U32),
      #|}
    ),
  )
  debug_inspect(
    function.call([U32(41U)]),
    content=(
      #|[U32(42)]
    ),
  )
}

///|
test "component runtime facade reports stable path and arity errors" {
  let instance = @component.ComponentRuntime().instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  inspect(
    try instance.bind("math#missing") catch {
      error => error
    } noraise {
      _ => fail("expected unknown export")
    },
    content=(
      #|UnknownExport("math#missing")
    ),
  )
  let function = instance.bind("math#increment")
  inspect(
    try function.call([]) catch {
      error => error
    } noraise {
      _ => fail("expected argument count mismatch")
    },
    content=(
      #|ArgumentCountMismatch(expected=1, actual=0)
    ),
  )
}

///|
test "component runtime facade preserves WIT-shaped JSON values" {
  let ty = @component.ComponentValueType::Record([
    ComponentField("items", List(Option(U32))),
    ComponentField(
      "state",
      Variant([
        ComponentCase("ready", Some(String)),
        ComponentCase("closed", None),
      ]),
    ),
    ComponentField("permissions", Flags(["read", "write"])),
  ])
  let value = @component.parse_component_value_json(
    (
      #|{"items":[{"some":7},null],"state":{"case":"ready","value":"ok"},"permissions":["read"]}
    ),
    ty,
  )
  debug_inspect(
    value,
    content=(
      #|Record(
      #|  [
      #|    ("items", List([OptionSome(U32(7)), OptionNone])),
      #|    ("state", Variant("ready", Some(String("ok")))),
      #|    ("permissions", Flags(["read"])),
      #|  ],
      #|)
    ),
  )
  inspect(
    @component.component_value_to_json(value).stringify(),
    content=(
      #|{"items":[{"some":7},null],"state":{"case":"ready","value":"ok"},"permissions":["read"]}
    ),
  )
}

///|
test "component runtime facade rejects malformed JSON before invocation" {
  inspect(
    try
      @component.parse_component_value_json(
        "{\"wrong\":1}",
        Record([ComponentField("expected", U32)]),
      )
    catch {
      error => error
    } noraise {
      _ => fail("expected record validation failure")
    },
    content=(
      #|JsonValueError("missing record field 'expected'")
    ),
  )
}

///|
test "component JSON preserves non-finite floating-point values" {
  inspect(
    @component.component_values_to_json([
      F64(0.0 / 0.0),
      F64(1.0 / 0.0),
      F32(Float::from_double(-1.0 / 0.0)),
    ]).stringify(),
    content=(
      #|["nan","inf","-inf"]
    ),
  )
  debug_inspect(
    [
      @component.parse_component_value_json("\"nan\"", F64),
      @component.parse_component_value_json("\"inf\"", F32),
    ],
    content=(
      #|[F64(NaN), F32(Infinity)]
    ),
  )
}

///|
test "resolved WIT world binds and invokes a typed interface export" {
  let instance = @component.ComponentRuntime().instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let wit_package = @wit.parse_package(
    (
      #|package test:demo;
      #|
      #|interface math {
      #|  increment: func(value: u32) -> u32;
      #|}
      #|
      #|world demo {
      #|  export math;
      #|}
      #|
    ),
  )
  let bindings = @wit.resolve_package(wit_package, []).bind_world(
    "demo", instance,
  )
  debug_inspect(bindings.paths(), content="[\"math#increment\"]")
  debug_inspect(
    bindings.function("math#increment").call([U32(9U)]),
    content=(
      #|[U32(10)]
    ),
  )
}

///|
test "WIT binding rejects a mismatched export before invocation" {
  let instance = @component.ComponentRuntime().instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let wit_package = @wit.parse_package(
    (
      #|package test:demo;
      #|
      #|interface math {
      #|  increment: func(value: u32) -> string;
      #|}
      #|
      #|world demo {
      #|  export math;
      #|}
      #|
    ),
  )
  inspect(
    try
      @wit.resolve_package(wit_package, []).bind_world("demo", instance)
    catch {
      error => error
    } noraise {
      _ => fail("expected binding type mismatch")
    },
    content=(
      #|RuntimeBindingFailed("BindingTypeMismatch(\n  path=\"math#increment\",\n  expected={\n    is_async: false,\n    params: [{ name: \"value\", ty: U32 }],\n    result: Some(String),\n  },\n  actual={\n    is_async: false,\n    params: [{ name: \"value\", ty: U32 }],\n    result: Some(U32),\n  },\n)")
    ),
  )
}

///|
test "WIT binding covers direct and inline world exports" {
  let instance = @component.ComponentRuntime().instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let wit_package = @wit.parse_package(
    (
      #|package test:demo;
      #|
      #|world demo {
      #|  export increment: func(value: u32) -> u32;
      #|  export math: interface {
      #|    increment: func(value: u32) -> u32;
      #|  }
      #|}
      #|
    ),
  )
  let bindings = @wit.resolve_package(wit_package, []).bind_world(
    "demo", instance,
  )
  debug_inspect(bindings.paths(), content="[\"increment\", \"math#increment\"]")
}

///|
test "WIT binding resolves referenced dependency interfaces" {
  let instance = @component.ComponentRuntime().instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let root = @wit.parse_package(
    (
      #|package test:demo;
      #|
      #|world demo {
      #|  export dep:math/math@1.0.0;
      #|}
      #|
    ),
  )
  let dependency = @wit.parse_package(
    (
      #|package dep:math@1.0.0;
      #|
      #|interface math {
      #|  increment: func(value: u32) -> u32;
      #|}
      #|
    ),
  )
  let bindings = @wit.resolve_package(root, [dependency]).bind_world(
    "demo", instance,
  )
  debug_inspect(bindings.paths(), content="[\"dep:math/math@1.0.0#increment\"]")
}
