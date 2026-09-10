///|
test "fixed lists flatten parameters and lift indirect results without realloc" {
  let source =
    #|(component
    #|  (type $pair (list u32 2))
    #|  (type $matrix (list $pair 2))
    #|  (core module $M
    #|    (memory (export "memory") 1)
    #|    (func (export "roundtrip") (param i32 i32 i32 i32) (result i32)
    #|      i32.const 8 local.get 0 i32.store
    #|      i32.const 12 local.get 1 i32.store
    #|      i32.const 16 local.get 2 i32.store
    #|      i32.const 20 local.get 3 i32.store
    #|      i32.const 8))
    #|  (core instance $m (instantiate $M))
    #|  (func (export "roundtrip") (param "x" $matrix) (result $matrix)
    #|    (canon lift (core func $m "roundtrip") (memory (core memory $m "memory")))))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  for native in [false, true] {
    let engine = if native {
      open_native_component_session(opt_level=0)
    } else {
      @runtime_impl.interpreter_core_execution_engine()
    }
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
    )
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    debug_inspect(
      instance.call_exported_func("roundtrip", [
        List([List([U32(1), U32(2)]), List([U32(3), U32(4)])]),
      ]),
      content="[List([List([U32(1), U32(2)]), List([U32(3), U32(4)])])]",
    )
    let error = try {
      instance.call_exported_func("roundtrip", [List([List([U32(1)])])])
      |> ignore
      "missing error"
    } catch {
      error => error.to_string()
    }
    inspect(error.contains("type mismatch"), content="true")
  }
}

///|
test "fixed list result preserves padded element stride" {
  let source =
    #|(component
    #|  (type $item (tuple u8 u64 u8))
    #|  (type $list (list $item 2))
    #|  (core module $M
    #|    (memory (export "memory") 1)
    #|    (func (export "get") (result i32)
    #|      i32.const 0 i32.const 1 i32.store8
    #|      i32.const 8 i64.const 2 i64.store
    #|      i32.const 16 i32.const 3 i32.store8
    #|      i32.const 24 i32.const 4 i32.store8
    #|      i32.const 32 i64.const 5 i64.store
    #|      i32.const 40 i32.const 6 i32.store8
    #|      i32.const 0))
    #|  (core instance $m (instantiate $M))
    #|  (func (export "get") (result $list)
    #|    (canon lift (core func $m "get") (memory (core memory $m "memory")))))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  for native in [false, true] {
    let engine = if native {
      open_native_component_session(opt_level=0)
    } else {
      @runtime_impl.interpreter_core_execution_engine()
    }
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
    )
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    debug_inspect(
      instance.call_exported_func("get", []),
      content="[List([([U8(1), U64(2), U8(3)]), ([U8(4), U64(5), U8(6)])])]",
    )
  }
}

///|
test "indirect fixed-list parameters preserve element padding" {
  let source =
    #|(component
    #|  (type $item (tuple u8 u64 u8))
    #|  (type $list (list $item 6))
    #|  (core module $M
    #|    (memory (export "memory") 1)
    #|    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
    #|      local.get 2 i32.const 8 i32.ne if unreachable end
    #|      local.get 3 i32.const 144 i32.ne if unreachable end
    #|      i32.const 64)
    #|    (func (export "roundtrip") (param $ptr i32) (result i32)
    #|      local.get $ptr i32.load8_u offset=24 i32.const 4 i32.ne if unreachable end
    #|      local.get $ptr i64.load offset=32 i64.const 5 i64.ne if unreachable end
    #|      local.get $ptr i32.load8_u offset=136 i32.const 18 i32.ne if unreachable end
    #|      local.get $ptr))
    #|  (core instance $m (instantiate $M))
    #|  (func (export "roundtrip") (param "x" $list) (result $list)
    #|    (canon lift (core func $m "roundtrip") (memory (core memory $m "memory"))
    #|      (realloc (func $m "realloc")))))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  for native in [false, true] {
    let engine = if native {
      open_native_component_session(opt_level=0)
    } else {
      @runtime_impl.interpreter_core_execution_engine()
    }
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
    )
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    let values : Array[@runtime_impl.ComponentValue] = []
    for i in 0..<6 {
      values.push(
        Tuple([U8(i * 3 + 1), U64((i * 3 + 2).to_int64()), U8(i * 3 + 3)]),
      )
    }
    debug_inspect(
      instance.call_exported_func("roundtrip", [List(values)]),
      content=(
        #|[
        #|  List(
        #|    [
        #|      ([U8(1), U64(2), U8(3)]),
        #|      ([U8(4), U64(5), U8(6)]),
        #|      ([U8(7), U64(8), U8(9)]),
        #|      ([U8(10), U64(11), U8(12)]),
        #|      ([U8(13), U64(14), U8(15)]),
        #|      ([U8(16), U64(17), U8(18)]),
        #|    ],
        #|  ),
        #|]
      ),
    )
  }
}

///|
test "single-element fixed-list results lower to one scalar" {
  let source =
    #|(component
    #|  (component $A
    #|    (type $one (list u32 1))
    #|    (core module $M (func (export "get") (result i32) i32.const 42))
    #|    (core instance $m (instantiate $M))
    #|    (func (export "get") (result $one) (canon lift (core func $m "get"))))
    #|  (component $B
    #|    (type $one (list u32 1))
    #|    (import "get" (func $get (result $one)))
    #|    (core func $get (canon lower (func $get)))
    #|    (core module $M
    #|      (import "" "get" (func $get (result i32)))
    #|      (func (export "run") (result i32) call $get))
    #|    (core instance $m (instantiate $M (with "" (instance (export "get" (func $get))))))
    #|    (func (export "run") (result u32) (canon lift (core func $m "run"))))
    #|  (instance $a (instantiate $A))
    #|  (instance $b (instantiate $B (with "get" (func $a "get"))))
    #|  (export "run" (func $b "run")))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(@component_text.parse_component_wat(source)),
    ComponentValidationConfig(false),
  )
  for native in [false, true] {
    let engine = if native {
      open_native_component_session(opt_level=0)
    } else {
      @runtime_impl.interpreter_core_execution_engine()
    }
    let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
      engine,
    )
    defer linker.close()
    let instance = linker.instantiate("root", validated)
    debug_inspect(instance.call_exported_func("run", []), content="[U32(42)]")
  }
}
