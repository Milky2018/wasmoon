///|
fn host_gc_source() -> String {
  let source =
    #|(module
    #| (type $s (struct (field i32)))
    #| (import "host" "gc" (func $gc (param (ref null any))))
    #| (func (export "run") (result i32) (local $live (ref null $s))
    #|  i32.const 42 struct.new $s local.set $live
    #|  i32.const 100 struct.new $s
    #|  i32.const 7 struct.new $s call $gc
    #|  struct.get $s 0 local.get $live struct.get $s 0 i32.add))
  source
}

///|
test "host collection retains live locals operands and arguments on both engines" {
  let source = host_gc_source()
  for mode in [0, 1, 2, 3, 4] {
    let store = if mode != 0 { @runtime.Store::with_c_heap() } else { Store() }
    defer store.close()
    let linker = @runtime.Linker::with_store(store)
    let nested = if mode >= 3 {
      let inner_store = if mode == 4 {
        store
      } else {
        @runtime.Store::with_c_heap()
      }
      let inner_linker = @runtime.Linker::with_store(inner_store)
      inner_linker.add_host_func(
        "host",
        "gc",
        fn(_) { [I32(store.collect_garbage())] },
        func_type={ params: [], results: [I32], },
      )
      let inner_module = @wat.parse(
        "(module (import \"host\" \"gc\" (func $gc (result i32))) (func (export \"run\") (result i32) call $gc))",
      )
      let inner_instance = @executor.instantiate_with_linker(
        inner_linker, "inner", inner_module,
      )
      let inner_context = prepare_async_jit_context(
        inner_module, inner_instance, inner_store,
      )
      inner_context.install_hostcall_dispatcher(inner_store, inner_instance)
      Some((inner_context, inner_instance, inner_store))
    } else {
      None
    }
    defer (if nested is Some((context, _, inner_store)) {
      context.close()
      inner_store.close()
    })
    let collected : Array[Int] = []
    let observed : Array[@types.Value] = []
    linker.add_host_func(
      "host",
      "gc",
      fn(args) raise @runtime.RuntimeError {
        store.alloc_struct(0, [I32(900)]) |> ignore
        let count = match nested {
          Some((context, instance, inner_store)) => {
            let values = context.call_core_func(inner_store, instance, 1, []) catch {
              error => raise LinkErrorDetail(error.to_string())
            }
            guard values is [I32(count)] else { raise Unreachable }
            count
          }
          None => store.collect_garbage()
        }
        collected.push(count)
        guard args is [StructRef(reference)] else { raise Unreachable }
        observed.push(store.struct_get(reference, 0))
        []
      },
      func_type={ params: [AnyRef], results: [], },
    )
    let mod = @wat.parse(source)
    let instance = @executor.instantiate_module_with_imports(
      store,
      mod,
      linker.build_imports(),
    )
    let results = if mode >= 2 {
      let context = prepare_async_jit_context(mod, instance, store)
      defer context.close()
      context.install_hostcall_dispatcher(store, instance)
      context.call_core_func(store, instance, 1, [])
    } else {
      @executor.call_exported_func(store, instance, "run", [])
    }
    debug_inspect(results, content="[I32(142)]")
    debug_inspect(collected, content="[1]")
    debug_inspect(observed, content="[I32(7)]")
    inspect(store.collect_garbage(), content="3")
  }
}

///|
test "host collection retains detached roots during reentry into the same JIT context" {
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  let reenter : Ref[(() -> Unit raise @runtime.RuntimeError)?] = Ref(None)
  let inside = Ref(false)
  let collected : Array[Int] = []
  let observed : Array[@types.Value] = []
  linker.add_host_func(
    "host",
    "gc",
    fn(args) raise @runtime.RuntimeError {
      store.alloc_struct(0, [I32(900)]) |> ignore
      if !inside.val {
        inside.val = true
        reenter.val.unwrap()()
        inside.val = false
      }
      collected.push(store.collect_garbage())
      guard args is [StructRef(reference)] else { raise Unreachable }
      observed.push(store.struct_get(reference, 0))
      []
    },
    func_type={ params: [AnyRef], results: [], },
  )
  let mod = @wat.parse(host_gc_source())
  let instance = @executor.instantiate_with_linker(linker, "guest", mod)
  let context = prepare_async_jit_context(mod, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  reenter.val = Some(fn() raise @runtime.RuntimeError {
    let values = context.call_core_func(store, instance, 1, []) catch {
      error => raise LinkErrorDetail(error.to_string())
    }
    if values != [I32(142)] {
      raise Unreachable
    }
  })
  defer {
    reenter.val = None
  }
  debug_inspect(
    context.call_core_func(store, instance, 1, []),
    content="[I32(142)]",
  )
  debug_inspect(collected, content="[2, 3]")
  debug_inspect(observed, content="[I32(7), I32(7)]")
  inspect(store.collect_garbage(), content="3")
}
