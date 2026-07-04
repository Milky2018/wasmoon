///|
test "lower empty wasm function through embedding environment" {
  let mod_ = @types.Module::simple([], [], [], "run")
  let env = EmbeddingEnvironment::new()
  let func = lower_function(env, mod_, 0)
  inspect(func.name, content="wasm_func_0")
  inspect(func.signature.params.length(), content="1")
  inspect(func.signature.results.length(), content="0")
  inspect(func.blocks.length(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "lower unsupported body as generic MilkIR trap" {
  let mod_ = @types.Module::simple([], [], [Nop], "run")
  let env = EmbeddingEnvironment::new(hidden_context_type=None)
  let func = lower_function(env, mod_, 0)
  inspect(func.signature.params.length(), content="0")
  inspect(func.blocks[0].instructions.length(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "lower rejects missing wasm function" {
  let mod_ = @types.Module::empty()
  let env = EmbeddingEnvironment::new()
  try lower_function(env, mod_, 0) catch {
    err => inspect(err, content="FunctionIndexOutOfRange(index=0)")
  } noraise {
    _ => fail("expected missing wasm function")
  }
}
