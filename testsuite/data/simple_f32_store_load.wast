(module
  (memory 1)
  (func (export "test_store_load") (result f32)
    (f32.store (i32.const 0) (f32.const 42.5))
    (f32.load (i32.const 0))
  )
)
(assert_return (invoke "test_store_load") (f32.const 42.5))
