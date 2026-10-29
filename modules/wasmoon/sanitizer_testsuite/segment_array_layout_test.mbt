///|
test "segment constructors use canonical compact layouts in both engines" {
  let source =
    #|(module
    #| (type $b (array (mut i8))) (type $h (array (mut i16)))
    #| (type $i (array (mut i32))) (type $l (array (mut i64)))
    #| (type $f (array (mut f32))) (type $d (array (mut f64)))
    #| (type $s (struct (field i32)))
    #| (type $r (array (mut (ref $s))))
    #| (type $v (array (mut v128)))
    #| (data $bytes "\2a\00\00\00\00\00\00\00\21\43\65\87\a9\cb\ed\ff")
    #| (elem $objects (ref $s) (item (struct.new $s (i32.const 42))))
    #| (func (export "b") (result (ref $b)) i32.const 0 i32.const 8 array.new_data $b $bytes)
    #| (func (export "h") (result (ref $h)) i32.const 0 i32.const 4 array.new_data $h $bytes)
    #| (func (export "i") (result (ref $i)) i32.const 0 i32.const 2 array.new_data $i $bytes)
    #| (func (export "l") (result (ref $l)) i32.const 0 i32.const 1 array.new_data $l $bytes)
    #| (func (export "f") (result (ref $f)) i32.const 0 i32.const 2 array.new_data $f $bytes)
    #| (func (export "d") (result (ref $d)) i32.const 0 i32.const 1 array.new_data $d $bytes)
    #| (func (export "r") (result (ref $r)) i32.const 0 i32.const 1 array.new_elem $r $objects)
    #| (func (export "v") (result (ref $v)) i32.const 0 i32.const 1 array.new_data $v $bytes))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    for native in [false, true] {
      let store = @runtime.Store::with_c_heap()
      defer store.close()
      let instance = @executor.instantiate_module_with_imports(
        store,
        module_,
        Imports(store),
      )
      let context = if native {
        Some(build_gc_root_context(module_, instance, store, opt_level~))
      } else {
        None
      }
      defer (if context is Some(context) { context.close() })
      let heap = store.native_heap().unwrap()
      for index, name in ["b", "h", "i", "l", "f", "d", "r", "v"] {
        let before = heap.get_size()
        let result = if context is Some(context) {
          context.call_core_func(store, instance, index, [])
        } else {
          @executor.call_exported_func(store, instance, name, [])
        }
        guard result is [ArrayRef(array)] else { fail("missing array result") }
        assert_true(
          heap.runtime_type(array) >= 0,
          msg="native=\{native}, level=\{opt_level}, kind=\{name}",
        )
        assert_eq(heap.get_size() - before, 48L)
        let rooted = store.pin_gc_roots(result)
        defer rooted.release()
        store.collect_garbage() |> ignore
        let value = store.array_get(array, 0)
        match value {
          I32(value) => assert_eq(value, 42)
          I64(value) => assert_eq(value, 42L)
          F32(value) => assert_eq(value.reinterpret_as_int(), 42)
          F64(value) => assert_eq(value.reinterpret_as_int64(), 42L)
          V128(bytes) =>
            assert_eq(
              bytes, b"\x2a\x00\x00\x00\x00\x00\x00\x00\x21\x43\x65\x87\xa9\xcb\xed\xff",
            )
          StructRef(child) => assert_eq(store.struct_get(child, 0), I32(42))
          _ => fail("incorrect segment element representation")
        }
        assert_true(heap.verify())
        rooted.release()
      }
    }
  }
}

