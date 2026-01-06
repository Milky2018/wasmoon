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
      #|vcode test(v0:int, v1:int, v2:int, v3:int) {
      #|block0:
      #|    v4 = ldi 200
      #|    v5 = ldi 0
      #|    v6 = load_ptr.i64 +0 v0
      #|    v7 = ldi 8
      #|    v8 = load_ptr.i64 +8 v0
      #|    v9 = mov v4
      #|    v10 = ldi 1
      #|    v11 = add #1 v4
      #|    v12 = cmp.ule v11, v8
      #|    br_cmp.ls v11, v8, block2, block1
      #|block1:
      #|    trap "memory out of bounds"
      #|block2:
      #|    v13 = add v6, v9
      #|    store_ptr8 +0 v13, v2
      #|    v14 = ldi 201
      #|    v15 = load_ptr.i64 +0 v0
      #|    v16 = load_ptr.i64 +8 v0
      #|    v17 = mov v14
      #|    v18 = add #1 v14
      #|    v19 = cmp.ule v18, v16
      #|    br_cmp.ls v18, v16, block3, block1
      #|block3:
      #|    v20 = add v15, v17
      #|    store_ptr8 +0 v20, v3
      #|    ret
      #|}
      #|
    ),
  )
}
