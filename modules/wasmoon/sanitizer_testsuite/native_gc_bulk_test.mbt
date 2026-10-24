///|
fn native_bulk_types() -> @types.Module raise {
  @wat.parse(
    "(module (type (array (mut i8))) (type (array (mut i16))) (type (array (mut i32))) (type (array (mut i64))) (type (array (mut f32))) (type (array (mut f64))) (type (array (mut v128))) (type (array (mut anyref))) (type (struct (field i32))))",
  )
}

///|
test "typed array initialization distinguishes zero bits and the high vector word" {
  let module_ = native_bulk_types()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
  let upper = @types.Value::V128(
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x2a\x00\x00\x00\x00\x00\x00\x00",
  )
  for
    (type_, value) in [
      (2, @types.Value::I32(0)),
      (6, V128(Bytes::make(16, 0))),
      (6, upper),
      (7, Null),
    ] {
    for count in [0, 1, 65] {
      // Reuse nonzero arena bytes instead of relying on fresh OS-zeroed pages.
      store.alloc_array_repeated(3, 256, I64(-1L)) |> ignore
      store.collect_garbage() |> ignore
      let repeated = store.alloc_array_repeated(type_, count, value)
      let explicit = store.alloc_array(type_, Array::make(count, value))
      for index in 0..<count {
        assert_eq(store.array_get(repeated, index), value)
        assert_eq(store.array_get(explicit, index), value)
      }
      assert_true(store.native_heap().unwrap().verify())
    }
  }
  let array = store.alloc_array(2, [I32(0), I32(42), I32(0)])
  assert_eq(store.array_get(array, 1), I32(42))
}

///|
test "native bulk arrays preserve every scalar width and mixed physical layouts" {
  let module_ = native_bulk_types()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
  let heap = store.native_heap().unwrap()
  let values : Array[@types.Value] = [
    I32(165),
    I32(0x1234),
    I32(-42),
    I64(-0x123456789L),
    F32(1.25),
    F64(-1.5),
    V128(b"\x01\x23\x45\x67\x89\xab\xcd\xef\xfe\xdc\xba\x98\x76\x54\x32\x10"),
  ]
  let zeros : Array[@types.Value] = [
    I32(0),
    I32(0),
    I32(0),
    I64(0L),
    F32(0.0),
    F64(0.0),
    V128(Bytes::make(16, 0)),
  ]
  for kind, value in values {
    for count in [0, 1, 7, 65] {
      let initialized = store.alloc_array_repeated(kind, count, value)
      for index in 0..<count {
        assert_eq(store.array_get(initialized, index), value)
      }
      for mode in 0..<4 {
        let source = if mode == 1 || mode == 2 {
          heap.alloc_array(kind, count + 2, zeros[kind])
        } else {
          store.alloc_array_repeated(kind, count + 2, zeros[kind])
        }
        let destination = if mode == 1 || mode == 3 {
          heap.alloc_array(kind, count + 2, zeros[kind])
        } else {
          store.alloc_array_repeated(kind, count + 2, zeros[kind])
        }
        store.array_fill(source, 1, value, count)
        store.array_copy(destination, 1, source, 1, count)
        store.array_copy(source, 1, destination, 1, count)
        for index in 0..<(count + 2) {
          let expected = if index > 0 && index <= count {
            value
          } else {
            zeros[kind]
          }
          assert_eq(store.array_get(source, index), expected)
          assert_eq(store.array_get(destination, index), expected)
        }
        store.array_fill(destination, count + 2, value, 0)
        store.array_copy(destination, count + 2, source, count + 2, 0)
        store.array_fill(destination, 0, zeros[kind], count + 2)
        for index in 0..<(count + 2) {
          assert_eq(store.array_get(destination, index), zeros[kind])
        }
      }
    }
  }
}

///|
test "native bulk copies preserve both overlap directions including wide vectors" {
  let module_ = native_bulk_types()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
  for kind in [0, 1, 2, 3, 4, 5, 6, 7] {
    let values : Array[@types.Value] = Array::makei(6, index => {
      match kind {
        3 => I64(index.to_int64())
        4 => F32(Float::from_int(index))
        5 => F64(index.to_double())
        6 => V128(Bytes::make(16, index.to_byte()))
        7 => StructRef(store.alloc_struct(8, [I32(index)]))
        _ => I32(index)
      }
    })
    for wide in [false, true] {
      for backwards in [false, true] {
        let array = if wide {
          store.native_heap().unwrap().alloc_array_from_values(kind, values)
        } else {
          store.alloc_array(kind, values)
        }
        let (dst, src) = if backwards { (1, 0) } else { (0, 1) }
        store.array_copy(array, dst, array, src, 5)
        let expected = values.copy()
        for index in 0..<5 {
          expected[dst + index] = values[src + index]
        }
        for index in 0..<6 {
          assert_eq(store.array_get(array, index), expected[index])
        }
        store.array_copy(array, 0, array, 0, 6)
        assert_eq(store.array_get(array, 5), expected[5])
      }
    }
  }
}

///|
test "native bulk reference writes retain barriers and collection roots" {
  let module_ = native_bulk_types()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
  let heap = store.native_heap().unwrap()
  for wide in [false, true] {
    let child = store.alloc_struct(8, [I32(42)])
    let source = store.alloc_array_repeated(7, 4, StructRef(child))
    let dst = if wide {
      heap.alloc_array(7, 4, Null)
    } else {
      store.alloc_array_repeated(7, 4, Null)
    }
    let before = heap.get_barrier_writes()
    store.array_copy(dst, 0, source, 0, 4)
    assert_eq(heap.get_barrier_writes() - before, 4)
    store.collect_garbage(additional_roots=[ArrayRef(dst)]) |> ignore
    assert_eq(store.struct_get(child, 0), I32(42))
    let next = store.alloc_struct(8, [I32(43)])
    let before = heap.get_barrier_writes()
    store.array_fill(dst, 0, StructRef(next), 4)
    assert_eq(heap.get_barrier_writes() - before, 4)
    store.collect_garbage(additional_roots=[ArrayRef(dst)]) |> ignore
    assert_false(store.is_gc_valid(child))
    assert_eq(store.struct_get(next, 0), I32(43))
    store.array_fill(dst, 0, Null, 4)
    store.collect_garbage(additional_roots=[ArrayRef(dst)]) |> ignore
    assert_false(store.is_gc_valid(next))
  }
}

///|
test "native bulk array bounds reject the whole write including overflowing ranges" {
  let module_ = native_bulk_types()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
  let array = store.alloc_array_repeated(2, 4, I32(7))
  let operations : Array[() -> Unit raise @runtime.RuntimeError] = [
    () => store.array_fill(array, 3, I32(42), 2),
    () => store.array_fill(array, -1, I32(42), 1),
    () => store.array_fill(array, 1, I32(42), 0x7fffffff),
    () => store.array_copy(array, 3, array, 0, 2),
    () => store.array_copy(array, 0, array, 3, 2),
    () => store.array_copy(array, 1, array, 0, 0x7fffffff),
  ]
  for operation in operations {
    try operation() catch {
      OutOfBoundsArrayAccess => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("invalid bulk range was accepted")
    }
    for index in 0..<4 {
      assert_eq(store.array_get(array, index), I32(7))
    }
  }
}
