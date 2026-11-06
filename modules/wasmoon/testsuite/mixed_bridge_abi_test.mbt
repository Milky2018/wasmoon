///|
test "entry trampolines agree with internal mixed register overflow arguments" {
  let source =
    #|(module
    #|  (func (export "main") (param f64 f64 f64 f64 f64 f64 f64 f64 f64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) (result i64)
    #|    local.get 8 i64.trunc_f64_s
    #|    local.get 9 i64.add
    #|    local.get 18 i64.add))
  let args : Array[@types.Value] = []
  for i in 0..<9 {
    args.push(F64((i + 1).to_double()))
  }
  for i in 0..<10 {
    args.push(I64((100 + i).to_int64()))
  }
  inspect(
    @testsuite.compare_jit_interp(source, "main", args),
    content="matched",
  )
}

///|
test "entry trampolines agree with internal mixed register overflow results" {
  let source =
    #|(module
    #|  (func (export "main") (result f64 f64 f64 f64 f64 f64 f64 f64 f64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    #|    f64.const 1 f64.const 2 f64.const 3 f64.const 4 f64.const 5 f64.const 6 f64.const 7 f64.const 8 f64.const 9 i64.const 100 i64.const 101 i64.const 102 i64.const 103 i64.const 104 i64.const 105 i64.const 106 i64.const 107 i64.const 108 i64.const 109))
  inspect(@testsuite.compare_jit_interp(source, "main", []), content="matched")
}

///|
test "hostcall trampolines preserve mixed register overflow arguments" {
  let source =
    #|(module
    #|  (import "host" "capture" (func $capture (param f64 f64 f64 f64 f64 f64 f64 f64 f64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) (result i64)))
    #|  (func (export "main") (result i64)
    #|    f64.const 1 f64.const 2 f64.const 3 f64.const 4 f64.const 5 f64.const 6 f64.const 7 f64.const 8 f64.const 9 i64.const 100 i64.const 101 i64.const 102 i64.const 103 i64.const 104 i64.const 105 i64.const 106 i64.const 107 i64.const 108 i64.const 109 call $capture))
  let mod_ = @wat.parse(source)
  let observed : Array[@types.Value] = []
  let linker = @runtime.Linker()
  defer linker.close()
  linker.add_host_func(
    "host",
    "capture",
    args => {
      observed.push_iter(args.iter())
      [I64(42)]
    },
    func_type=mod_.validated_func_type_at(0),
  )
  let store = linker.get_store()
  let instance = @executor.instantiate_with_linker(linker, "guest", mod_)
  let context = prepare_async_jit_context(mod_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  debug_inspect(
    context.call_core_func(store, instance, 1, []),
    content="[I64(42)]",
  )
  let expected : Array[@types.Value] = []
  for i in 0..<9 {
    expected.push(F64((i + 1).to_double()))
  }
  for i in 0..<10 {
    expected.push(I64((100 + i).to_int64()))
  }
  assert_eq(observed, expected)
}

///|
test "hostcall trampolines preserve mixed register overflow results" {
  let source =
    #|(module
    #|  (import "host" "values" (func $values
    #|    (result f64 f64 f64 f64 f64 f64 f64 f64 f64
    #|      i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)))
    #|  (func (export "main") (result i64) (local $last i64) (local $overflow f64)
    #|    call $values
    #|    local.set $last
    #|    drop drop drop drop drop drop drop drop drop
    #|    local.set $overflow
    #|    drop drop drop drop drop drop drop drop
    #|    local.get $last local.get $overflow i64.trunc_f64_s i64.add))
  let mod_ = @wat.parse(source)
  let values : Array[@types.Value] = []
  for i in 0..<9 {
    values.push(F64((i + 1).to_double()))
  }
  for i in 0..<10 {
    values.push(I64((100 + i).to_int64()))
  }
  let linker = @runtime.Linker()
  defer linker.close()
  linker.add_host_func(
    "host",
    "values",
    _ => values.copy(),
    func_type=mod_.validated_func_type_at(0),
  )
  let store = linker.get_store()
  let instance = @executor.instantiate_with_linker(linker, "guest", mod_)
  let context = prepare_async_jit_context(mod_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  debug_inspect(
    context.call_core_func(store, instance, 1, []),
    content="[I64(118)]",
  )
}
