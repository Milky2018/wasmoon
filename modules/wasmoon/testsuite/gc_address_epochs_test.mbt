///|
test "GC address epochs preserve logical reads through allocation and alias writes" {
  let source =
    #|(module
    #| (type $s (struct (field (mut i64)) (field i64)))
    #| (func (export "test") (result i64)
    #|  (local $object (ref null $s)) (local $alias (ref null $s))
    #|  (local $before i64) (local $after i64) (local $i i32)
    #|  (local.set $object (struct.new $s (i64.const 37) (i64.const 5)))
    #|  (local.set $alias (local.get $object))
    #|  (local.set $before (struct.get $s 0 (local.get $object)))
    #|  (loop $allocate
    #|   (drop (struct.new $s (i64.const 99) (i64.const 101)))
    #|   (local.set $i (i32.add (local.get $i) (i32.const 1)))
    #|   (br_if $allocate (i32.lt_u (local.get $i) (i32.const 20000))))
    #|  (local.set $after (struct.get $s 0 (local.get $object)))
    #|  (struct.set $s 0 (local.get $alias) (i64.const 53))
    #|  (i64.add (i64.add (local.get $before) (local.get $after))
    #|   (i64.add (struct.get $s 0 (local.get $object))
    #|            (struct.get $s 1 (local.get $object)))))
    #|)
  inspect(@testsuite.compare_jit_interp(source, "test", []), content="matched")
}
