///|
test "polled leaf inlining cross compiles with precise safepoints on both targets" {
  let module_ = @core_wat.parse(
    (
      #|(module (type $a (array i32))
      #| (func $leaf (param (ref $a)) (result i32) local.get 0 i32.const 0 array.get $a)
      #| (func (export "run") (param (ref $a)) (result i32) local.get 0 call $leaf))
    ),
  )
  @validator.validate_module(module_)
  let shape = @wasmoon_jit.context_shape(module_)
  let context = @wasm_frontend.translation_context_from_module(
    module_,
    @wasmoon.wasm_frontend_embedding_environment(
      context_shape=shape,
      cancellation_safepoints=true,
    ),
  )
  let validation = @wasm_frontend.wasm_validation_context(context)
  let scalar_callees = @wasm_frontend.scalar_callees(context, module_)
  for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
    let compiler = @wasmoon_jit.NativeCompiler::new(target, context_shape=shape)
    for level in [0, 2] {
      let ty = module_.validated_func_type_at(module_.funcs[1])
      let function = @wasm_frontend.translate_function_body(
        context,
        "polled_array",
        ty,
        module_.codes[1].locals,
        module_.codes[1].body,
      )
      @wasm_optimize.optimize_with_level(
        function,
        validation,
        @optimize.OptLevel::from_int(level),
        scalar_callees~,
      )
      |> ignore
      let mut calls = 0
      for block in function.blocks {
        for id in function.block_instruction_ids(block) {
          if @wasm_milkir.decode_opcode(
              function.instruction_by_id(id).unwrap().opcode,
            )
            is Some(WasmCall(_)) {
            calls += 1
          }
        }
      }
      assert_eq(calls, if level == 0 { 1 } else { 0 })
      let compiled = compiler.compile_wasm_body_artifact_function(
        function,
        validation,
        function_index=1,
        signature=@wasmoon_jit.wasm_function_signature(ty),
      )
      assert_false(compiled.code.is_empty())
      assert_false(compiled.safepoints.is_empty())
    }
  }
}

///|
test "both targets retain logical reference carriers in checked physical loads" {
  let module_ = @core_wat.parse(
    (
      #|(module (type $f (func (result i64)))
      #| (type $n (struct (field (ref null $f)) (field externref) (field i64)))
      #| (func (param (ref $n)) (result (ref null $f) externref i64)
      #|  local.get 0 struct.get $n 0 local.get 0 struct.get $n 1 local.get 0 struct.get $n 2))
    ),
  )
  @validator.validate_module(module_)
  let shape = @wasmoon_jit.context_shape(module_)
  let context = @wasm_frontend.translation_context_from_module(
    module_,
    @wasmoon.wasm_frontend_embedding_environment(context_shape=shape),
  )
  let validation = @wasm_frontend.wasm_validation_context(context)
  for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
    let compiler = @wasmoon_jit.NativeCompiler::new(target, context_shape=shape)
    let ty = module_.validated_func_type_at(module_.funcs[0])
    let function = @wasm_frontend.translate_function_body(
      context,
      "typed_carrier_loads",
      ty,
      module_.codes[0].locals,
      module_.codes[0].body,
    )
    let compiled = compiler.compile_wasm_body_artifact_function(
      function,
      validation,
      function_index=0,
      signature=@wasmoon_jit.wasm_function_signature(ty),
    )
    let mut callable = false
    let mut opaque_loaded = false
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        match function.instruction_by_id(id).unwrap().opcode {
          Memory(Load(CallableRef)) => callable = true
          Memory(Load(OpaqueRef)) => opaque_loaded = true
          _ => ()
        }
      }
    }
    assert_true(callable && opaque_loaded)
    assert_false(compiled.code.is_empty())
  }
}

///|
test "full and partial native artifacts emit one direct call" {
  let source =
    #|(module (type $n (struct (field i64) (field i64)))
    #| (func $leaf (param (ref $n)) (result i64)
    #|  local.get 0 struct.get $n 0 i64.const 3 i64.div_s i64.const 5 i64.div_s)
    #| (func $wrapper (param (ref $n)) (result i64) local.get 0 call $leaf)
    #| (func (param (ref $n)) (result i64)
    #|  local.get 0 struct.get $n 0 local.get 0 call $wrapper i64.add
    #|  local.get 0 struct.get $n 1 i64.add))
  let module_ = @core_wat.parse(source)
  for partial in [false, true] {
    guard compile_module_to_jit(
        module_,
        false,
        false,
        2,
        false,
        enable_cancellation=true,
        local_compile_mask=if partial {
          Some([false, false, true])
        } else {
          None
        },
      )
      is Some((artifact, _)) else {
      fail("failed to compile native availability fixture")
    }
    guard artifact.functions.filter(f => f.identity.function_index == 2)
      is [caller] else {
      fail("expected exactly one compiled caller")
    }
    let calls = caller.relocations
      .filter(relocation => {
        relocation.target is Code(symbol) && symbol.name == "wasm.func.1"
      })
      .length()
    assert_eq(calls, 1)
  }
}

///|
test "progress reentry cannot replace a snapshotted compilation body" {
  let source =
    #|(module (type $n (struct (field i64) (field i64)))
    #| (func $caller (param (ref $n)) (result i64)
    #|  local.get 0 struct.get $n 0 local.get 0 call $leaf i64.add
    #|  local.get 0 struct.get $n 1 i64.add)
    #| (func $leaf (param (ref $n)) (result i64)
    #|  local.get 0 struct.get $n 0 i64.const 3 i64.div_s i64.const 5 i64.div_s))
  let replacement = @core_wat.parse(
    "(module (type $n (struct (field i64) (field i64))) (func (param (ref $n)) (result i64) i64.const 99 i64.const 7 struct.new $n struct.get $n 0))",
  )
  let module_ = @core_wat.parse(source)
  guard compile_module_to_jit(
      module_,
      false,
      false,
      2,
      false,
      enable_cancellation=true,
    )
    is Some((control, _)) else {
    fail("failed to compile source control")
  }
  let changed = Ref(false)
  guard compile_module_to_jit(
      module_,
      false,
      false,
      2,
      false,
      enable_cancellation=true,
      on_progress=event => {
        if !changed.val && event.stage is Translate && event.func_idx == Some(0) {
          module_.codes[1] = replacement.codes[0]
          changed.val = true
        }
        None
      },
    )
    is Some((compiled, _)) else {
    fail("source snapshot did not compile")
  }
  assert_true(changed.val)
  assert_eq(module_.codes[1], replacement.codes[0])
  assert_eq(compiled, control)
}

///|
test "progress reentry cannot mutate the admitted native compilation mask" {
  let module_ = @core_wat.parse(
    "(module (func i32.const 1 drop) (func i32.const 2 drop))",
  )
  let mask = [true, true]
  let changed = Ref(false)
  guard compile_module_to_jit(
      module_,
      false,
      false,
      2,
      false,
      local_compile_mask=Some(mask),
      on_progress=event => {
        if !changed.val && event.stage is Translate {
          mask[1] = false
          changed.val = true
        }
        None
      },
    )
    is Some((compiled, _)) else {
    fail("mask snapshot did not compile")
  }
  assert_true(changed.val)
  assert_eq(mask, [true, false])
  assert_eq(compiled.functions.map(f => f.identity.function_index), [0, 1])
}
