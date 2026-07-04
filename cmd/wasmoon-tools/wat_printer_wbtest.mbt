///|
test "wat_printer: element segments" {
  let mod_ = @types.Module::new()
  mod_.elems.push({
    mode: Passive,
    type_: FuncRef,
    init: [[RefFunc(0)], [RefFunc(1)]],
  })
  mod_.elems.push({
    mode: Active(0, [I32Const(0)]),
    type_: FuncRef,
    init: [[RefFunc(0)], [RefFunc(1)]],
  })
  mod_.elems.push({ mode: Declarative, type_: FuncRef, init: [[RefFunc(0)]] })
  let output = module_to_wat(mod_)
  let expected =
    #|(module
    #|  (elem (;0;) funcref (ref.func 0) (ref.func 1))
    #|  (elem (;1;) (i32.const 0) funcref (ref.func 0) (ref.func 1))
    #|  (elem (;2;) declare funcref (ref.func 0))
    #|)
    #|
  inspect(output, content=expected)
}
