///|
test "UTF-16 rejects unpaired surrogates and overflowing lengths" {
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = store.get_mem(store.alloc_mem(Memory(1, None)))
  for unit in [0xd800, 0xdc00, 0xdbff, 0xdfff] {
    memory.store_i32(0, unit)
    for encoding in [StringEncoding::Utf16, Latin1Utf16] {
      let length = if encoding == Utf16 { 1 } else { -2147483647 }
      let error = try {
        read_string_from_memory_with_encoding(
          memory,
          0,
          length.to_int64() & 0xffffffffL,
          encoding,
        )
        |> ignore
        "missing error"
      } catch {
        error => error.to_string()
      }
      inspect(error.contains("unpaired surrogate"), content="true")
    }
  }
  for encoding in [StringEncoding::Utf16, Latin1Utf16] {
    let length = if encoding == Utf16 { 0x40000000 } else { -1073741824 }
    let error = try {
      read_string_from_memory_with_encoding(
        memory,
        0,
        length.to_int64() & 0xffffffffL,
        encoding,
      )
      |> ignore
      "missing error"
    } catch {
      error => error.to_string()
    }
    inspect(error.contains("out-of-bounds"), content="true")
  }
  memory.store_i32(0, -566044611)
  inspect(
    read_string_from_memory_with_encoding(memory, 0, 2, Utf16),
    content="🙂",
  )
}
