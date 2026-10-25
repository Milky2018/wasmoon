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
