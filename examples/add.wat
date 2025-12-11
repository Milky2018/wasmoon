(module
  (func (export "add") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.add)
  (func (export "addf") (param f32 f32) (result f32)
    local.get 0
    local.get 1
    f32.add)
)
