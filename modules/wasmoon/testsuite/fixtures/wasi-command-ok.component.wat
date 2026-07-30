(component
  (core module $module
    (func (export "run") (result i32)
      i32.const 0
    )
  )
  (core instance $instance (instantiate $module))
  (type $run-result (result))
  (type $run-type (func (result $run-result)))
  (func $run (type $run-type)
    (canon lift (core func $instance "run"))
  )
  (instance $run-interface
    (export "run" (func $run))
  )
  (export "wasi:cli/run@0.2.11" (instance $run-interface))
)
