///|
#borrow(heap, roots)
extern "c" fn generation_collection(
  heap : @wasmoon_jit.GCHeapHandle,
  roots : FixedArray[Int64],
) -> Int32 = "wasmoon_test_heap_allocation_collection"

///|
#borrow(heap)
extern "c" fn generation_minor_count(heap : @wasmoon_jit.GCHeapHandle) -> Int32 = "wasmoon_test_heap_minor_collections"

///|
#borrow(heap)
extern "c" fn generation_allowance(heap : @wasmoon_jit.GCHeapHandle) -> Int64 = "wasmoon_test_heap_collection_allowance"

///|
#borrow(heap)
extern "c" fn generation_dirty_cards(
  heap : @wasmoon_jit.GCHeapHandle,
  reference : Int32,
) -> Int32 = "wasmoon_test_heap_dirty_cards"

///|
#borrow(heap)
extern "c" fn generation_identity_bytes(
  heap : @wasmoon_jit.GCHeapHandle,
) -> Int64 = "wasmoon_test_gc_identity_bytes"

///|
fn generation_roots(
  pointer : @wasmoon_jit.GCHeapHandle,
  roots : FixedArray[Int64],
  young : Bool,
) -> FixedArray[Int64] {
  let graph = if young {
    pointer.begin_young_trace()
  } else {
    pointer.begin_trace()
  }
  for word in roots {
    if word > 0L && (word & 1L) == 0L {
      let expanded = graph.expand((word >> 1).to_int())
      if expanded != [0L] {
        return [-2L]
      }
    }
  }
  graph.mark()
  roots
}

///|
fn bind_generation_roots(heap : @wasmoon_jit.CHeap) -> Unit {
  let pointer = heap.get_ptr()
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(roots) { Some(generation_roots(pointer, roots, true)) },
  )
}

///|
test "young collection retains a child reachable only through a mature struct write" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  assert_true(pointer.define_layout(8, [4], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  assert_true(owner > 0)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  assert_eq(generation_minor_count(pointer), 0)
  // Host writes between native entries must keep recording edges, although
  // no root provider or precise collection is installed in that interval.
  heap.clear_root_visitor()
  let child = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
  assert_true(child > owner)
  heap.struct_set(owner - 1, 0, StructRef(child - 1))
  bind_generation_roots(heap)
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_minor_count(pointer), 1)
  assert_true(heap.is_valid(child - 1))
  assert_eq(heap.struct_get(child - 1, 0, I32), I32(42))
  assert_true(heap.verify())
  // Explicit collection keeps full reclamation semantics after a young cycle.
  assert_eq(heap.collect([]), 2)
  assert_false(heap.is_valid(owner - 1))
  assert_false(heap.is_valid(child - 1))
  assert_true(heap.verify())
}

///|
test "young collection tracks mature reference array set fill and copy" {
  for operation in 0..<3 {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    defer heap.clear_root_visitor()
    let pointer = heap.get_ptr()
    assert_true(pointer.define_layout(7, [-8], true))
    assert_true(pointer.define_layout(8, [4], false))
    let owner = pointer.allocate_typed(7, 7, FixedArray::make(16, 0L), 8, true)
    bind_generation_roots(heap)
    assert_eq(heap.collect([ArrayRef(owner - 1)]), 0)
    let a = pointer.allocate_typed(8, 8, [41L, 0L], 1, false)
    let b = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
    // The source stays young and unrooted: a missing destination barrier must
    // not be hidden by a remembered source retaining the same children.
    let source = pointer.allocate_typed(
      7,
      7,
      FixedArray::makei(16, fn(i) {
        if i % 2 == 1 {
          0L
        } else if i % 4 == 0 {
          a.to_int64() << 1
        } else {
          b.to_int64() << 1
        }
      }),
      8,
      false,
    )
    match operation {
      0 =>
        for i in 0..<8 {
          heap.array_set(
            owner - 1,
            i,
            StructRef((if i % 2 == 0 { a } else { b }) - 1),
          )
        }
      1 => {
        heap.array_fill(owner - 1, 0, StructRef(a - 1), 4)
        heap.array_fill(owner - 1, 4, StructRef(b - 1), 4)
      }
      _ => heap.array_copy(owner - 1, 0, source - 1, 0, 8)
    }
    assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 1)
    assert_eq(generation_minor_count(pointer), 1)
    assert_false(heap.is_valid(source - 1))
    for i in 0..<8 {
      let expected = if operation == 1 {
        if i < 4 {
          a
        } else {
          b
        }
      } else if i % 2 == 0 {
        a
      } else {
        b
      }
      assert_eq(
        heap.array_get(owner - 1, i, StructRef),
        StructRef(expected - 1),
      )
    }
    assert_eq(heap.struct_get(a - 1, 0, I32), I32(41))
    assert_eq(heap.struct_get(b - 1, 0, I32), I32(42))
    assert_true(heap.verify())
    assert_eq(heap.collect([]), 3)
    assert_true(heap.verify())
  }
}

