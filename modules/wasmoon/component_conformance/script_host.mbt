///|
/// Build fresh host resources for one WAST component instance. The upstream
/// runner creates a separate Store on every component instantiation.
fn create_script_host(
  use_jit : Bool,
) -> ScriptHost raise @runtime_impl.ComponentRuntimeError {
  let linker = if use_jit {
    @runtime_impl.ComponentLinker::with_core_execution_engine(
      @component_native.open_native_component_session(opt_level=0),
    )
  } else {
    ComponentLinker()
  }
  errdefer linker.close()
  let store = linker.get_store()
  let host_runtime = try! linker.host_runtime_state()
  let host_yields : Array[SpectestYield] = []
  try! host_runtime.set_event_loop(fn() { wake_spectest_yields(host_yields) }, poll=fn() {
    wake_spectest_yields(host_yields)
  })
  let return_two = make_const_u32_func(2)
  let return_three = make_const_u32_func(3)
  let return_four = make_const_u32_func(4)
  let echo_u32 = make_echo_u32_func()
  try! linker.add_import("host-return-two", Func(return_two))
  try! linker.add_import("host-echo-u32", Func(echo_u32))
  let simple_module_wat = "(module (func (export \"f\") (result i32) i32.const 101) (global (export \"g\") i32 (i32.const 100)))"
  let simple_module = try! @wat.parse(simple_module_wat)
  let nested_exports : Map[String, @runtime_impl.ComponentExtern] = Map([])
  nested_exports.set("return-four", Func(return_four))
  let nested_instance = make_instance(
    "host::nested", store, nested_exports, host_runtime,
  )
  let host_exports : Map[String, @runtime_impl.ComponentExtern] = Map([])
  host_exports.set("return-two", Func(return_two))
  host_exports.set("return-three", Func(return_three))
  host_exports.set("simple-module", CoreModule(simple_module))
  host_exports.set("nested", Instance(nested_instance))
  host_exports.set(
    "return-two-slowly",
    Func(make_spectest_slow_func(false, host_yields)),
  )
  host_exports.set(
    "echo-slowly",
    Func(make_spectest_slow_func(true, host_yields)),
  )
  host_exports.set(
    "never-return",
    Func(
      HostAsync({ is_async: true, params: [], result: None, }, [], fn(_, _) {
        HostFuture(fn() { Pending }, fn() { () })
      }),
    ),
  )
  host_exports.set(
    "return-hi",
    Func(
      Host({ is_async: false, params: [], result: Some(Prim(String)), }, [], fn(
        _,
        _,
      ) {
        [String("hi")]
      }),
    ),
  )

  // Host instance used by component-spec/wasmtime suites.
  let resource1_type = linker.new_host_resource_type()
  let resource2_type = linker.new_host_resource_type()
  guard resource1_type is Some(ResourceType(resource1_id, _, _, _)) else {
    abort("host resource allocation did not return a resource type")
  }
  host_exports.set("resource1", Type(resource1_type))
  host_exports.set("resource2", Type(resource2_type))
  host_exports.set("resource1-again", Type(resource1_type))
  let resource1_drops : Array[Int] = [0]
  let resource1_last_drop : Array[Int] = [0]
  let dtor_core_type : @types.FuncType = { params: [I32], results: [], }
  let resource1_dtor = @runtime_impl.alloc_host_core_func(
    store,
    dtor_core_type,
    fn(
      args : Array[@types.Value],
    ) -> Array[@types.Value] raise @runtime.RuntimeError {
      match args {
        [I32(rep)] => {
          resource1_drops[0] = resource1_drops[0] + 1
          resource1_last_drop[0] = rep
          []
        }
        _ => raise Unreachable
      }
    },
  ) catch {
    error => raise CanonCallError(error.to_string())
  }
  fn resource1_expect_handle(
    table : @runtime_impl.ResourceTable,
    handle : Int,
  ) -> @runtime_impl.ResourceHandle raise @runtime_impl.ComponentRuntimeError {
    match table.get(handle) {
      Some(h) =>
        if h.type_id != resource1_id {
          raise CanonCallError(
            "handle index \{handle} used with the wrong type",
          )
        } else {
          h
        }
      None => raise CanonCallError("unknown handle index \{handle}")
    }
  }

  let ctor_types : Array[@component_types.TypeDef?] = [
    resource1_type,
    Some(Own(0)),
  ]
  let ctor_func_type : @component_types.FuncType = {
    is_async: false,
    params: [{ label: "r", ty: Prim(U32), }],
    result: Some(TypeIdx(1)),
  }
  let ctor = @runtime_impl.ComponentFunc::Host(ctor_func_type, ctor_types, fn(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    match args {
      [U32(rep)] => {
        let handle = table.alloc({
          type_id: resource1_id,
          rep,
          dtor: Some(resource1_dtor),
          host_dtor: None,
          kind: HostDefined,
          impl_component_id: table.id,
          own: true,
          borrow_scope: None,
          num_lends: [0],
        })
        [U32(handle)]
      }
      _ => raise HostCallError("argument type mismatch")
    }
  })
  host_exports.set("[constructor]resource1", Func(ctor))
  let drops_func_type : @component_types.FuncType = {
    is_async: false,
    params: [],
    result: Some(Prim(U32)),
  }
  let drops = @runtime_impl.ComponentFunc::Host(drops_func_type, [], fn(
    args : Array[@runtime_impl.ComponentValue],
    _table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    if args.length() != 0 {
      raise HostCallError("argument count mismatch")
    }
    [U32(resource1_drops[0])]
  })
  host_exports.set("[static]resource1.drops", Func(drops))
  let last_drop = @runtime_impl.ComponentFunc::Host(drops_func_type, [], fn(
    args : Array[@runtime_impl.ComponentValue],
    _table : @runtime_impl.ResourceTable,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    if args.length() != 0 {
      raise HostCallError("argument count mismatch")
    }
    [U32(resource1_last_drop[0])]
  })
  host_exports.set("[static]resource1.last-drop", Func(last_drop))
  let assert_types : Array[@component_types.TypeDef?] = [
    resource1_type,
    Some(Own(0)),
  ]
  let assert_func_type : @component_types.FuncType = {
    is_async: false,
    params: [{ label: "r", ty: TypeIdx(1), }, { label: "rep", ty: Prim(U32), }],
    result: None,
  }
  let assert_func = @runtime_impl.ComponentFunc::Host(
    assert_func_type,
    assert_types,
    fn(
      args : Array[@runtime_impl.ComponentValue],
      table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      match args {
        [U32(handle), U32(expected)] => {
          let actual = resource1_expect_handle(table, handle)
          // Consume the owned resource.
          table.free(handle) |> ignore
          if actual.rep != expected {
            raise HostCallError("rep mismatch")
          }
          []
        }
        _ => raise HostCallError("argument type mismatch")
      }
    },
  )
  host_exports.set("[static]resource1.assert", Func(assert_func))
  let borrow_ty = Some(@component_types.TypeDef::Borrow(0))
  let simple_types : Array[@component_types.TypeDef?] = [
    resource1_type, borrow_ty,
  ]
  let simple_func_type : @component_types.FuncType = {
    is_async: false,
    params: [
      { label: "self", ty: TypeIdx(1), },
      { label: "rep", ty: Prim(U32), },
    ],
    result: None,
  }
  let simple = @runtime_impl.ComponentFunc::Host(
    simple_func_type,
    simple_types,
    fn(
      args : Array[@runtime_impl.ComponentValue],
      table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      match args {
        [U32(handle), U32(expected)] => {
          let actual = resource1_expect_handle(table, handle)
          if actual.rep != expected {
            raise HostCallError("rep mismatch")
          }
          []
        }
        _ => raise HostCallError("argument type mismatch")
      }
    },
  )
  host_exports.set("[method]resource1.simple", Func(simple))
  let take_borrow_func_type : @component_types.FuncType = {
    is_async: false,
    params: [
      { label: "self", ty: TypeIdx(1), },
      { label: "b", ty: TypeIdx(1), },
    ],
    result: None,
  }
  let take_borrow = @runtime_impl.ComponentFunc::Host(
    take_borrow_func_type,
    simple_types,
    fn(
      args : Array[@runtime_impl.ComponentValue],
      table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      match args {
        [U32(a), U32(b)] => {
          resource1_expect_handle(table, a) |> ignore
          resource1_expect_handle(table, b) |> ignore
          []
        }
        _ => raise HostCallError("argument type mismatch")
      }
    },
  )
  host_exports.set("[method]resource1.take-borrow", Func(take_borrow))
  let own_ty = Some(@component_types.TypeDef::Own(0))
  let take_own_types : Array[@component_types.TypeDef?] = [
    resource1_type, borrow_ty, own_ty,
  ]
  let take_own_func_type : @component_types.FuncType = {
    is_async: false,
    params: [
      { label: "self", ty: TypeIdx(1), },
      { label: "b", ty: TypeIdx(2), },
    ],
    result: None,
  }
  let take_own = @runtime_impl.ComponentFunc::Host(
    take_own_func_type,
    take_own_types,
    fn(
      args : Array[@runtime_impl.ComponentValue],
      table : @runtime_impl.ResourceTable,
    ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
      match args {
        [U32(self_handle), U32(b_handle)] => {
          resource1_expect_handle(table, self_handle) |> ignore
          if self_handle == b_handle {
            raise CanonCallError("cannot remove owned resource while borrowed")
          }
          // Consume owned argument.
          match table.free(b_handle) {
            Some(_) => []
            None => raise CanonCallError("unknown handle index \{b_handle}")
          }
        }
        _ => raise HostCallError("argument type mismatch")
      }
    },
  )
  host_exports.set("[method]resource1.take-own", Func(take_own))
  host_exports.set(
    "[method]resource1.never-return",
    Func(
      HostAsync(
        {
          is_async: true,
          params: [{ label: "self", ty: TypeIdx(1), }],
          result: None,
        },
        [resource1_type, Some(Borrow(0))],
        fn(args, table) raise @runtime_impl.ComponentRuntimeError {
          match args {
            [U32(handle)] => resource1_expect_handle(table, handle) |> ignore
            _ => raise HostCallError("argument type mismatch")
          }
          HostFuture(fn() { Pending }, fn() { () })
        },
      ),
    ),
  )
  let host_instance = make_instance("host", store, host_exports, host_runtime)
  try! linker.add_instance("host", host_instance)
  {
    linker,
    runtime: host_runtime,
    resource_types: Map([((-1, 0), resource1_type), ((-1, 1), resource2_type)]),
  }
}
