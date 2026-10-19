(module
  (import "spectest" "print_char" (func $boundary (param i32)))
  (memory (export "memory") 1)
  (type $f (func (result i32))) (type $c (cont $f)) (tag $yield)
  (func $body (result i32) (loop $again suspend $yield br $again) i32.const 0)
  (elem declare func $body)
  (func (export "run") (param $n i32) (result i32)
    (local $k (ref null $c)) (local $i i32)
    (local.set $k (cont.new $c (ref.func $body)))
    (call $boundary (i32.const 1))
    (loop $again
      (block $suspended (result (ref $c))
        (resume $c (on $yield $suspended) (local.get $k)) unreachable)
      local.set $k
      local.get $i i32.const 1 i32.add local.tee $i local.get $n i32.lt_u br_if $again)
    (call $boundary (i32.const 2))
    (if (i32.ne (local.get $i) (local.get $n)) (then unreachable))
    (local.get $i)))
(assert_return (invoke "run" (i32.const 100)) (i32.const 100))
