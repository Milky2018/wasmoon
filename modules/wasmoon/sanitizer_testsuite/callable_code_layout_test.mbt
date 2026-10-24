///|
test "context-bound callable entries share compact immutable storage" {
  let functions = Array::makei(64, i => "(func $f\{i} (type $t) i32.const \{i})").join(
    "\n",
  )
  let module_ = @wat.parse(
    "(module (type $t (func (result i32))) \{functions} (table 64 funcref) (func (export \"dispatch\") (param i32) (result i32) local.get 0 call_indirect (type $t)))",
  )
  @validator.validate_module(module_)
  guard @commands.compile_module_to_jit(module_, false, false, 0, false)
    is Some((artifact, debug_db)) else {
    fail("callable layout compilation failed")
  }
  let module_ = @jit.JITModule::load_artifact_with_imports(
    @commands.verify_compiled_jit_artifact(artifact),
    @wast.build_func_signatures(module_),
    {},
    function_names=@commands.build_jit_function_names(module_),
    debug_db~,
  )
  defer module_.close()
  // Type zero is the common no-argument i32 result signature.
  module_.init_indirect_table(64, Array::makei(64, i => (i, i, 0)))
  let dispatch = module_.get_func_by_name("dispatch").unwrap()
  let mut first = module_.get_func_ptr(0)
  let mut last = first
  for i in 0..<64 {
    assert_eq(module_.call_with_context(dispatch, [i.to_int64()]), [
      i.to_int64(),
    ])
    let entry = module_.get_func_ptr(i)
    assert_true(entry != 0L)
    if entry < first {
      first = entry
    }
    if entry > last {
      last = entry
    }
  }
  // Sixty-four small leaf bindings fit in 4 KiB on either supported target.
  assert_true(last - first < 4096L)
}
