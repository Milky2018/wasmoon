///|
test "standalone indirect table initialization preserves callable entries" {
  let module_ = @wat.parse(
    "(module (type $t (func (result i32))) (func $f (type $t) i32.const 42) (table 1 funcref) (func (export \"run\") (result i32) i32.const 0 call_indirect (type $t)))",
  )
  @validator.validate_module(module_)
  guard @commands.compile_module_to_jit(module_, false, false, 0, false)
    is Some((artifact, debug_db)) else {
    fail("JIT compilation failed")
  }
  let loaded = @commands.verify_compiled_jit_artifact(artifact)
  let jm = @jit.JITModule::load_artifact_with_imports(
    loaded,
    @wast.build_func_signatures(module_),
    {},
    function_names=@commands.build_jit_function_names(module_),
    debug_db~,
  )
  defer jm.close()
  jm.init_indirect_table(1, [(0, 0, module_.funcs[0])])
  let run = jm.get_func_by_name("run").unwrap()
  assert_eq(jm.call_with_context(run, []), [42L])
}
