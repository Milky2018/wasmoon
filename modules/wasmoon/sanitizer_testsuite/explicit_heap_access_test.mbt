///|
test "generated struct reads preserve compact affine and legacy field offsets" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $wide (struct (field i64) (field i64) (field i64)))
      #| (type $mixed (struct (field i32) (field i32) (field i64)))
      #| (func (param (ref $wide)) (result i64 i64 i64)
      #|   local.get 0 struct.get $wide 0
      #|   local.get 0 struct.get $wide 1
      #|   local.get 0 struct.get $wide 2)
      #| (func (param (ref $mixed)) (result i32 i32 i64)
      #|   local.get 0 struct.get $mixed 0
      #|   local.get 0 struct.get $mixed 1
      #|   local.get 0 struct.get $mixed 2))
    ),
  )
  @validator.validate_module(module_)
  let canonical = @types.compute_canonical_type_indices(
    module_.types,
    type_rec_groups=module_.type_rec_groups,
  )
  for level in [0, 2, 3] {
    guard @commands.compile_module_to_jit(module_, false, false, level, false)
      is Some((artifact, _)) else {
      fail("struct read compilation failed")
    }
    let jm = @jit.JITModule::load_artifact(
      @commands.verify_compiled_jit_artifact(artifact),
      @wast.build_func_signatures(module_),
    )
    defer jm.close()
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    jm.setup_gc(heap, module_.types, canonical, [2, 3])
    assert_true(heap.get_ptr().define_layout(canonical[0], [8, 8, 8], false))
    assert_true(heap.get_ptr().define_layout(canonical[1], [4, 4, 8], false))
    for compact in [false, true] {
      let allocate = fn(type_, values) raise {
        if compact {
          heap.alloc_struct(type_, values, runtime_type=canonical[type_])
        } else {
          heap.alloc_struct(type_, values)
        }
      }
      let wide = allocate(0, [I64(-1L), I64(4294967297L), I64(-4294967297L)])
      let mixed = allocate(1, [I32(-17), I32(65539), I64(4294967299L)])
      assert_eq(
        jm.call_with_context(jm.get_func(0).unwrap(), [
          (wide + 1).to_int64() << 1,
        ]),
        [-1L, 4294967297L, -4294967297L],
      )
      assert_eq(
        jm.call_with_context(jm.get_func(1).unwrap(), [
          (mixed + 1).to_int64() << 1,
        ]),
        [4294967279L, 65539L, 4294967299L],
      )
    }
  }
}

///|
test "raw JIT entry rejects incompatible concrete GC argument types" {
  // Reject the incompatible identity before native code can use its layout.
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $bytes (array (mut i8)))
      #| (type $words (array (mut i64)))
      #| (func (export "read") (param (ref $words)) (result i64)
      #|   local.get 0 i32.const 1 array.get $words)
      #| (func (export "write") (param (ref $words))
      #|   local.get 0 i32.const 1 i64.const 511 array.set $words))
    ),
  )
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let array = store.alloc_array(0, [I32(7), I32(7)], instance~)
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  for index in [0, 1] {
    try
      context.call_core_func(store, instance, index, [ArrayRef(array)])
    catch {
      HostInvocation(TypeMismatch) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("incompatible concrete array entered native code")
    }
  }
}

