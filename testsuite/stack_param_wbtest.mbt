///|
test "i64 7 params - get param 6 (first stack param)" {
  let source =
    #|(module
    #|  (func (export "get_p6")
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64)
    #|        (result i64)
    #|    (local.get 6))
    #|)
  let result = compare_jit_interp(source, "get_p6", [
    I64(1L),
    I64(2L),
    I64(3L),
    I64(4L),
    I64(5L),
    I64(6L),
    I64(7L),
  ])
  inspect(result, content="matched")
}

///|
test "i64 37 params - sum all" {
  let source =
    #|(module
    #|  (func (export "sum37")
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (result i64)
    #|    (local $sum i64)
    #|    (local.set $sum (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 0) (local.get 1)) (local.get 2)) (local.get 3)) (local.get 4)) (local.get 5)) (local.get 6)) (local.get 7)))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 8) (local.get 9)) (local.get 10)) (local.get 11)) (local.get 12)) (local.get 13)) (local.get 14)) (local.get 15))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 16) (local.get 17)) (local.get 18)) (local.get 19)) (local.get 20)) (local.get 21)) (local.get 22)) (local.get 23))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 24) (local.get 25)) (local.get 26)) (local.get 27)) (local.get 28)) (local.get 29)) (local.get 30)) (local.get 31))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 32) (local.get 33)) (local.get 34)) (local.get 35)) (local.get 36))))
    #|    (local.get $sum))
    #|)
  // 1+2+...+37 = 37*38/2 = 703
  let result = compare_jit_interp(source, "sum37", [
    I64(1L),
    I64(2L),
    I64(3L),
    I64(4L),
    I64(5L),
    I64(6L),
    I64(7L),
    I64(8L),
    I64(9L),
    I64(10L),
    I64(11L),
    I64(12L),
    I64(13L),
    I64(14L),
    I64(15L),
    I64(16L),
    I64(17L),
    I64(18L),
    I64(19L),
    I64(20L),
    I64(21L),
    I64(22L),
    I64(23L),
    I64(24L),
    I64(25L),
    I64(26L),
    I64(27L),
    I64(28L),
    I64(29L),
    I64(30L),
    I64(31L),
    I64(32L),
    I64(33L),
    I64(34L),
    I64(35L),
    I64(36L),
    I64(37L),
  ])
  inspect(result, content="matched")
}
