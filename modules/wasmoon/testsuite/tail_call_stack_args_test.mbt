///|
test "tail call with stack overflow args (direct)" {
  let source =
    #|(module
    #|  (func $sum12
    #|    (param i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    #|    (result i64)
    #|    local.get 0
    #|    local.get 1
    #|    i64.add
    #|    local.get 2
    #|    i64.add
    #|    local.get 3
    #|    i64.add
    #|    local.get 4
    #|    i64.add
    #|    local.get 5
    #|    i64.add
    #|    local.get 6
    #|    i64.add
    #|    local.get 7
    #|    i64.add
    #|    local.get 8
    #|    i64.add
    #|    local.get 9
    #|    i64.add
    #|    local.get 10
    #|    i64.add
    #|    local.get 11
    #|    i64.add
    #|  )
    #|  (func (export "main") (result i64)
    #|    i64.const 1
    #|    i64.const 2
    #|    i64.const 3
    #|    i64.const 4
    #|    i64.const 5
    #|    i64.const 6
    #|    i64.const 7
    #|    i64.const 8
    #|    i64.const 9
    #|    i64.const 10
    #|    i64.const 11
    #|    i64.const 12
    #|    return_call $sum12
    #|  )
    #|)
  inspect(@testsuite.compare_jit_interp(source, "main", []), content="matched")
}

///|
test "tail call with stack overflow args (indirect)" {
  let source =
    #|(module
    #|  (type $t12 (func
    #|    (param i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    #|    (result i64)))
    #|  (table 1 funcref)
    #|  (elem (i32.const 0) $sum12)
    #|  (func $sum12
    #|    (type $t12)
    #|    local.get 0
    #|    local.get 1
    #|    i64.add
    #|    local.get 2
    #|    i64.add
    #|    local.get 3
    #|    i64.add
    #|    local.get 4
    #|    i64.add
    #|    local.get 5
    #|    i64.add
    #|    local.get 6
    #|    i64.add
    #|    local.get 7
    #|    i64.add
    #|    local.get 8
    #|    i64.add
    #|    local.get 9
    #|    i64.add
    #|    local.get 10
    #|    i64.add
    #|    local.get 11
    #|    i64.add
    #|  )
    #|  (func (export "main") (result i64)
    #|    i64.const 1
    #|    i64.const 2
    #|    i64.const 3
    #|    i64.const 4
    #|    i64.const 5
    #|    i64.const 6
    #|    i64.const 7
    #|    i64.const 8
    #|    i64.const 9
    #|    i64.const 10
    #|    i64.const 11
    #|    i64.const 12
    #|    i32.const 0
    #|    return_call_indirect (type $t12)
    #|  )
    #|)
  inspect(@testsuite.compare_jit_interp(source, "main", []), content="matched")
}

///|
test "expanded SysV tail calls preserve native helper entry alignment" {
  let probe = @native_test_support.x64_stack_alignment_probe_ptr()
  if probe == 0L {
    return
  }
  let source =
    #|(module
    #|  (import "host" "alignment" (func $probe (result i64)))
    #|  (type $wide (func (param i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) (result i64)))
    #|  (table 1 funcref)
    #|  (elem (i32.const 0) $callee)
    #|  (func $callee (type $wide) (call $probe))
    #|  (func (export "normal") (result i64) (call $probe))
    #|  (func (export "direct") (result i64)
    #|    i64.const 1 i64.const 2 i64.const 3 i64.const 4
    #|    i64.const 5 i64.const 6 i64.const 7 i64.const 8
    #|    i64.const 9 i64.const 10 i64.const 11 i64.const 12
    #|    return_call $callee)
    #|  (func (export "indirect") (result i64)
    #|    i64.const 1 i64.const 2 i64.const 3 i64.const 4
    #|    i64.const 5 i64.const 6 i64.const 7 i64.const 8
    #|    i64.const 9 i64.const 10 i64.const 11 i64.const 12
    #|    i32.const 0 return_call_indirect (type $wide)))
  let mod_ = @wat.parse(source)
  guard @commands.compile_module_to_jit(mod_, false, false, 0, false)
    is Some((artifact, debug_db)) else {
    fail("JIT compilation failed")
  }
  let loaded = @commands.verify_compiled_jit_artifact(artifact)
  let jm = @jit.JITModule::load_artifact_with_imports(
    loaded,
    @wast.build_func_signatures(mod_),
    { "host": { "alignment": probe } },
    function_names=@commands.build_jit_function_names(mod_),
    debug_db~,
  )
  defer jm.close()
  jm.init_indirect_table(1, [(0, 1, mod_.funcs[0])])
  for name in ["normal", "direct", "indirect"] {
    guard jm.get_func_by_name(name) is Some(func) else {
      fail("missing export")
    }
    assert_eq(jm.call_with_context(func, []), [8L])
  }
}