///|
test "young collection preserves partial mature pages and independently seeds dirty owners" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  assert_true(pointer.define_layout(8, [4], false))
  let mut head = 0
  for _ in 0..<1030 {
    head = pointer.allocate_typed(7, 7, [head.to_int64() << 1, 0L], 1, false)
  }
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(head - 1)]), 0)
  for _ in 0..<10 {
    pointer.allocate_typed(8, 8, [0L, 0L], 1, false) |> ignore
  }
  let child = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
  heap.struct_set(0, 0, StructRef(child - 1))
  // Root head is not dirty. Walking all mature ancestors would hide a broken
  // independent remembered-owner seed or an incorrect old-page population.
  assert_eq(generation_collection(pointer, [head.to_int64() << 1]), 10)
  assert_eq(generation_minor_count(pointer), 1)
  assert_eq(heap.struct_get(child - 1, 0, I32), I32(42))
  assert_true(heap.verify())
  for batch in [5, 2200] {
    for _ in 0..<batch {
      pointer.allocate_typed(8, 8, [0L, 0L], 1, false) |> ignore
    }
    assert_eq(generation_collection(pointer, [head.to_int64() << 1]), batch)
    assert_eq(heap.struct_get(child - 1, 0, I32), I32(42))
    assert_true(heap.verify())
  }
  assert_eq(generation_minor_count(pointer), 3)
  assert_eq(heap.collect([StructRef(head - 1)]), 0)
  assert_eq(heap.collect([]), 1031)
  assert_true(heap.verify())
}

///|
test "declined young discovery recomputes full seeds without retaining dirty garbage" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let child = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  heap.struct_set(owner - 1, 0, StructRef(child - 1))
  let attempts = Ref(0)
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(_roots) {
      attempts.val += 1
      None
    },
  )
  assert_eq(generation_collection(pointer, []), 2)
  assert_eq(attempts.val, 1)
  assert_eq(generation_minor_count(pointer), 0)
  assert_false(heap.is_valid(owner - 1))
  assert_false(heap.is_valid(child - 1))
  assert_true(heap.verify())
}

///|
test "aborted young discovery captures its visitor and preserves the next collection" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let child = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  heap.struct_set(owner - 1, 0, StructRef(child - 1))
  let aborted = Ref(0)
  heap.bind_generational_root_visitor(
    fn(phase, _roots) {
      if phase == 2 {
        aborted.val += 1
      }
      []
    },
    fn(_roots) {
      heap.clear_root_visitor()
      Some([-2L])
    },
  )
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), -1)
  assert_eq(aborted.val, 1)
  assert_eq(generation_minor_count(pointer), 0)
  assert_true(heap.is_valid(owner - 1))
  assert_true(heap.is_valid(child - 1))
  bind_generation_roots(heap)
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_minor_count(pointer), 1)
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 2)
}

///|
test "allocation rollback rebuilds generation facts after young promotion" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let rollback = heap.make_allocation_rollback(fn() { [StructRef(owner - 1)] })
  let promoted = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  assert_eq(
    generation_collection(pointer, [
      owner.to_int64() << 1,
      promoted.to_int64() << 1,
    ]),
    0,
  )
  assert_eq(generation_minor_count(pointer), 1)
  rollback()
  assert_false(heap.is_valid(promoted - 1))
  assert_true(heap.is_valid(owner - 1))
  assert_true(heap.verify())
  let child = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  heap.struct_set(owner - 1, 0, StructRef(child - 1))
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_true(heap.is_valid(child - 1))
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 2)
}

