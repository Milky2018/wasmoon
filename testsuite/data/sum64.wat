(module
  (func (export "sum64")
        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
        (result i64)
    (local $sum i64)
    (local.set $sum (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (local.get 0) (local.get 1)) (local.get 2)) (local.get 3)) (local.get 4)) (local.get 5)) (local.get 6)) (local.get 7)))
    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (local.get 8) (local.get 9)) (local.get 10)) (local.get 11)) (local.get 12)) (local.get 13)) (local.get 14)) (local.get 15))))
    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (local.get 16) (local.get 17)) (local.get 18)) (local.get 19)) (local.get 20)) (local.get 21)) (local.get 22)) (local.get 23))))
    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (local.get 24) (local.get 25)) (local.get 26)) (local.get 27)) (local.get 28)) (local.get 29)) (local.get 30)) (local.get 31))))
    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (local.get 32) (local.get 33)) (local.get 34)) (local.get 35)) (local.get 36)) (local.get 37)) (local.get 38)) (local.get 39))))
    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (local.get 40) (local.get 41)) (local.get 42)) (local.get 43)) (local.get 44)) (local.get 45)) (local.get 46)) (local.get 47))))
    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (local.get 48) (local.get 49)) (local.get 50)) (local.get 51)) (local.get 52)) (local.get 53)) (local.get 54)) (local.get 55))))
    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (local.get 56) (local.get 57)) (local.get 58)) (local.get 59)) (local.get 60)) (local.get 61)) (local.get 62)) (local.get 63))))
    (local.get $sum))
)
