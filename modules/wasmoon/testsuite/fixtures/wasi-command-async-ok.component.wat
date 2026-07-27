(component
  (core module $module
    (func (export "run") (result i32)
      i32.const 0
    )
  )
  (core instance $instance (instantiate $module))
  (type $run-result (result))
  (func $run async (result $run-result)
    (canon lift (core func $instance "run"))
  )
  (instance $run-interface
    (export "run" (func $run))
  )
  (export "wasi:cli/run@0.3.0-rc-2025-09-16" (instance $run-interface))
)
