(module
 (memory 1)
 (func (export "run") (param $n i32) (param $x i32) (result i32)
  (local $p0 i32)
  (local $p1 i32)
  (local $p2 i32)
  (local $p3 i32)
  (local $p4 i32)
  (local $p5 i32)
  (local $p6 i32)
  (local $p7 i32)
  (local $p8 i32)
  (local $p9 i32)
  (local $p10 i32)
  (local $p11 i32)
  (local $p12 i32)
  (local $p13 i32)
  (local $p14 i32)
  (local $p15 i32)
  (local $p16 i32)
  (local $p17 i32)
  (local $p18 i32)
  (local $p19 i32)
  (local $p20 i32)
  (local $p21 i32)
  (local $p22 i32)
  (local $p23 i32)
  (local $p24 i32)
  (local $p25 i32)
  (local $p26 i32)
  (local $p27 i32)
  (local $p28 i32)
  (local $p29 i32)
  (local $p30 i32)
  (local $p31 i32)
  (local.set $p0 (i32.load (i32.const 0)))
  (local.set $p1 (i32.load (i32.const 4)))
  (local.set $p2 (i32.load (i32.const 8)))
  (local.set $p3 (i32.load (i32.const 12)))
  (local.set $p4 (i32.load (i32.const 16)))
  (local.set $p5 (i32.load (i32.const 20)))
  (local.set $p6 (i32.load (i32.const 24)))
  (local.set $p7 (i32.load (i32.const 28)))
  (local.set $p8 (i32.load (i32.const 32)))
  (local.set $p9 (i32.load (i32.const 36)))
  (local.set $p10 (i32.load (i32.const 40)))
  (local.set $p11 (i32.load (i32.const 44)))
  (local.set $p12 (i32.load (i32.const 48)))
  (local.set $p13 (i32.load (i32.const 52)))
  (local.set $p14 (i32.load (i32.const 56)))
  (local.set $p15 (i32.load (i32.const 60)))
  (local.set $p16 (i32.load (i32.const 64)))
  (local.set $p17 (i32.load (i32.const 68)))
  (local.set $p18 (i32.load (i32.const 72)))
  (local.set $p19 (i32.load (i32.const 76)))
  (local.set $p20 (i32.load (i32.const 80)))
  (local.set $p21 (i32.load (i32.const 84)))
  (local.set $p22 (i32.load (i32.const 88)))
  (local.set $p23 (i32.load (i32.const 92)))
  (local.set $p24 (i32.load (i32.const 96)))
  (local.set $p25 (i32.load (i32.const 100)))
  (local.set $p26 (i32.load (i32.const 104)))
  (local.set $p27 (i32.load (i32.const 108)))
  (local.set $p28 (i32.load (i32.const 112)))
  (local.set $p29 (i32.load (i32.const 116)))
  (local.set $p30 (i32.load (i32.const 120)))
  (local.set $p31 (i32.load (i32.const 124)))
  (loop $loop
   (local.set $x (i32.add (local.get $x) (i32.const 3)))
   (local.set $p0 (i32.add (local.get $p0) (i32.const 5)))
   (local.set $p1 (i32.add (local.get $p1) (i32.const 6)))
   (local.set $p2 (i32.add (local.get $p2) (i32.const 7)))
   (local.set $p3 (i32.add (local.get $p3) (i32.const 8)))
   (local.set $p4 (i32.add (local.get $p4) (i32.const 9)))
   (local.set $p5 (i32.add (local.get $p5) (i32.const 10)))
   (local.set $p6 (i32.add (local.get $p6) (i32.const 11)))
   (local.set $p7 (i32.add (local.get $p7) (i32.const 12)))
   (local.set $p8 (i32.add (local.get $p8) (i32.const 13)))
   (local.set $p9 (i32.add (local.get $p9) (i32.const 14)))
   (local.set $p10 (i32.add (local.get $p10) (i32.const 15)))
   (local.set $p11 (i32.add (local.get $p11) (i32.const 16)))
   (local.set $p12 (i32.add (local.get $p12) (i32.const 17)))
   (local.set $p13 (i32.add (local.get $p13) (i32.const 18)))
   (local.set $p14 (i32.add (local.get $p14) (i32.const 19)))
   (local.set $p15 (i32.add (local.get $p15) (i32.const 20)))
   (local.set $p16 (i32.add (local.get $p16) (i32.const 21)))
   (local.set $p17 (i32.add (local.get $p17) (i32.const 22)))
   (local.set $p18 (i32.add (local.get $p18) (i32.const 23)))
   (local.set $p19 (i32.add (local.get $p19) (i32.const 24)))
   (local.set $p20 (i32.add (local.get $p20) (i32.const 25)))
   (local.set $p21 (i32.add (local.get $p21) (i32.const 26)))
   (local.set $p22 (i32.add (local.get $p22) (i32.const 27)))
   (local.set $p23 (i32.add (local.get $p23) (i32.const 28)))
   (local.set $p24 (i32.add (local.get $p24) (i32.const 29)))
   (local.set $p25 (i32.add (local.get $p25) (i32.const 30)))
   (local.set $p26 (i32.add (local.get $p26) (i32.const 31)))
   (local.set $p27 (i32.add (local.get $p27) (i32.const 32)))
   (local.set $p28 (i32.add (local.get $p28) (i32.const 33)))
   (local.set $p29 (i32.add (local.get $p29) (i32.const 34)))
   (local.set $p30 (i32.add (local.get $p30) (i32.const 35)))
   (local.set $p31 (i32.add (local.get $p31) (i32.const 36)))
   (local.set $n (i32.sub (local.get $n) (i32.const 1)))
   (br_if $loop (local.get $n))
  )
  (local.get $x)
  (local.get $p0) i32.add
  (local.get $p1) i32.add
  (local.get $p2) i32.add
  (local.get $p3) i32.add
  (local.get $p4) i32.add
  (local.get $p5) i32.add
  (local.get $p6) i32.add
  (local.get $p7) i32.add
  (local.get $p8) i32.add
  (local.get $p9) i32.add
  (local.get $p10) i32.add
  (local.get $p11) i32.add
  (local.get $p12) i32.add
  (local.get $p13) i32.add
  (local.get $p14) i32.add
  (local.get $p15) i32.add
  (local.get $p16) i32.add
  (local.get $p17) i32.add
  (local.get $p18) i32.add
  (local.get $p19) i32.add
  (local.get $p20) i32.add
  (local.get $p21) i32.add
  (local.get $p22) i32.add
  (local.get $p23) i32.add
  (local.get $p24) i32.add
  (local.get $p25) i32.add
  (local.get $p26) i32.add
  (local.get $p27) i32.add
  (local.get $p28) i32.add
  (local.get $p29) i32.add
  (local.get $p30) i32.add
  (local.get $p31) i32.add
 )
)

(assert_return (invoke "run" (i32.const 1) (i32.const 0)) (i32.const 659))
(assert_return (invoke "run" (i32.const 1) (i32.const 7)) (i32.const 666))
(assert_return (invoke "run" (i32.const 1) (i32.const -3)) (i32.const 656))
(assert_return (invoke "run" (i32.const 1) (i32.const 2147483647)) (i32.const -2147482990))
(assert_return (invoke "run" (i32.const 2) (i32.const 0)) (i32.const 1318))
(assert_return (invoke "run" (i32.const 2) (i32.const 7)) (i32.const 1325))
(assert_return (invoke "run" (i32.const 2) (i32.const -3)) (i32.const 1315))
(assert_return (invoke "run" (i32.const 2) (i32.const 2147483647)) (i32.const -2147482331))
(assert_return (invoke "run" (i32.const 17) (i32.const 0)) (i32.const 11203))
(assert_return (invoke "run" (i32.const 17) (i32.const 7)) (i32.const 11210))
(assert_return (invoke "run" (i32.const 17) (i32.const -3)) (i32.const 11200))
(assert_return (invoke "run" (i32.const 17) (i32.const 2147483647)) (i32.const -2147472446))