///|
test "young completion marks are full roots for exactly the next collection" {
  for abort in [false, true] {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    defer heap.clear_root_visitor()
    let pointer = heap.get_ptr()
    assert_true(pointer.define_layout(7, [-8], false))
    let owner = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
    bind_generation_roots(heap)
    assert_eq(heap.collect([StructRef(owner - 1)]), 0)
    let marked = Ref(0)
    heap.bind_generational_root_visitor(
      fn(phase, roots) {
        if phase == (if abort { 2 } else { 1 }) && marked.val == 0 {
          marked.val = pointer.allocate_typed(
            7,
            7,
            [owner.to_int64() << 1, 0L],
            1,
            false,
          )
          generation_roots(pointer, [marked.val.to_int64() << 1], false)
          |> ignore
        }
        if phase == 0 {
          generation_roots(pointer, roots, false)
        } else {
          []
        }
      },
      fn(roots) {
        Some(if abort { [-2L] } else { generation_roots(pointer, roots, true) })
      },
    )
    assert_eq(
      generation_collection(pointer, [owner.to_int64() << 1]),
      if abort {
        -1
      } else {
        0
      },
    )
    assert_true(marked.val > 0)
    // Premarks force a full trace and protect the old owner as well as the
    // callback allocation. A leaked young trace mode would lose the owner.
    assert_eq(generation_collection(pointer, []), 0)
    assert_true(heap.is_valid(owner - 1))
    assert_true(heap.is_valid(marked.val - 1))
    assert_eq(heap.collect([]), 2)
    assert_true(heap.verify())
  }
}

///|
test "compiled and interpreted reference mutations feed the same young collector" {
  let source =
    $|(module
    $| (type $child (struct (field i32)))
    $| (type $owner (struct (field (mut (ref null $child)))))
    $| (type $array (array (mut (ref null $child))))
    $| (import "h" "promote" (func $promote))
    $| (import "h" "young" (func $young))
    $| (global $owner (ref $owner) ref.null $child struct.new $owner)
    $| (global $array (ref $array) ref.null $child i32.const 4 array.new $array)
    $| (func (export "probe") (result i32)
    $|  call $promote
    $|  global.get $owner i32.const 41 struct.new $child struct.set $owner 0
    $|  global.get $array i32.const 0 i32.const 42 struct.new $child
    $|  i32.const 4 array.fill $array
    $|  global.get $array i32.const 0 i32.const 43 struct.new $child
    $|  i32.const 2 array.new $array i32.const 0 i32.const 2 array.copy $array $array
    $|  global.get $array i32.const 3 i32.const 44 struct.new $child array.set $array
    $|  call $young
    $|  global.get $owner struct.get $owner 0 struct.get $child 0
    $|  global.get $array i32.const 0 array.get $array struct.get $child 0 i32.add
    $|  global.get $array i32.const 2 array.get $array struct.get $child 0 i32.add
    $|  global.get $array i32.const 3 array.get $array struct.get $child 0 i32.add))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_) catch {
    error => fail("mutator validation: \{error}")
  }
  for opt_level in [0, 2, 3] {
    for native in [false, true] {
      let store = @runtime.Store::with_c_heap()
      defer store.close()
      let heap = store.native_heap().unwrap()
      let promote = store.alloc_host_func(fn(_) {
        store.collect_garbage() |> ignore
        []
      })
      let collected = Ref(-1)
      let young = store.alloc_host_func(fn(_) {
        collected.val = generation_collection(heap.get_ptr(), [])
        []
      })
      let imports = @runtime.Imports::Imports(store)
      imports.add_func("h", "promote", promote)
      imports.add_func("h", "young", young)
      let instance = @executor.instantiate_module_with_imports(
        store, module_, imports,
      ) catch {
        error => fail("mutator instantiation: \{error}")
      }
      // This host callback deliberately invokes the allocation collector.
      // Keep its Store root provider installed for the interpreter as well.
      store.begin_gc_tracing()
      defer store.end_gc_tracing()
      let result = try {
        if native {
          let context = build_gc_root_context(
            module_,
            instance,
            store,
            opt_level~,
          )
          defer context.close()
          context.install_hostcall_dispatcher(store, instance)
          context.call_core_func(store, instance, 2, [])
        } else {
          @executor.call_exported_func(store, instance, "probe", [])
        }
      } catch {
        error =>
          fail(
            "mutator execution native=\{native}, level=\{opt_level}: \{error}",
          )
      }
      assert_eq(result, [I32(170)], msg="native=\{native}, level=\{opt_level}")
      assert_true(collected.val >= 0)
      assert_eq(generation_minor_count(heap.get_ptr()), 1)
      assert_true(heap.verify())
    }
  }
}

