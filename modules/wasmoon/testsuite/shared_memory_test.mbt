///|
test "shared memory: text and binary preserve the flag" {
  let module_ = @wat.parse("(module (memory 1 2 shared))")
  @validator.validate_module(module_)
  inspect(module_.memories[0].is_shared, content="true")
  let encoded = Bytes::from_array(
    @encoder.encode(module_).map(n => n.to_byte()),
  )
  let decoded = @parser.parse_module(encoded)
  @validator.validate_module(decoded)
  inspect(decoded.memories[0].is_shared, content="true")
  let rendered = @wat.render(decoded)
  inspect(@wat.parse(rendered).memories[0].is_shared, content="true")
  let (store, instance) = @executor.instantiate_module_with_init(decoded)
  defer store.close()
  inspect(store.get_mem(instance.mem_addrs[0]).is_shared(), content="true")
}

///|
test "shared memory: a maximum is required" {
  let module_ = @wat.parse("(module (memory 1 shared))")
  let accepted = try {
    @validator.validate_module(module_)
    true
  } catch {
    _ => false
  }
  inspect(accepted, content="false")
}

///|
test "atomics: text and binary use the same standard opcode and alignment" {
  let source =
    #|(module (memory 1 1 shared)
    #|  (func (export "test") (result i32)
    #|    i32.const 0 i32.const 42 i32.atomic.store
    #|    i32.const 0 i32.atomic.load))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let encoded = Bytes::from_array(
    @encoder.encode(module_).map(n => n.to_byte()),
  )
  let decoded = @parser.parse_module(encoded)
  @validator.validate_module(decoded)
  debug_inspect(
    decoded.codes[0].body,
    content=(
      #|[
      #|  I32Const(0),
      #|  I32Const(42),
      #|  Atomic(23, 0, 2, 0),
      #|  I32Const(0),
      #|  Atomic(16, 0, 2, 0),
      #|]
    ),
  )
  debug_inspect(run_interp_only(source, "test", []), content="Ok([I32(42)])")
  inspect(compare_jit_interp(source, "test", []), content="matched")
}

///|
test "shared memory: unsigned memory32 page limits remain positive" {
  let module_ = @wat.parse("(module (memory 1 0xffffffff shared (pagesize 1)))")
  @validator.validate_module(module_)
  debug_inspect(module_.memories[0].limits.max, content="Some(4294967295)")
  let encoded = Bytes::from_array(
    @encoder.encode(module_).map(n => n.to_byte()),
  )
  let decoded = @parser.parse_module(encoded)
  @validator.validate_module(decoded)
  debug_inspect(decoded.memories[0].limits.max, content="Some(4294967295)")
}

///|
test "atomics: alignment must equal the natural alignment" {
  for alignment in [1, 2, 8] {
    let module_ = @wat.parse(
      "(module (memory 1 1 shared) (func (result i32) i32.const 0 i32.atomic.load align=\{alignment}))",
    )
    let accepted = try {
      @validator.validate_module(module_)
      true
    } catch {
      _ => false
    }
    inspect(accepted, content="false")
  }
  for alignment in [0, 3] {
    let parsed = try {
      @wat.parse(
        "(module (memory 1 1 shared) (func (result i32) i32.const 0 i32.atomic.load align=\{alignment}))",
      )
      |> ignore
      true
    } catch {
      _ => false
    }
    inspect(parsed, content="false")
  }
}
