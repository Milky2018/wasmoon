///|
test "canon convert: lower non-empty list stores elements" {
  let store = @runtime.Store::new()
  let mem_addr = store.alloc_mem(@runtime.Memory::new(1, None))
  let heap_ptr = [1024]
  let realloc = alloc_host_core_func(
    store,
    {
      params: [
        @types.ValueType::I32,
        @types.ValueType::I32,
        @types.ValueType::I32,
        @types.ValueType::I32,
      ],
      results: [@types.ValueType::I32],
    },
    fn(
      args : Array[@types.Value],
    ) -> Array[@types.Value] raise @runtime.RuntimeError {
      if args.length() != 4 {
        raise @runtime.RuntimeError::TypeMismatch
      }
      let align = match args[2] {
        @types.Value::I32(n) => n
        _ => raise @runtime.RuntimeError::TypeMismatch
      }
      let size = match args[3] {
        @types.Value::I32(n) => n
        _ => raise @runtime.RuntimeError::TypeMismatch
      }
      let mut ptr = heap_ptr[0]
      if align > 1 {
        let rem = ptr % align
        if rem != 0 {
          ptr += align - rem
        }
      }
      heap_ptr[0] = ptr + size
      [@types.Value::I32(ptr)]
    },
  )
  let resources : CanonResources = {
    mem_addr: Some(mem_addr),
    realloc: Some(realloc),
    post_return: None,
    encoding: StringEncoding::Utf8,
  }
  let func_type : FuncType = {
    is_async: false,
    params: [{ label: "", ty: TypeIdx(0) }],
    result: None,
  }
  let types : Array[TypeDef?] = [Some(TypeDef::List(Prim(S32)))]
  let core_args = component_args_to_core(
    [
      ComponentValue::List([
        ComponentValue::S32(10),
        ComponentValue::S32(20),
        ComponentValue::S32(30),
      ]),
    ],
    func_type,
    types,
    resources,
    store,
    ResourceTable::new(),
    ResourceTable::new(),
  ) catch {
    e => return fail("lower list failed: \{e}")
  }
  let (ptr, len) = match core_args {
    [@types.Value::I32(ptr), @types.Value::I32(len)] => (ptr, len)
    _ => return fail("unexpected lowered args")
  }
  inspect(len, content="3")
  let mem = store.get_mem(mem_addr) catch { _ => return fail("missing memory") }
  inspect(mem.load_i32(ptr) catch { _ => -1 }, content="10")
  inspect(mem.load_i32(ptr + 4) catch { _ => -1 }, content="20")
  inspect(mem.load_i32(ptr + 8) catch { _ => -1 }, content="30")
}
