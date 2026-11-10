///|
fn dynamic_memory_loop_fixture(
  escaping~ : Bool = false,
) -> @milkir.Function raise {
  let b = @milkir.FunctionBuilder("dynamic_memory_loop")
  let pointer = b.add_param(Ptr)
  let count = b.add_param(I32)
  b.add_result(I32)
  let header = b.create_block()
  let index = b.add_block_param(header, I32)
  let body = b.create_block()
  let latch = b.create_block()
  let exit = b.create_block()
  let answer = b.add_block_param(exit, I32)
  let zero = b.iconst_i32(0)
  b.jump(header, [zero])
  b.switch_to_block(header)
  let condition = b.icmp_slt(index, count)
  b.branch(condition, body, [], exit, [index])
  b.switch_to_block(body)
  let offset = b.iconst_i64(0L)
  let loaded = b.load_ptr(I32, pointer, offset)
  b.store_ptr(I32, pointer, b.iadd(loaded, b.iconst_i32(1)), offset)
  let next = b.iadd(index, b.iconst_i32(1))
  b.jump(latch, [])
  b.switch_to_block(latch)
  b.jump(header, [next])
  b.switch_to_block(exit)
  b.return_([if escaping { index } else { answer }])
  b.finalize()
}

///|
test "dynamic memory unrolling retains both header tests and carried effects" {
  let function = dynamic_memory_loop_fixture()
  let original = function.blocks.copy()
  let header = original[1]
  let latch = original[3]
  let before_stores = function.blocks.fold(init=0, fn(total, block) {
    total +
    function
    .block_instruction_ids(block)
    .filter(id => {
      function.instruction_by_id(id).unwrap().opcode is Memory(Store(_))
    })
    .length()
  })
  assert_true(unroll_dynamic_memory_loop(function).changed)
  function.verify()
  assert_true(latch.terminator is Some(Jump(id, _)) && id != header.id)
  assert_eq(
    function.blocks
    .filter(block => block.terminator is Some(Branch(_, _, _, _, _)))
    .length(),
    2,
  )
  assert_eq(
    function.blocks.fold(init=0, fn(total, block) {
      total +
      function
      .block_instruction_ids(block)
      .filter(id => {
        function.instruction_by_id(id).unwrap().opcode is Memory(Store(_))
      })
      .length()
    }),
    before_stores * 2,
  )
}

///|
test "dynamic memory unrolling declines nonclosed loop values without mutation" {
  let function = dynamic_memory_loop_fixture(escaping=true)
  let before = function.print()
  assert_false(unroll_dynamic_memory_loop(function).changed)
  assert_eq(function.print(), before)
}
