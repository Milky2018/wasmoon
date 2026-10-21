;; Independent expected values cover every atomic RMW operation and width.
;; Full memory results also detect writes outside a narrow operand.

;; i32 width 32: add
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw.add (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 1985229328) (i64.const -81985526944926415))

;; i32 width 32: sub
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw.sub (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 1985229328) (i64.const -81985527193080081))

;; i32 width 32: and
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw.and (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 1985229328) (i64.const -81985531096595968))

;; i32 width 32: or
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw.or (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 1985229328) (i64.const -81985527050046671))

;; i32 width 32: xor
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw.xor (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 1985229328) (i64.const -81985527155166927))

;; i32 width 32: xchg
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw.xchg (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 1985229328) (i64.const -81985528930155743))

;; i32 width 32: cmpxchg
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw.cmpxchg (i32.const 0) (i32.const 1985229328) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 1985229328) (i64.const -81985528930155743))

;; i32 width 32: cmpxchg_miss
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw.cmpxchg (i32.const 0) (i32.const 1985229329) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 1985229328) (i64.const -81985529216486896))

;; i32 width 8: add
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw8.add_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 16) (i64.const -81985529216486863))

;; i32 width 8: sub
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw8.sub_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 16) (i64.const -81985529216486673))

;; i32 width 8: and
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw8.and_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 16) (i64.const -81985529216486912))

;; i32 width 8: or
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw8.or_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 16) (i64.const -81985529216486863))

;; i32 width 8: xor
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw8.xor_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 16) (i64.const -81985529216486863))

;; i32 width 8: xchg
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw8.xchg_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 16) (i64.const -81985529216486879))

;; i32 width 8: cmpxchg
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw8.cmpxchg_u (i32.const 0) (i32.const 16) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 16) (i64.const -81985529216486879))

;; i32 width 8: cmpxchg_miss
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw8.cmpxchg_u (i32.const 0) (i32.const 17) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 16) (i64.const -81985529216486896))

;; i32 width 16: add
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw16.add_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 12816) (i64.const -81985529216469711))

;; i32 width 16: sub
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw16.sub_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 12816) (i64.const -81985529216438545))

;; i32 width 16: and
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw16.and_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 12816) (i64.const -81985529216499200))

;; i32 width 16: or
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw16.or_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 12816) (i64.const -81985529216470223))

;; i32 width 16: xor
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw16.xor_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 12816) (i64.const -81985529216470735))

;; i32 width 16: xchg
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw16.xchg_u (i32.const 0) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 12816) (i64.const -81985529216482527))

;; i32 width 16: cmpxchg
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw16.cmpxchg_u (i32.const 0) (i32.const 12816) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 12816) (i64.const -81985529216482527))

;; i32 width 16: cmpxchg_miss
(module (memory 1 1 shared)
  (func (export "run") (result i32 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i32.atomic.rmw16.cmpxchg_u (i32.const 0) (i32.const 12817) (i32.const -2023406815))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i32.const 12816) (i64.const -81985529216486896))

;; i64 width 64: add
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw.add (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const -81985529216486896) (i64.const 1229782937922794801))

;; i64 width 64: sub
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw.sub (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const -81985529216486896) (i64.const -1393753996355768593))

;; i64 width 64: and
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw.and (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const -81985529216486896) (i64.const 1302686086610551296))

;; i64 width 64: or
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw.or (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const -81985529216486896) (i64.const -72903148687756495))

;; i64 width 64: xor
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw.xor (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const -81985529216486896) (i64.const -1375589235298307791))

;; i64 width 64: xchg
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw.xchg (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const -81985529216486896) (i64.const 1311768467139281697))

;; i64 width 64: cmpxchg
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw.cmpxchg (i32.const 0) (i64.const -81985529216486896) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const -81985529216486896) (i64.const 1311768467139281697))

;; i64 width 64: cmpxchg_miss
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw.cmpxchg (i32.const 0) (i64.const -81985529216486895) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const -81985529216486896) (i64.const -81985529216486896))

;; i64 width 8: add
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw8.add_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 16) (i64.const -81985529216486863))

;; i64 width 8: sub
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw8.sub_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 16) (i64.const -81985529216486673))

;; i64 width 8: and
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw8.and_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 16) (i64.const -81985529216486912))

;; i64 width 8: or
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw8.or_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 16) (i64.const -81985529216486863))

;; i64 width 8: xor
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw8.xor_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 16) (i64.const -81985529216486863))

;; i64 width 8: xchg
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw8.xchg_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 16) (i64.const -81985529216486879))

;; i64 width 8: cmpxchg
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw8.cmpxchg_u (i32.const 0) (i64.const 16) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 16) (i64.const -81985529216486879))

;; i64 width 8: cmpxchg_miss
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw8.cmpxchg_u (i32.const 0) (i64.const 17) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 16) (i64.const -81985529216486896))

;; i64 width 16: add
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw16.add_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 12816) (i64.const -81985529216469711))

;; i64 width 16: sub
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw16.sub_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 12816) (i64.const -81985529216438545))

;; i64 width 16: and
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw16.and_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 12816) (i64.const -81985529216499200))

;; i64 width 16: or
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw16.or_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 12816) (i64.const -81985529216470223))

;; i64 width 16: xor
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw16.xor_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 12816) (i64.const -81985529216470735))

;; i64 width 16: xchg
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw16.xchg_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 12816) (i64.const -81985529216482527))

;; i64 width 16: cmpxchg
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw16.cmpxchg_u (i32.const 0) (i64.const 12816) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 12816) (i64.const -81985529216482527))

;; i64 width 16: cmpxchg_miss
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw16.cmpxchg_u (i32.const 0) (i64.const 12817) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 12816) (i64.const -81985529216486896))

;; i64 width 32: add
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw32.add_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 1985229328) (i64.const -81985526944926415))

;; i64 width 32: sub
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw32.sub_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 1985229328) (i64.const -81985527193080081))

;; i64 width 32: and
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw32.and_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 1985229328) (i64.const -81985531096595968))

;; i64 width 32: or
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw32.or_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 1985229328) (i64.const -81985527050046671))

;; i64 width 32: xor
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw32.xor_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 1985229328) (i64.const -81985527155166927))

;; i64 width 32: xchg
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw32.xchg_u (i32.const 0) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 1985229328) (i64.const -81985528930155743))

;; i64 width 32: cmpxchg
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw32.cmpxchg_u (i32.const 0) (i64.const 1985229328) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 1985229328) (i64.const -81985528930155743))

;; i64 width 32: cmpxchg_miss
(module (memory 1 1 shared)
  (func (export "run") (result i64 i64)
    (i64.store (i32.const 0) (i64.const -81985529216486896))
    (i64.atomic.rmw32.cmpxchg_u (i32.const 0) (i64.const 1985229329) (i64.const 1311768467139281697))
    (i64.load (i32.const 0))))
(assert_return (invoke "run") (i64.const 1985229328) (i64.const -81985529216486896))
