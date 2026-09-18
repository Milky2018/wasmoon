(component
  (type $duration u64)
  (import "wasi:clocks/types@0.3.0"
    (instance (export "duration" (type (eq $duration)))))
  (core module $m (func (export "probe")))
  (core instance $i (instantiate $m))
  (func (export "probe") (canon lift (core func $i "probe")))
)