///|
test "vector data initialization preserves high words bounds and surrounding elements" {
  let source =
    #|(module
    #| (type $a (array (mut v128)))
    #| (data $d "\ff\01\02\03\04\05\06\07\08\11\12\13\14\15\16\17\18\21\22\23\24\25\26\27\28\31\32\33\34\35\36\37\38")
    #| (global $out (ref $a) (array.new $a (v128.const i64x2 -1 -2) (i32.const 4)))
    #| (func (export "init") (param i32 i32 i32)
    #|  global.get $out local.get 0 local.get 1 local.get 2 array.init_data $a $d)
    #| (func (export "get") (param i32) (result v128)
    #|  global.get $out local.get 0 array.get $a)
    #| (func (export "drop") data.drop $d)
    #| (func (export "null")
    #|  ref.null $a i32.const 0 i32.const 0 i32.const 0 array.init_data $a $d))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    for native in [true, false] {
      let store = @runtime.Store::with_c_heap()
      defer store.close()
      let instance = @executor.instantiate_module_with_imports(
        store,
        module_,
        Imports(store),
      )
      let context = if native {
        Some(build_gc_root_context(module_, instance, store, opt_level~))
      } else {
        None
      }
      defer (if context is Some(context) { context.close() })
      let call = fn(index : Int32, arguments : Array[@types.Value]) raise {
        if context is Some(context) {
          context.call_core_func(store, instance, index, arguments)
        } else {
          @executor.call_exported_func(
            store,
            instance,
            ["init", "get", "drop", "null"][index],
            arguments,
          )
        }
      }
      assert_eq(call(0, [I32(1), I32(1), I32(2)]), [])
      let before = Array::makei(4, i => call(1, [I32(i)]))
      assert_eq(before[0], [V128(@types.int64_pair_to_v128_le(-1L, -2L))])
      assert_eq(before[3], before[0])
      assert_eq(before[1], [
        V128(
          b"\x01\x02\x03\x04\x05\x06\x07\x08\x11\x12\x13\x14\x15\x16\x17\x18",
        ),
      ])
      assert_eq(before[2], [
        V128(
          b"\x21\x22\x23\x24\x25\x26\x27\x28\x31\x32\x33\x34\x35\x36\x37\x38",
        ),
      ])
      let bad_ranges : Array[(Array[@types.Value], String)] = [
        ([I32(1), I32(2), I32(2)], "out of bounds memory access"),
        ([I32(3), I32(1), I32(2)], "out of bounds array access"),
      ]
      for (arguments, expected) in bad_ranges {
        let error = try {
          call(0, arguments) |> ignore
          "accepted"
        } catch {
          error => error.to_string()
        }
        assert_true(error.contains(expected), msg=error)
      }
      store.collect_garbage() |> ignore
      for i in 0..<4 {
        assert_eq(call(1, [I32(i)]), before[i])
      }
      call(2, []) |> ignore
      assert_eq(call(0, [I32(4), I32(0), I32(0)]), [])
      let error = try {
        call(3, []) |> ignore
        "accepted"
      } catch {
        error => error.to_string()
      }
      assert_true(error.contains("null reference"), msg=error)
      assert_true(store.native_heap().unwrap().verify())
    }
  }
}

///|
test "numeric segment init keeps legacy wide strides and conservative barriers" {
  for packed in [false, true] {
    let element = if packed { "i8" } else { "i64" }
    let bytes = if packed {
      "\\2a\\2b\\2c\\2d"
    } else {
      "\\02\\00\\00\\00\\00\\00\\00\\00".repeat(4)
    }
    let offset = if packed { 1 } else { 0 }
    let count = 4
    let source = "(module (type $a (array (mut \{element}))) (data $d \"\{bytes}\") (func (param (ref $a)) local.get 0 i32.const \{offset} i32.const 0 i32.const \{count} array.init_data $a $d))"
    let module_ = @wat.parse(source)
    @validator.validate_module(module_)
    for opt_level in [0, 2, 3] {
      let store = @runtime.Store::with_c_heap()
      defer store.close()
      let instance = @executor.instantiate_module_with_imports(
        store,
        module_,
        Imports(store),
      )
      let context = build_gc_root_context(module_, instance, store, opt_level~)
      defer context.close()
      let heap = store.native_heap().unwrap()
      let child = heap.alloc_struct(9, [I32(42)])
      assert_eq(child, 0)
      let legacy = heap.alloc_array(0, 6, if packed { I32(9) } else { I64(9L) })
      assert_eq(heap.runtime_type(legacy), -1)
      let barriers = heap.get_barrier_writes()
      assert_eq(
        context.jit_module.call_with_context(
          context.jit_module.get_func(0).unwrap(),
          [@wasmoon_jit.encode_heap_ref(legacy)],
        ),
        [],
      )
      if packed {
        for i, expected in [9, 42, 43, 44, 45, 9] {
          assert_eq(heap.array_get(legacy, i, I32), I32(expected))
        }
      } else {
        assert_eq(heap.get_barrier_writes() - barriers, 4)
        for i in 0..<4 {
          assert_eq(heap.array_get(legacy, i, I64), I64(2L))
        }
        assert_eq(heap.array_get(legacy, 4, I64), I64(9L))
        assert_eq(heap.array_get(legacy, 5, I64), I64(9L))
        // The wide embedding's low word really names its first object. The
        // existing conservative barrier is observable even for numeric Wasm.
      }
      assert_true(heap.verify())
    }
  }
}

