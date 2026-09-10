///|
fn continuation_roundtrip(source : String) -> Unit raise {
  let module_ = @wat.parse(source)
  validate_module(module_, stack_switching=true)
  validate_module_with_context(module_, stack_switching=true)
  let bytes = Bytes::from_array(@encoder.encode(module_).map(Int::to_byte))
  let decoded = @parser.parse_module(bytes)
  validate_module(decoded, stack_switching=true)
  assert_eq(@encoder.encode(decoded), @encoder.encode(module_))
  let rendered = @wat.parse(@wat.render(module_))
  validate_module(rendered, stack_switching=true)
  assert_eq(@encoder.encode(rendered), @encoder.encode(module_))
}

///|
test "continuation frontend: creation binding and resumption roundtrip" {
  continuation_roundtrip(
    (
      #|(module
      #|  (type $f (func (param i32 i64) (result i64)))
      #|  (type $g (func (param i64) (result i64)))
      #|  (type $c (cont $f))
      #|  (type $d (cont $g))
      #|  (func $body (type $f) local.get 1)
      #|  (elem declare func $body)
      #|  (func (result i64)
      #|    (resume $d (i64.const 42)
      #|      (cont.bind $c $d (i32.const 7) (cont.new $c (ref.func $body))))))
    ),
  )
}

///|
test "continuation frontend: suspension handlers and control tag results" {
  continuation_roundtrip(
    (
      #|(module
      #|  (type $f (func (result i32)))
      #|  (type $c (cont $f))
      #|  (type $after (func (param i64) (result i32)))
      #|  (type $k (cont $after))
      #|  (tag $yield (param i32) (result i64))
      #|  (func (result i32 (ref $k))
      #|    (block $handler (result i32 (ref $k))
      #|      (resume $c (on $yield $handler) (ref.null $c))
      #|      drop unreachable))
      #|  (func (result i64) (suspend $yield (i32.const 8))))
    ),
  )
}

///|
test "continuation frontend: feature gate and hierarchy isolation" {
  let source =
    #|(module (type $f (func)) (type $c (cont $f)))
  let module_ = @wat.parse(source)
  try validate_module(module_) catch {
    error =>
      inspect(error, content="TypeMismatch(\"stack switching is not enabled\")")
  } noraise {
    _ => fail("expected the feature gate to reject continuation types")
  }
  for
    source in [
      "(module (type $f (func)) (type $c (cont $f)) (func (result (ref null $c)) ref.null none))",
      "(module (type $f (func)) (type $c (cont $f)) (func (result anyref) ref.null $c))",
      "(module (type $f (func)) (type $c (cont $f)) (func (result (ref $c)) ref.null $c))",
      "(module (type $s (struct)) (type $c (cont $s)))", "(module (type $f (func)) (type $c (cont $f)) (func cont.new $f drop))",
    ] {
    let invalid = @wat.parse(source)
    try validate_module(invalid, stack_switching=true) catch {
      _ => ()
    } noraise {
      _ => fail(source)
    }
  }
}
