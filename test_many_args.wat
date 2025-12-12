(module
  ;; Inner function that takes 16 i64 parameters and sums them
  (func $sum16
        (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64)
        (result i64)
    (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
      (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
        (i64.add (local.get 0) (local.get 1))
        (local.get 2)) (local.get 3)) (local.get 4)) (local.get 5))
        (local.get 6)) (local.get 7)) (local.get 8)) (local.get 9))
        (local.get 10)) (local.get 11)) (local.get 12)) (local.get 13))
        (local.get 14)) (local.get 15)))

  ;; Test function that receives 16 params and forwards them to sum16
  (func (export "test")
        (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64)
        (param i64) (param i64) (param i64) (param i64)
        (result i64)
    (call $sum16
      (local.get 0) (local.get 1) (local.get 2) (local.get 3)
      (local.get 4) (local.get 5) (local.get 6) (local.get 7)
      (local.get 8) (local.get 9) (local.get 10) (local.get 11)
      (local.get 12) (local.get 13) (local.get 14) (local.get 15)))
)
