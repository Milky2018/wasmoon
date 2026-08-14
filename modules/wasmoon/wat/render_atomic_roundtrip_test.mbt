///|
test "canonical renderer round-trips every atomic subopcode" {
  assert_instruction_roundtrip(
    (
      #|
      #|    memory.atomic.notify 1 offset=7 align=1
      #|    memory.atomic.wait32 1 offset=7 align=1
      #|    memory.atomic.wait64 1 offset=7 align=1
      #|    atomic.fence
      #|    i32.atomic.load 1 offset=7 align=1
      #|    i64.atomic.load 1 offset=7 align=1
      #|    i32.atomic.load8_u 1 offset=7 align=1
      #|    i32.atomic.load16_u 1 offset=7 align=1
      #|    i64.atomic.load8_u 1 offset=7 align=1
      #|    i64.atomic.load16_u 1 offset=7 align=1
      #|    i64.atomic.load32_u 1 offset=7 align=1
      #|    i32.atomic.store 1 offset=7 align=1
      #|    i64.atomic.store 1 offset=7 align=1
      #|    i32.atomic.store8 1 offset=7 align=1
      #|    i32.atomic.store16 1 offset=7 align=1
      #|    i64.atomic.store8 1 offset=7 align=1
      #|    i64.atomic.store16 1 offset=7 align=1
      #|    i64.atomic.store32 1 offset=7 align=1
      #|    i32.atomic.rmw.add 1 offset=7 align=1
      #|    i64.atomic.rmw.add 1 offset=7 align=1
      #|    i32.atomic.rmw8.add_u 1 offset=7 align=1
      #|    i32.atomic.rmw16.add_u 1 offset=7 align=1
      #|    i64.atomic.rmw8.add_u 1 offset=7 align=1
      #|    i64.atomic.rmw16.add_u 1 offset=7 align=1
      #|    i64.atomic.rmw32.add_u 1 offset=7 align=1
      #|    i32.atomic.rmw.sub 1 offset=7 align=1
      #|    i64.atomic.rmw.sub 1 offset=7 align=1
      #|    i32.atomic.rmw8.sub_u 1 offset=7 align=1
      #|    i32.atomic.rmw16.sub_u 1 offset=7 align=1
      #|    i64.atomic.rmw8.sub_u 1 offset=7 align=1
      #|    i64.atomic.rmw16.sub_u 1 offset=7 align=1
      #|    i64.atomic.rmw32.sub_u 1 offset=7 align=1
      #|    i32.atomic.rmw.and 1 offset=7 align=1
      #|    i64.atomic.rmw.and 1 offset=7 align=1
      #|    i32.atomic.rmw8.and_u 1 offset=7 align=1
      #|    i32.atomic.rmw16.and_u 1 offset=7 align=1
      #|    i64.atomic.rmw8.and_u 1 offset=7 align=1
      #|    i64.atomic.rmw16.and_u 1 offset=7 align=1
      #|    i64.atomic.rmw32.and_u 1 offset=7 align=1
      #|    i32.atomic.rmw.or 1 offset=7 align=1
      #|    i64.atomic.rmw.or 1 offset=7 align=1
      #|    i32.atomic.rmw8.or_u 1 offset=7 align=1
      #|    i32.atomic.rmw16.or_u 1 offset=7 align=1
      #|    i64.atomic.rmw8.or_u 1 offset=7 align=1
      #|    i64.atomic.rmw16.or_u 1 offset=7 align=1
      #|    i64.atomic.rmw32.or_u 1 offset=7 align=1
      #|    i32.atomic.rmw.xor 1 offset=7 align=1
      #|    i64.atomic.rmw.xor 1 offset=7 align=1
      #|    i32.atomic.rmw8.xor_u 1 offset=7 align=1
      #|    i32.atomic.rmw16.xor_u 1 offset=7 align=1
      #|    i64.atomic.rmw8.xor_u 1 offset=7 align=1
      #|    i64.atomic.rmw16.xor_u 1 offset=7 align=1
      #|    i64.atomic.rmw32.xor_u 1 offset=7 align=1
      #|    i32.atomic.rmw.xchg 1 offset=7 align=1
      #|    i64.atomic.rmw.xchg 1 offset=7 align=1
      #|    i32.atomic.rmw8.xchg_u 1 offset=7 align=1
      #|    i32.atomic.rmw16.xchg_u 1 offset=7 align=1
      #|    i64.atomic.rmw8.xchg_u 1 offset=7 align=1
      #|    i64.atomic.rmw16.xchg_u 1 offset=7 align=1
      #|    i64.atomic.rmw32.xchg_u 1 offset=7 align=1
      #|    i32.atomic.rmw.cmpxchg 1 offset=7 align=1
      #|    i64.atomic.rmw.cmpxchg 1 offset=7 align=1
      #|    i32.atomic.rmw8.cmpxchg_u 1 offset=7 align=1
      #|    i32.atomic.rmw16.cmpxchg_u 1 offset=7 align=1
      #|    i64.atomic.rmw8.cmpxchg_u 1 offset=7 align=1
      #|    i64.atomic.rmw16.cmpxchg_u 1 offset=7 align=1
      #|    i64.atomic.rmw32.cmpxchg_u 1 offset=7 align=1
    ),
  )
}
