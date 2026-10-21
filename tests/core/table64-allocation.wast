;;! memory64 = true
;;! hogs_memory = true
;;! reference_types = true

(assert_trap
  (module (table i64 0x2000_0000_0000_0000 funcref))
  "overflow calculating table allocation size")

(module
  (table i64 0 funcref)
  (func (export "grow") (param i64) (result i64)
    (table.grow 0 (ref.null func) (local.get 0))
  )
)

(assert_trap (invoke "grow" (i64.const 0x2000_0000_0000_0000))
  "failed to allocate")

(module
  (table i64 0 4294967296 funcref)
  (func (export "grow") (param i64) (result i64)
    ref.null func local.get 0 table.grow 0))
(assert_return (invoke "grow" (i64.const 1)) (i64.const 0))
(assert_return (invoke "grow" (i64.const 0x2000000000000000)) (i64.const -1))
