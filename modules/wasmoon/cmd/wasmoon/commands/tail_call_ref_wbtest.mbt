///|
test "mixed stack reference tail calls cross compile on both native targets" {
  // Exercise every call form through the production artifact compiler even on ARM hosts.
  for repeats in [8, 10] {
    let signature = "i32 i64 f32 f64 ".repeat(repeats) + "v128"
    let arguments = Array::makei(repeats * 4 + 1, i => "local.get \{i}").join(
      " ",
    )
    let calls = [
      "call $host", "return_call $host", "i32.const 0 call_indirect (type $sig)",
      "i32.const 0 return_call_indirect (type $sig)", "ref.func $host call_ref $sig",
      "ref.func $host return_call_ref $sig",
    ]
    let wrappers = Array::makei(calls.length(), i => {
      "(func (export \"call\{i}\") (type $sig) \{arguments} \{calls[i]})"
    }).join(" ")
    let module_ = @core_wat.parse(
      "(module (type $sig (func (param \{signature}) (result \{signature}))) (import \"host\" \"f\" (func $host (type $sig))) (table 1 funcref) (elem (i32.const 0) $host) \{wrappers})",
    )
    @validator.validate_module(module_)
    for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
      let shape = @wasmoon_jit.context_shape(module_)
      let compiler = @wasmoon_jit.NativeCompiler::new(
        target,
        context_shape=shape,
      )
      let context = @wasm_frontend.translation_context_from_module(
        module_,
        @wasmoon.wasm_frontend_embedding_environment(context_shape=shape),
      )
      let validation = @wasm_frontend.wasm_validation_context(context)
      for level in [0, 2] {
        for i, code in module_.codes {
          let func_type = module_.validated_func_type_at(module_.funcs[i])
          let function = @wasm_frontend.translate_function_body(
            context,
            "call\{i}",
            func_type,
            code.locals,
            code.body,
          )
          @optimize.optimize_with_level(
            function,
            @optimize.OptLevel::from_int(level),
          )
          |> ignore
          let compiled = compiler.compile_wasm_body_artifact_function(
            function,
            validation,
            function_index=i + 1,
            signature=@wasmoon_jit.wasm_function_signature(func_type),
          )
          assert_false(compiled.code.is_empty())
        }
      }
    }
  }
}
