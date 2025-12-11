(module
  (func (export "f32.ugt") (param $x f32) (param $y f32) (result i32)
    (i32.eqz (f32.le (local.get $x) (local.get $y))))
)