///|
fn assert_segment_bits(
  element : String,
  value : @types.Value,
  lo : Int64,
  hi : Int64,
) -> Unit raise {
  match (element, value) {
    ("i8", I32(word)) | ("i16", I32(word)) | ("i32", I32(word)) =>
      assert_eq(word, lo.to_int())
    ("i64", I64(word)) => assert_eq(word, lo)
    ("f32", F32(word)) => assert_eq(word.reinterpret_as_int(), lo.to_int())
    ("f64", F64(word)) => assert_eq(word.reinterpret_as_int64(), lo)
    ("v128", V128(bytes)) =>
      assert_eq(bytes, @types.int64_pair_to_v128_le(lo, hi))
    _ => fail("segment element has the wrong value type")
  }
}

///|
test "numeric segment ranges preserve all widths bits sentinels and nonreference barriers" {
  let cases : Array[(String, String, Int64, Int64)] = [
    ("i8", "\\2a", 42L, 0L),
    ("i16", "\\81\\fe", 0xfe81L, 0L),
    ("i32", "\\21\\43\\65\\87", 0x87654321L, 0L),
    ("i64", "\\80\\70\\60\\50\\40\\30\\20\\10", 0x1020304050607080L, 0L),
    ("f32", "\\45\\23\\a1\\7f", 0x7fa12345L, 0L),
    ("f64", "\\bc\\9a\\78\\56\\34\\12\\f0\\7f", 0x7ff0123456789abcL, 0L),
    (
      "v128", "\\88\\77\\66\\55\\44\\33\\22\\11\\00\\11\\22\\33\\44\\55\\66\\77",
      0x1122334455667788L, 0x7766554433221100L,
    ),
  ]
  for (element, pattern, lo, hi) in cases {
    let data = "\\ff" + pattern.repeat(17)
    let source = "(module (type $a (array (mut \{element}))) (data $d \"\{data}\") (global $out (ref $a) (array.new_default $a (i32.const 19))) (func (export \"new\") (result (ref $a)) i32.const 1 i32.const 17 array.new_data $a $d) (func (export \"init\") (result (ref $a)) global.get $out i32.const 1 i32.const 1 i32.const 17 array.init_data $a $d global.get $out))"
    let module_ = @wat.parse(source)
    @validator.validate_module(module_)
    for opt_level in [0, 2, 3] {
      for native in [false, true] {
        let store = @runtime.Store::with_c_heap()
        defer store.close()
        let instance = @executor.instantiate_module_with_imports(
          store,
          module_,
          Imports(store),
        )
        let context = if native {
          Some(build_gc_root_context(module_, instance, store, opt_level~))
        } else {
          None
        }
        defer (if context is Some(context) { context.close() })
        let heap = store.native_heap().unwrap()
        let barriers = heap.get_barrier_writes()
        for index, name in ["new", "init"] {
          let result = if context is Some(context) {
            context.call_core_func(store, instance, index, [])
          } else {
            @executor.call_exported_func(store, instance, name, [])
          }
          guard result is [ArrayRef(array)] else {
            fail("missing numeric segment array")
          }
          let roots = store.pin_gc_roots(result)
          defer roots.release()
          store.collect_garbage() |> ignore
          let start = if index == 0 { 0 } else { 1 }
          for i in 0..<17 {
            assert_segment_bits(
              element,
              store.array_get(array, start + i),
              lo,
              hi,
            )
          }
          if index == 1 {
            assert_segment_bits(element, store.array_get(array, 0), 0L, 0L)
            assert_segment_bits(element, store.array_get(array, 18), 0L, 0L)
          }
          assert_eq(heap.get_barrier_writes(), barriers)
          assert_true(heap.verify())
          roots.release()
        }
      }
    }
  }
}
