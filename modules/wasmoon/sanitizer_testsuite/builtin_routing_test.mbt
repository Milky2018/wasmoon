///|
test "spectest imports invoke the linked host function with typed arguments" {
  let cases : Array[
    (String, String, String, Array[@types.ValueType], Array[@types.Value]),
  ] = [
    ("print", "", "", [], []),
    ("print_i32", "i32", "i32.const -1234567", [I32], [I32(-1234567)]),
    (
      "print_i64",
      "i64",
      "i64.const 123456789012345",
      [I64],
      [I64(123456789012345L)],
    ),
    ("print_f32", "f32", "f32.const -13.25", [F32], [F32(-13.25)]),
    ("print_f64", "f64", "f64.const 12345.125", [F64], [F64(12345.125)]),
    (
      "print_i32_f32",
      "i32 f32",
      "i32.const -17 f32.const 6.25",
      [I32, F32],
      [I32(-17), F32(6.25)],
    ),
    (
      "print_f64_f64",
      "f64 f64",
      "f64.const 3.5 f64.const -19.25",
      [F64, F64],
      [F64(3.5), F64(-19.25)],
    ),
    ("print_char", "i32", "i32.const 65", [I32], [I32(65)]),
  ]
  for (name, params, operands, types, expected) in cases {
    let source = "(module (import \"spectest\" \"\{name}\" (func $host (param \{params}))) (func (export \"run\") \{operands} call $host))"
    let module_ = @wat.parse(source)
    @validator.validate_module(module_)
    for native in [false, true] {
      let store = @runtime.Store::with_c_heap()
      let linker = @runtime.Linker::with_store(store)
      defer linker.close()
      let observed : Array[Array[@types.Value]] = []
      linker.add_host_func(
        "spectest",
        name,
        fn(args) {
          observed.push(args.copy())
          []
        },
        func_type={ params: ReadOnlyArray::from_array(types), results: [], },
      )
      let instance = @executor.instantiate_with_linker(linker, "guest", module_)
      if native {
        let context = build_gc_root_context(module_, instance, store)
        defer context.close()
        context.install_hostcall_dispatcher(store, instance)
        assert_eq(context.call_core_func(store, instance, 1, []), [])
      } else {
        assert_eq(@executor.call_exported_func(store, instance, "run", []), [])
      }
      assert_eq(observed, [expected], msg="\{name}, native=\{native}")
    }
  }
}

///|
test "builtin-named overrides preserve mixed stack arguments and overflow results on every call form" {
  let types : Array[@types.ValueType] = []
  let values : Array[@types.Value] = []
  for i in 0..<10 {
    types.push(I32)
    types.push(I64)
    types.push(F32)
    types.push(F64)
    values.push(I32(-100 - i))
    values.push(I64(123456789012345L + i.to_int64()))
    values.push(F32(Float::from_int(i) + 0.25))
    values.push(F64(-i.to_double() - 0.5))
  }
  types.push(V128)
  values.push(
    V128(b"\x01\x23\x45\x67\x89\xab\xcd\xef\xfe\xdc\xba\x98\x76\x54\x32\x10"),
  )
  let signature = "i32 i64 f32 f64 ".repeat(10) + "v128"
  let arguments = Array::makei(types.length(), i => "local.get \{i}").join(" ")
  let calls = [
    "call $host", "return_call $host", "i32.const 0 call_indirect (type $sig)", "i32.const 0 return_call_indirect (type $sig)",
    "ref.func $host call_ref $sig", "ref.func $host return_call_ref $sig",
  ]
  let wrappers = Array::makei(calls.length(), i => {
    "(func (export \"call\{i}\") (type $sig) \{arguments} \{calls[i]})"
  }).join(" ")
  let source = "(module (type $sig (func (param \{signature}) (result \{signature}))) (import \"spectest\" \"print_i32\" (func $host (type $sig))) (table 1 funcref) (elem (i32.const 0) $host) \{wrappers})"
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for native in [false, true] {
    let store = @runtime.Store::with_c_heap()
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    let observed : Array[Array[@types.Value]] = []
    linker.add_host_func(
      "spectest",
      "print_i32",
      fn(args) {
        observed.push(args.copy())
        args.copy()
      },
      func_type={
        params: ReadOnlyArray::from_array(types),
        results: ReadOnlyArray::from_array(types),
      },
    )
    let instance = @executor.instantiate_with_linker(linker, "guest", module_)
    if native {
      let context = build_gc_root_context(module_, instance, store)
      defer context.close()
      context.install_hostcall_dispatcher(store, instance)
      for index in 1..<=calls.length() {
        assert_eq(
          context.call_core_func(store, instance, index, values),
          values,
          msg="native function \{index}",
        )
      }
    } else {
      for index in 1..<=calls.length() {
        let name = "call\{index - 1}"
        assert_eq(
          @executor.call_exported_func(store, instance, name, values),
          values,
          msg=name,
        )
      }
    }
    assert_eq(observed, Array::make(calls.length(), values))
  }
}

///|
test "builtin hostcall arguments and returns preserve signed zero and NaN payload bits" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (import "spectest" "print_f32" (func $host (param f32 f64) (result f32 f64)))
      #| (func (export "run") (param i32 i64) (result i32 i64) (local f32 f64)
      #|  local.get 0 f32.reinterpret_i32 local.get 1 f64.reinterpret_i64 call $host
      #|  local.set 3 local.set 2
      #|  local.get 2 i32.reinterpret_f32 local.get 3 i64.reinterpret_f64))
    ),
  )
  @validator.validate_module(module_)
  let cases = [
    (0x80000000, 0x8000000000000000L),
    (0x7fc12345, 0xfff8000000001234L),
    (0xff800000, 0x7ff0000000000000L),
  ]
  for native in [false, true] {
    let store = @runtime.Store::with_c_heap()
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    let observed : Array[(@types.Value, @types.Value)] = []
    linker.add_host_func(
      "spectest",
      "print_f32",
      fn(args) raise @runtime.RuntimeError {
        guard args is [F32(f), F64(d)] else { raise Unreachable }
        observed.push(
          (I32(f.reinterpret_as_int()), I64(d.reinterpret_as_int64())),
        )
        args.copy()
      },
      func_type={ params: [F32, F64], results: [F32, F64], },
    )
    let instance = @executor.instantiate_with_linker(linker, "guest", module_)
    if native {
      let context = build_gc_root_context(module_, instance, store)
      defer context.close()
      context.install_hostcall_dispatcher(store, instance)
      for (f, d) in cases {
        assert_eq(
          context.call_core_func(store, instance, 1, [I32(f), I64(d)]),
          [I32(f), I64(d)],
        )
      }
    } else {
      for (f, d) in cases {
        assert_eq(
          @executor.call_exported_func(store, instance, "run", [I32(f), I64(d)]),
          [I32(f), I64(d)],
        )
      }
    }
    assert_eq(observed, cases.map(pair => (I32(pair.0), I64(pair.1))))
  }
}
