///|
test "canonical string lowering preserves allocation sequence and encoded bytes" {
  let cases : Array[(ComponentValue, StringEncoding, Array[Int])] = [
    (String("àà"), Utf16, [8, 4]),
    (EncodedString("AΣ", Utf16, 2), Latin1Utf16, [2, 4]),
    (EncodedString("AA", Latin1Utf16, -2147483646), Latin1Utf16, [4, 2]),
    (String("Ë┛"), Latin1Utf16, [5, 10, 4]),
    (EncodedString("é", Utf16, 1), Utf8, [1, 3, 2]),
  ]
  for case in cases {
    let (value, encoding, sizes) = case
    let store = @runtime.Store::Store()
    defer store.close()
    let memory = store.get_mem(store.alloc_mem(Memory(1, None)))
    let seen : Array[Int] = []
    let realloc = alloc_host_core_func(
      store,
      { params: [I32, I32, I32, I32], results: [I32], },
      args => {
        guard args is [I32(old_ptr), I32(old_size), I32(_), I32(size)] else {
          raise TypeMismatch
        }
        if seen.is_empty() {
          if old_ptr != 0 || old_size != 0 {
            raise Unreachable
          }
        } else if old_ptr != 16 || old_size != seen[seen.length() - 1] {
          raise Unreachable
        }
        seen.push(size)
        [I32(16)]
      },
    )
    let (ptr, _) = lower_canonical_string(
      value,
      encoding,
      store,
      memory,
      {
        func: realloc,
        async_state: AsyncState(StreamTable()),
        owner_component_id: 0,
      },
      false,
    )
    inspect(seen == sizes, content="true")
    guard value.to_host_value() is String(text) else { fail("expected string") }
    let (expected, _, _) = encode_string_for_canon(text, encoding)
    for i in 0..<expected.length() {
      inspect(memory.load_byte(ptr + i) == expected[i], content="true")
    }
  }
}

///|
test "host calls receive plain strings recursively" {
  let store = @runtime.Store::Store()
  defer store.close()
  let observed : Ref[Array[ComponentValue]] = Ref([])
  let func = ComponentFunc::Host(
    { is_async: false, params: [], result: None, },
    [],
    (args, _) => {
      observed.val = args
      []
    },
  )
  call_component_func(
    func,
    [List([EncodedString("é", Utf16, 1)])],
    store,
    ResourceTable(),
    AsyncState(StreamTable()),
  )
  |> ignore
  debug_inspect(observed.val, content="[List([String(\"é\")])]")
}