///|
test "bounded young cycles eventually reclaim unreachable mature garbage" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [4], false))
  let owner = pointer.allocate_typed(7, 7, [42L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  for _ in 0..<64 {
    assert_eq(generation_collection(pointer, []), 0)
    assert_true(heap.is_valid(owner - 1))
  }
  assert_eq(generation_minor_count(pointer), 64)
  assert_eq(generation_collection(pointer, []), 1)
  assert_false(heap.is_valid(owner - 1))
  assert_true(heap.verify())
}

///|
test "legacy physical allocations preserve full conservative collection fallback" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [4], false))
  let owner = pointer.allocate_typed(7, 7, [42L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let legacy = heap.alloc_struct(0, [I32(7)])
  assert_eq(generation_collection(pointer, []), 2)
  assert_eq(generation_minor_count(pointer), 0)
  assert_false(heap.is_valid(owner - 1))
  assert_false(heap.is_valid(legacy))
  assert_true(heap.verify())
}

///|
test "auxiliary references created after promotion decline young collection" {
  for exception in [false, true] {
    let module_ = @wat.parse("(module (type (struct (field i32))))")
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    store.set_module_types(module_.types, rec_groups=module_.type_rec_groups)
    let owner = store.alloc_struct(0, [I32(42)])
    let pinned = store.pin_gc_roots([StructRef(owner)])
    defer pinned.release()
    store.collect_garbage() |> ignore
    let child = store.alloc_struct(0, [I32(7)])
    let root : @types.Value = if exception {
      let tag = store.alloc_tag({ params: [StructRef], results: [], })
      ExnRef(store.alloc_exn(tag, [StructRef(child)]))
    } else {
      store.wrap_as_extern(StructRef(child))
    }
    let auxiliary = store.pin_gc_roots([root])
    defer auxiliary.release()
    let heap = store.native_heap().unwrap()
    store.begin_gc_tracing()
    defer store.end_gc_tracing()
    assert_eq(generation_collection(heap.get_ptr(), []), 0)
    assert_eq(generation_minor_count(heap.get_ptr()), 0)
    assert_eq(store.struct_get(child, 0), I32(7))
    auxiliary.release()
    pinned.release()
    assert_eq(generation_collection(heap.get_ptr(), []), 2)
    assert_true(heap.verify())
  }
}

///|
test "rejected same-heap reentry preserves the outer young tracing scope" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let child = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  heap.struct_set(owner - 1, 0, StructRef(child - 1))
  let nested = Ref(0)
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(roots) {
      nested.val = heap.collect([])
      Some(generation_roots(pointer, roots, true))
    },
  )
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(nested.val, -1)
  assert_eq(generation_minor_count(pointer), 1)
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 2)
}

