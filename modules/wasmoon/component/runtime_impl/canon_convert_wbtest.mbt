///|
test "canon convert: lower non-empty list stores elements" {
  let store = @runtime.Store::Store()
  let mem_addr = store.alloc_mem(Memory(1, None))
  let heap_ptr = [1024]
  let realloc = alloc_host_core_func(
    store,
    { params: [I32, I32, I32, I32], results: [I32] },
    fn(
      args : Array[@types.Value],
    ) -> Array[@types.Value] raise @runtime.RuntimeError {
      if args.length() != 4 {
        raise TypeMismatch
      }
      let align = match args[2] {
        I32(n) => n
        _ => raise TypeMismatch
      }
      let size = match args[3] {
        I32(n) => n
        _ => raise TypeMismatch
      }
      let mut ptr = heap_ptr[0]
      if align > 1 {
        let rem = ptr % align
        if rem != 0 {
          ptr += align - rem
        }
      }
      heap_ptr[0] = ptr + size
      [I32(ptr)]
    },
  )
  let resources : CanonResources = {
    mem_addr: Some(mem_addr),
    realloc: Some(realloc),
    post_return: None,
    encoding: Utf8,
  }
  let func_type : FuncType = {
    is_async: false,
    params: [{ label: "", ty: TypeIdx(0) }],
    result: None,
  }
  let types : Array[TypeDef?] = [Some(List(Prim(S32)))]
  let core_args = component_args_to_core(
    [List([S32(10), S32(20), S32(30)])],
    func_type,
    types,
    resources,
    store,
    ResourceTable(),
    ResourceTable(),
  ) catch {
    e => return fail("lower list failed: \{e}")
  }
  let (ptr, len) = match core_args {
    [I32(ptr), I32(len)] => (ptr, len)
    _ => return fail("unexpected lowered args")
  }
  inspect(len, content="3")
  let mem = store.get_mem(mem_addr) catch { _ => return fail("missing memory") }
  inspect(mem.load_i32(ptr) catch { _ => -1 }, content="10")
  inspect(mem.load_i32(ptr + 4) catch { _ => -1 }, content="20")
  inspect(mem.load_i32(ptr + 8) catch { _ => -1 }, content="30")
}

///|
test "canon convert: lower indirect list result stores compound elements" {
  let store = @runtime.Store::Store()
  let mem_addr = store.alloc_mem(Memory(1, None))
  let heap_ptr = [1024]
  let realloc = alloc_host_core_func(
    store,
    { params: [I32, I32, I32, I32], results: [I32] },
    fn(
      args : Array[@types.Value],
    ) -> Array[@types.Value] raise @runtime.RuntimeError {
      guard args is [I32(_), I32(_), I32(align), I32(size)] else {
        raise TypeMismatch
      }
      let mut ptr = heap_ptr[0]
      if align > 1 {
        let remainder = ptr % align
        if remainder != 0 {
          ptr = ptr + align - remainder
        }
      }
      heap_ptr[0] = ptr + size
      [I32(ptr)]
    },
  )
  let resources : CanonResources = {
    mem_addr: Some(mem_addr),
    realloc: Some(realloc),
    post_return: None,
    encoding: Utf8,
  }
  let func_type : FuncType = {
    is_async: false,
    params: [],
    result: Some(TypeIdx(1)),
  }
  let types : Array[TypeDef?] = [
    Some(Tuple([Prim(U32), Prim(String)])),
    Some(List(TypeIdx(0))),
  ]
  let core_results = component_results_to_core(
    [List([Tuple([U32(7), String("/sandbox")])])],
    func_type,
    types,
    resources,
    store,
    Some(0),
  ) catch {
    e => return fail("lower compound list result failed: \{e}")
  }
  debug_inspect(core_results, content="[]")
  let mem = store.get_mem(mem_addr) catch { _ => return fail("missing memory") }
  let list_ptr = mem.load_i32(0) catch { _ => -1 }
  let string_ptr = mem.load_i32(list_ptr + 4) catch { _ => -1 }
  debug_inspect(
    (
      mem.load_i32(4) catch {
        _ => -1
      },
      mem.load_i32(list_ptr) catch {
        _ => -1
      },
      mem.load_i32(list_ptr + 8) catch {
        _ => -1
      },
      read_string_from_memory_with_encoding(mem, string_ptr, 8, Utf8) catch {
        _ => "<invalid>"
      },
    ),
    content="(1, 7, 8, \"/sandbox\")",
  )
}

///|
test "typed host stream values lower strings into reader memory" {
  let store = @runtime.Store::Store()
  let mem_addr = store.alloc_mem(Memory(1, None))
  let heap_ptr = [1024]
  let realloc = alloc_host_core_func(
    store,
    { params: [I32, I32, I32, I32], results: [I32] },
    fn(
      args : Array[@types.Value],
    ) -> Array[@types.Value] raise @runtime.RuntimeError {
      guard args is [I32(_), I32(_), I32(align), I32(size)] else {
        raise TypeMismatch
      }
      let mut ptr = heap_ptr[0]
      if align > 1 {
        let remainder = ptr % align
        if remainder != 0 {
          ptr = ptr + align - remainder
        }
      }
      heap_ptr[0] = ptr + size
      [I32(ptr)]
    },
  )
  let resources : CanonResources = {
    mem_addr: Some(mem_addr),
    realloc: Some(realloc),
    post_return: None,
    encoding: Utf8,
  }
  let types : Array[TypeDef?] = [
    Some(Enum(["unknown", "directory", "file"])),
    Some(
      Record([
        { label: "kind", ty: TypeIdx(0) },
        { label: "name", ty: Prim(String) },
      ]),
    ),
  ]
  store_host_stream_value(
    Tuple([U32(2), String("data")]),
    TypeIdx(1),
    types,
    resources,
    store,
    ResourceTable(),
    64,
  ) catch {
    e => return fail("typed host stream lowering failed: \{e}")
  }
  let mem = store.get_mem(mem_addr) catch { _ => return fail("missing memory") }
  let string_ptr = mem.load_i32(68) catch { _ => -1 }
  debug_inspect(
    (
      mem.load_i32(64) catch {
        _ => -1
      },
      string_ptr,
      mem.load_i32(72) catch {
        _ => -1
      },
      [
        mem.load_byte(string_ptr) catch {
          _ => b'\x00'
        },
        mem.load_byte(string_ptr + 1) catch {
          _ => b'\x00'
        },
        mem.load_byte(string_ptr + 2) catch {
          _ => b'\x00'
        },
        mem.load_byte(string_ptr + 3) catch {
          _ => b'\x00'
        },
      ],
    ),
    content="(2, 1024, 4, [0x64, 0x61, 0x74, 0x61])",
  )
}
