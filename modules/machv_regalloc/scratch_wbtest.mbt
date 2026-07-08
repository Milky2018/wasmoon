///|
test "reserve_scratch picks distinct registers per spill slot" {
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let p2 : @machv.PReg = { index: 2, class: Int }
  let bindings : Array[ScratchBinding] = []
  let s0 = reserve_scratch([p0, p1, p2], bindings, 0, Int)
  let s1 = reserve_scratch([p0, p1, p2], bindings, 1, Int)
  inspect(s0 != s1, content="true")
  inspect(reserve_scratch([p0, p1, p2], bindings, 0, Int) == s0, content="true")
}

///|
test "reserve_scratch respects vector register class" {
  let v0 : @machv.PReg = { index: 0, class: Vector }
  let v1 : @machv.PReg = { index: 1, class: Vector }
  let bindings : Array[ScratchBinding] = []
  let scratch = reserve_scratch([v0, v1], bindings, 0, Vector)
  debug_inspect(scratch, content="Some({ index: 1, class: Vector })")
}
