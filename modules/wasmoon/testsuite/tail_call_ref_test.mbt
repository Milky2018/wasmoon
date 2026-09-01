///|
test "JIT preserves GC metadata for return_call_ref" {
  let source =
    #|(module
    #|  (type $callee (func (param i64) (result i64)))
    #|  (func $identity (type $callee) (param i64) (result i64)
    #|    local.get 0
    #|  )
    #|  (elem declare func $identity)
    #|  (global $identity (ref $callee) (ref.func $identity))
    #|  (func (export "test") (result i64)
    #|    i64.const 42
    #|    global.get $identity
    #|    return_call_ref $callee
    #|  )
    #|)
  inspect(compare_jit_interp(source, "test", []), content="matched")
}
