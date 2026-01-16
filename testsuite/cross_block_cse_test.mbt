///|
/// Test for cross-block common subexpression elimination
/// This test verifies that global CSE correctly eliminates redundant
/// computations across basic blocks
test "cross_block_cse" {
  // This function computes p0 + p1 twice:
  // 1. First in the entry block (stored in local $sum)
  // 2. Again in the then branch
  // Global CSE should eliminate the second computation
  let source =
    #|(module
    #|  (func (export "test") (param i32 i32) (result i32)
    #|    (local $sum i32)
    #|    ;; Compute p0 + p1 in entry block
    #|    (local.set $sum (i32.add (local.get 0) (local.get 1)))
    #|    ;; Branch and compute same expression again
    #|    (if (result i32) (local.get 0)
    #|      (then
    #|        ;; Compute p0 + p1 again - should be CSE'd
    #|        (i32.add (i32.add (local.get 0) (local.get 1)) (i32.const 1))
    #|      )
    #|      (else
    #|        ;; Use the original sum
    #|        (local.get $sum)
    #|      )
    #|    )
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)

  // Get locals from the function code
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }

  // Create translator and translate WASM to IR
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)

  // The unoptimized IR should have two iadd instructions computing p0 + p1
  let unopt_ir = ir_func.print()
  inspect(
    unopt_ir,
    content=(
      #|function test(v0:i64, v1:i64, v2:i32, v3:i32) -> i32 {
      #|block0:
      #|    v4:i32 = iconst 0
      #|    v5:i32 = iadd v2, v3
      #|    brnz v2, block1, block2
      #|block1:
      #|    v10:i32 = iadd v2, v3
      #|    v11:i32 = iconst 1
      #|    v12:i32 = iadd v10, v11
      #|    jump block3(v12, v2, v3, v5)
      #|block2:
      #|    jump block3(v5, v2, v3, v5)
      #|block3(v6:i32, v7:i32, v8:i32, v9:i32):
      #|    return v6
      #|}
      #|
    ),
  )

  // Run optimizations including global CSE
  @ir.optimize(ir_func) |> ignore

  // After global CSE, the second iadd v2, v3 in block1 should be eliminated
  // and replaced with v5 from block0
  let opt_ir = ir_func.print()
  inspect(
    opt_ir,
    content=(
      #|function test(v0:i64, v1:i64, v2:i32, v3:i32) -> i32 {
      #|block0:
      #|    v5:i32 = iadd v2, v3
      #|    brnz v2, block1, block2
      #|block1:
      #|    v11:i32 = iconst 1
      #|    v12:i32 = iadd v5, v11
      #|    jump block3(v12)
      #|block2:
      #|    jump block3(v5)
      #|block3(v6:i32):
      #|    return v6
      #|}
      #|
    ),
  )

  // Lower to vcode and generate machine code to verify CSE affects codegen
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int, v2:int, v3:int) -> int {
      #|block0:
      #|    v5 = add32 v2, v3
      #|    cbnz v2, block1, block2
      #|block1:
      #|    v6 = ldi 1
      #|    v7 = add32 #1 v5
      #|    jump block3 (v7)
      #|block2:
      #|    jump block3 (v5)
      #|block3(v4:int):
      #|    ret v4
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, v2:int, v3:int) -> int {
      #|block0:
      #|    x8 = add32 x2, x3
      #|    cbnz x2, block1, block2
      #|block1:
      #|    x8 = add32 #1 x8
      #|    jump block3
      #|block2:
      #|    jump block3
      #|block3(v4:int):
      #|    ret x8
      #|}
      #|
    ),
  )

  // Generate machine code - the key thing is there's only ONE add instruction
  // for v2+v3, not two. Without global CSE, block1 would have an extra add.
  let mc = @emit.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|block0:
      #|  0000: 4800030b  add w8, w2, w3
      #|  0004: 62000034  cbz w2, block2
      #|block1:
      #|  0008: 08050011  add w8, w8, #1
      #|  000c: 02000014  b block3
      #|block2:
      #|  0010: 01000014  b block3
      #|block3:
      #|  0014: e00308aa  mov x0, x8
      #|  0018: c0035fd6  ret
      #|
    ),
  )
}
