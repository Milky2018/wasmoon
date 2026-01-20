///|
/// Test for store merging peephole optimization
test "store_merging_peephole" {
  // Test case: two adjacent store8 with constant addresses
  // Similar to benchmark.wat's $print_num function
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i32 i32)
    #|    ;; store8 at constant address 200
    #|    (i32.store8 (i32.const 200) (local.get 0))
    #|    ;; store8 at constant address 201
    #|    (i32.store8 (i32.const 201) (local.get 1))
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  @ir.optimize(ir_func) |> ignore
  let vcode = @lower.lower_function(ir_func)

  // Print VCode to see if store merging happened
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int, v2:int) {
      #|block0:
      #|    v4 = load_mem_base mem=0 x21
      #|    v6 = add #200 v4
      #|    store_ptr8 +200 v4, v1
      #|    v8 = add #201 v4
      #|    store_ptr8 +201 v4, v2
      #|    ret
      #|}
      #|
    ),
  )
}
