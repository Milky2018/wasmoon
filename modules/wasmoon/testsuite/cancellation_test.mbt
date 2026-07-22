///|
test "JIT controlled call cancels at loop safepoint" {
  let source =
    #|(module
    #|  (func (export "run") (result i32)
    #|    (local $i i32)
    #|    (loop $loop
    #|      local.get $i
    #|      i32.const 1
    #|      i32.add
    #|      local.tee $i
    #|      i32.const 5
    #|      i32.lt_s
    #|      br_if $loop)
    #|    local.get $i))
  let mod_ = @wat.parse(source)
  guard @commands.compile_module_to_jit(
      mod_,
      false,
      false,
      0,
      false,
      enable_cancellation=true,
    )
    is Some((artifact, debug_db)) else {
    fail("JIT compile returned unsupported")
  }
  let jm = @jit.JITModule::load_artifact(
    @commands.verify_compiled_jit_artifact(artifact),
    @wast.build_func_signatures(mod_),
    function_names=@commands.build_jit_function_names(mod_),
    debug_db~,
  )
  guard jm.get_func_by_name("run") is Some(func) else {
    fail("compiled function not found")
  }
  let polls = [0]
  debug_inspect(
    jm.call_with_context_controlled(
      func,
      [],
      cancel=Some(fn() {
        polls[0] = polls[0] + 1
        polls[0] >= 3
      }),
    ),
    content="Cancelled",
  )
  debug_inspect(polls, content="[3]")
}

///|
test "JIT controlled call rejects an uninstrumented artifact" {
  let source =
    #|(module (func (export "run") (result i32) i32.const 42))
  let mod_ = @wat.parse(source)
  guard @commands.compile_module_to_jit(mod_, false, false, 0, false)
    is Some((artifact, debug_db)) else {
    fail("JIT compile returned unsupported")
  }
  let jm = @jit.JITModule::load_artifact(
    @commands.verify_compiled_jit_artifact(artifact),
    @wast.build_func_signatures(mod_),
    function_names=@commands.build_jit_function_names(mod_),
    debug_db~,
  )
  guard jm.get_func_by_name("run") is Some(func) else {
    fail("compiled function not found")
  }
  debug_inspect(
    jm.call_with_context_controlled(func, [], cancel=Some(fn() { false })),
    content="UnsupportedCancellation",
  )
}