///|
test "mixed-generation cyclic graphs preserve a deterministic reachability model" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8, -8, 4], false))
  let nodes : Array[Int32] = []
  let edges : Array[FixedArray[Int32]] = []
  fn add_node() -> Int32 raise {
    let index = nodes.length()
    let reference = pointer.allocate_typed(
      7,
      7,
      [0L, 0L, 0L, 0L, (index * 2).to_int64(), 0L],
      3,
      false,
    )
    assert_true(reference > 0)
    nodes.push(reference)
    edges.push([-1, -1])
    index
  }
  fn connect(owner : Int32, field : Int32, child : Int32) -> Unit {
    edges[owner][field] = child
    heap.struct_set(nodes[owner] - 1, field, StructRef(nodes[child] - 1))
  }
  fn reachable(roots : Array[Int32]) -> Array[Bool] {
    let seen = Array::make(nodes.length(), false)
    let pending = roots.copy()
    while pending.pop() is Some(index) {
      if seen[index] {
        continue
      }
      seen[index] = true
      for child in edges[index] {
        if child >= 0 {
          pending.push(child)
        }
      }
    }
    seen
  }
  fn check_live(seen : Array[Bool]) -> Unit raise {
    for index, expected in seen {
      if !expected {
        continue
      }
      assert_true(heap.is_valid(nodes[index] - 1))
      assert_eq(heap.struct_get(nodes[index] - 1, 2, I32), I32(index * 2))
      for field, child in edges[index] {
        assert_eq(
          heap.struct_get(nodes[index] - 1, field, StructRef),
          if child < 0 {
            Null
          } else {
            StructRef(nodes[child] - 1)
          },
        )
      }
    }
  }
  for _ in 0..<3 {
    add_node() |> ignore
  }
  connect(0, 0, 1)
  connect(1, 0, 2)
  connect(2, 0, 0)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(nodes[0] - 1)]), 0)
  let seed = Ref(0x679689U)
  fn choose(bound : Int32) -> Int32 {
    seed.val = seed.val * 1664525U + 1013904223U
    (seed.val % bound.reinterpret_as_uint()).reinterpret_as_int()
  }
  for round in 0..<9 {
    let mature : Array[Int32] = []
    for index, reference in nodes {
      if heap.is_valid(reference - 1) {
        mature.push(index)
      }
    }
    let first = nodes.length()
    for _ in 0..<129 {
      add_node() |> ignore
    }
    for owner in first..<nodes.length() {
      for field in 0..<2 {
        connect(
          owner,
          field,
          if choose(3) == 0 {
            mature[choose(mature.length())]
          } else {
            first + choose(129)
          },
        )
      }
    }
    // Shared young cycles are reachable through both a mature backedge and a
    // direct young root. Other mature garbage may survive until a major cycle.
    connect(0, 1, first)
    connect(mature[choose(mature.length())], 1, first + 128)
    let roots = [0, first + 17]
    let expected = reachable(roots)
    assert_true(
      generation_collection(
        pointer,
        FixedArray::makei(roots.length(), i => nodes[roots[i]].to_int64() << 1),
      ) >=
      0,
    )
    assert_eq(generation_minor_count(pointer), round + 1)
    check_live(expected)
    assert_true(heap.verify())
    if round == 4 {
      let mut live = 0
      let mut retained = 0
      for index, reference in nodes {
        if heap.is_valid(reference - 1) {
          live += 1
        }
        if expected[index] {
          retained += 1
        }
      }
      assert_eq(
        heap.collect(roots.map(i => StructRef(nodes[i] - 1))),
        live - retained,
      )
      for index, reference in nodes {
        assert_eq(heap.is_valid(reference - 1), expected[index])
      }
      assert_true(heap.verify())
    }
  }
  heap.collect([]) |> ignore
  for reference in nodes {
    assert_false(heap.is_valid(reference - 1))
  }
  assert_true(heap.verify())
}

///|
test "a bounded major cycle preserves the generational allocation allowance" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [1], true))
  // A mature payload larger than the nursery exposes accidental reuse of the
  // legacy live-set-sized allowance after a periodic major collection.
  let owner = pointer.allocate_typed(7, 7, [42L, 0L], 72 * 1024 * 1024, true)
  assert_true(owner > 0)
  bind_generation_roots(heap)
  assert_eq(heap.collect([ArrayRef(owner - 1)]), 0)
  assert_eq(generation_allowance(pointer), heap.get_size())
  for _ in 0..<64 {
    assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  }
  assert_eq(generation_minor_count(pointer), 64)
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_minor_count(pointer), 64)
  assert_eq(generation_allowance(pointer), 16L * 1024L * 1024L)
  assert_eq(heap.array_get(owner - 1, 72 * 1024 * 1024 - 1, I32), I32(42))
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(_roots) { None },
  )
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_allowance(pointer), heap.get_size())
  // Explicit host collection retains its complete reclamation/budget contract.
  assert_eq(heap.collect([ArrayRef(owner - 1)]), 0)
  assert_eq(generation_allowance(pointer), heap.get_size())
  assert_true(heap.verify())
}