///|
test "explicit heap scalar array accesses retain packed float and bounds behavior" {
  for
    (storage, initial, written, getter, equal) in [
      (
        "i8", "i32.const 0", "i32.const 511", "array.get_u", "i32.const 255 i32.eq",
      ),
      (
        "i16", "i32.const 0", "i32.const 65535", "array.get_s", "i32.const -1 i32.eq",
      ),
      (
        "i32", "i32.const 0", "i32.const -42", "array.get", "i32.const -42 i32.eq",
      ),
      (
        "i64", "i64.const 0", "i64.const -4294967297", "array.get", "i64.const -4294967297 i64.eq",
      ),
      (
        "f32", "f32.const 0", "f32.const -42.25", "array.get", "f32.const -42.25 f32.eq",
      ),
      (
        "f64", "f64.const 0", "f64.const -42.25", "array.get", "f64.const -42.25 f64.eq",
      ),
    ] {
    let module_ = @wat.parse(
      (
        $|(module (type $a (array (mut \{storage})))
        $|(func $write (param (ref $a))
        $|local.get 0 i32.const 1 \{written} array.set $a)
        $|(func (export "test") (result i32) (local $a (ref $a))
        $|\{initial} i32.const 3 array.new $a local.set $a
        $|local.get $a call $write
        $|local.get $a i32.const 1 \{getter} $a \{equal}
        $|local.get $a array.len i32.const 3 i32.eq i32.and)
        $|(func (export "bounds") (result i32)
        $|\{initial} i32.const 0 array.new $a i32.const -1
        $|\{getter} $a drop i32.const 1)
        $|(func (export "null")
        $|ref.null $a i32.const 0 \{written} array.set $a))
      ),
    )
    @validator.validate_module(module_)
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    for level in [0, 2, 3] {
      let context = build_gc_root_context(
        module_,
        instance,
        store,
        opt_level=level,
      )
      defer context.close()
      assert_eq(context.call_core_func(store, instance, 1, []), [I32(1)])
      for
        (index, message) in [
          (2, "out of bounds array access"),
          (3, "null reference"),
        ] {
        try context.call_core_func(store, instance, index, []) catch {
          Trap(actual) => assert_eq(actual, message)
          error => fail(error.to_string())
        } noraise {
          _ => fail("explicit heap access omitted its trap")
        }
      }
    }
  }
}

///|
test "explicit heap inherited fields survive reference writes and heap relocation" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $leaf (struct (field i32)))
      #| (type $base (sub (struct (field (mut i8)) (field (mut i16))
      #|   (field (mut i64)) (field (mut (ref null $leaf))) (field v128))))
      #| (type $child (sub $base (struct (field (mut i8)) (field (mut i16))
      #|   (field (mut i64)) (field (mut (ref null $leaf))) (field v128) (field i32))))
      #| (global $saved (mut (ref null $base)) (ref.null $base))
      #| (func (export "seed")
      #|   i32.const 0 i32.const 0 i64.const 0 ref.null $leaf
      #|   v128.const i32x4 1 2 3 42 i32.const 99 struct.new $child global.set $saved)
      #| (func (export "write")
      #|   global.get $saved i32.const 511 struct.set $base 0
      #|   global.get $saved i32.const 65535 struct.set $base 1
      #|   global.get $saved i64.const -4294967297 struct.set $base 2
      #|   global.get $saved i32.const 42 struct.new $leaf struct.set $base 3)
      #| (func (export "read") (result i32)
      #|   global.get $saved struct.get_u $base 0 i32.const 255 i32.eq
      #|   global.get $saved struct.get_s $base 1 i32.const -1 i32.eq i32.and
      #|   global.get $saved struct.get $base 2 i64.const -4294967297 i64.eq i32.and
      #|   global.get $saved struct.get $base 3 struct.get $leaf 0 i32.const 42 i32.eq i32.and
      #|   global.get $saved struct.get $base 4 i32x4.extract_lane 3 i32.const 42 i32.eq i32.and)
      #| (func (export "garbage") (local $i i32)
      #|   (loop $again
      #|     i32.const 99 struct.new $leaf drop
      #|     local.get $i i32.const 1 i32.add local.tee $i
      #|     i32.const 100 i32.lt_u br_if $again)))
    ),
  )
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(
      module_,
      instance,
      store,
      opt_level=level,
    )
    defer context.close()
    context.call_core_func(store, instance, 0, []) |> ignore
    for _ in 0..<3 {
      context.call_core_func(store, instance, 1, []) |> ignore
      context.call_core_func(store, instance, 3, []) |> ignore
      store.collect_garbage() |> ignore
      assert_eq(context.call_core_func(store, instance, 2, []), [I32(1)])
    }
  }
}
