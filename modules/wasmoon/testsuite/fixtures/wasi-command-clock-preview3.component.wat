(component
  (import "wasi:clocks/monotonic-clock@0.3.0"
    (instance $clock
      (export "now" (func (result u64)))
    )
  )
  (core func $now (canon lower (func $clock "now")))
  (core module $command
    (import "clock" "now" (func $now (result i64)))
    (func (export "run") (result i32)
      call $now
      drop
      i32.const 0
    )
  )
  (core instance $command
    (instantiate $command
      (with "clock" (instance (export "now" (func $now))))
    )
  )
  (type $run-result (result))
  (func $run async (result $run-result)
    (canon lift (core func $command "run"))
  )
  (instance $run-interface
    (export "run" (func $run))
  )
  (export "wasi:cli/run@0.3.0" (instance $run-interface))
)
