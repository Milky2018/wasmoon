///|
test "JIT shared loop bounds dominate both loop backedges at every optimization level" {
  let source =
    #|(module
    #| (global $count (mut i32) (i32.const 0))
    #| (func $push (param i32) global.get $count i32.const 1 i32.add global.set $count)
    #| (func (export "probe") (result i32)
    #|  (local $limit i32) (local $i i32) (local $more i32) (local $next i32) (local $again i32)
    #|  i32.const 65537 local.set $limit
    #|  i32.const 0 i32.const 1
    #|  loop (param i32 i32)
    #|   local.set $more local.set $i
    #|   local.get $more
    #|   if
    #|    i32.const 0 local.get $i i32.sub call $push
    #|    local.get $i i32.const 1 i32.add local.set $next
    #|    local.get $i local.get $limit i32.lt_s local.set $again
    #|    local.get $next local.get $again br 1
    #|   end
    #|  end
    #|  i32.const 0 i32.const 1
    #|  loop (param i32 i32)
    #|   local.set $more local.set $i
    #|   local.get $more
    #|   if
    #|    i32.const 0 local.get $i i32.sub call $push
    #|    local.get $i i32.const 1 i32.add local.set $next
    #|    local.get $i local.get $limit i32.lt_s local.set $again
    #|    local.get $next local.get $again br 1
    #|   end
    #|  end
    #|  global.get $count)
    #| (func (export "_start") call 1 i32.const 131076 i32.ne if unreachable end))
  for level in [0, 1, 2, 3] {
    inspect(
      @testsuite.compare_jit_interp_with_opt_level(source, "probe", [], level),
      content="matched",
    )
  }
}