///|
test "aborted major discovery invalidates generations before recovery" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let child = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  heap.struct_set(owner - 1, 0, StructRef(child - 1))
  heap.bind_generational_root_visitor(
    fn(phase, _roots) { if phase == 0 { [-2L] } else { [] } },
    fn(roots) { Some(generation_roots(pointer, roots, true)) },
  )
  assert_eq(heap.collect([StructRef(owner - 1)]), -1)
  assert_true(heap.is_valid(owner - 1))
  assert_true(heap.is_valid(child - 1))
  assert_true(heap.verify())
  bind_generation_roots(heap)
  // The aborted major discarded its dirty-page metadata. Recovery must first
  // establish a complete mature prefix before a young collection is possible.
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_minor_count(pointer), 0)
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_minor_count(pointer), 1)
  assert_eq(heap.collect([]), 2)
  assert_true(heap.verify())
}

///|
test "young collection retains its captured provider after the owner closes" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [4], false))
  let owner = pointer.allocate_typed(7, 7, [42L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let completed = Ref(0)
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 1 {
        completed.val += 1
      }
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(roots) {
      heap.free()
      Some(generation_roots(pointer, roots, true))
    },
  )
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_minor_count(pointer), 1)
  assert_eq(completed.val, 1)
  assert_true(heap.get_ptr().is_null())
  // The retained native handle stays valid independently of the closed owner.
  assert_eq(pointer.begin_trace().expand(owner), [0L])
}

///|
test "young graph handles cannot escape their admitted collection scope" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  assert_true(pointer.define_layout(8, [4], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let child = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
  heap.struct_set(owner - 1, 0, StructRef(child - 1))
  let saved_expand : Ref[(() -> FixedArray[Int64])?] = Ref(None)
  let saved_mark : Ref[(() -> Unit)?] = Ref(None)
  let expanded : Ref[FixedArray[Int64]] = Ref([])
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(roots) {
      let graph = pointer.begin_young_trace()
      expanded.val = graph.expand(owner)
      graph.mark()
      saved_expand.val = Some(fn() { graph.expand(owner) })
      saved_mark.val = Some(fn() { graph.mark() })
      Some(roots)
    },
  )
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(expanded.val, [0L])
  // An escaped handle must neither provide a stale partial closure nor mark
  // children for a subsequent explicit collection after its scope ended.
  assert_eq(saved_expand.val.unwrap()(), [-2L])
  saved_mark.val.unwrap()()
  assert_eq(heap.collect([]), 2)
  assert_false(heap.is_valid(owner - 1))
  assert_false(heap.is_valid(child - 1))
}

///|
test "an aborted young graph cannot be reused by a later collection attempt" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8, -8], false))
  assert_true(pointer.define_layout(8, [4], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L, 0L, 0L], 2, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  let child = pointer.allocate_typed(8, 8, [41L, 0L], 1, false)
  heap.struct_set(owner - 1, 0, StructRef(child - 1))
  let saved_expand : Ref[(() -> FixedArray[Int64])?] = Ref(None)
  let saved_mark : Ref[(() -> Unit)?] = Ref(None)
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(_roots) {
      let graph = pointer.begin_young_trace()
      graph.expand(owner) |> ignore
      saved_expand.val = Some(fn() { graph.expand(owner) })
      saved_mark.val = Some(fn() { graph.mark() })
      Some([-2L])
    },
  )
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), -1)
  let later = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
  heap.struct_set(owner - 1, 1, StructRef(later - 1))
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(roots) {
      if saved_expand.val.unwrap()() == [0L] {
        saved_mark.val.unwrap()()
        Some(roots)
      } else {
        Some([-2L])
      }
    },
  )
  // A refused attempt must preserve both children. Reusing the old worklist
  // would silently omit the newly written child while claiming completeness.
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), -1)
  assert_true(heap.is_valid(child - 1))
  assert_true(heap.is_valid(later - 1))
  bind_generation_roots(heap)
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(heap.struct_get(child - 1, 0, I32), I32(41))
  assert_eq(heap.struct_get(later - 1, 0, I32), I32(42))
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 3)
}
