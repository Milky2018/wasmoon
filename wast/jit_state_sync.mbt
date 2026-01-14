/// JIT/interpreter state synchronization helpers.
///
/// CLI JIT currently executes with its own linear memory allocation.
/// To keep behavior consistent when mixing interpreter instantiation/start and
/// later JIT execution, we provide:
/// - copying interpreter memory into JIT before execution
/// - syncing JIT-mutated memory back into the interpreter store afterwards
///
/// This code lives under `wast/` because it depends on both `runtime` and `jit`.

///|
fn is_all_zero(data : Bytes) -> Bool {
  for i in 0..<data.length() {
    if data[i] != b'\x00' {
      return false
    }
  }
  true
}

///|
fn copy_interp_memory_to_jit_indexed(
  store : @runtime.Store,
  mem_addr : Int,
  jit_mem_ptr : Int64,
) -> Unit {
  let mem = store.get_memory(mem_addr)
  // Copy only the 64KiB physical pages that were actually touched.
  for entry in mem.allocated_pages() {
    let (page_idx, page_bytes) = entry
    let off = page_idx.to_int64() * 65536L
    @jit.memory_init(jit_mem_ptr, off, page_bytes) |> ignore
  }
}

///|
/// Initialize JIT memory pointers by allocating fresh JIT memories and copying
/// the interpreter's current content into them.
///
/// Returns the allocated MemoryInfo list on success.
pub fn init_jit_memories_from_store(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jm : @jit.JITModule,
) -> Array[@jit.MemoryInfo]? {
  if instance.mem_addrs.is_empty() {
    return Some([])
  }
  let memories : Array[@jit.MemoryInfo] = []
  fn bytes_to_64k_pages(bytes : Int64) -> Int {
    ((bytes + 65535L) / 65536L).to_int()
  }

  for i, mem_addr in instance.mem_addrs {
    let mem = store.get_mem(mem_addr) catch { _ => return None }
    let size = mem.byte_len()
    let (_, max) = mem.get_limits()
    let cur_pages_64k = bytes_to_64k_pages(size)
    let max_pages_64k = max.map(fn(m) {
      let max_bytes = m.to_int64() * mem.page_size_bytes()
      bytes_to_64k_pages(max_bytes)
    })
    let mem_ptr = if i == 0 && not(mem.is_memory64()) {
      jm.alloc_guarded_memory(cur_pages_64k, max_pages_64k)
    } else {
      @jit.alloc_memory(size)
    }
    if mem_ptr == 0L && size > 0L {
      return None
    }
    copy_interp_memory_to_jit_indexed(store, mem_addr, mem_ptr)
    memories.push(@jit.MemoryInfo::new(mem_ptr, size, max_pages_64k))
  }
  jm.set_memory_pointers(memories)
  if memories.length() > 0 {
    jm.set_memory(memories[0].ptr, memories[0].size)
  }
  Some(memories)
}

///|
/// Sync JIT memory back to the interpreter store.
///
/// This uses the JIT context as the source of truth for both current memory
/// pointer and memory size (handles memory.grow that may reallocate).
pub fn sync_jit_memories_to_store(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jm : @jit.JITModule,
) -> Unit {
  for i, mem_addr in instance.mem_addrs {
    let old_mem = store.get_mem(mem_addr) catch { _ => continue }
    let mem_ptr = jm.get_memory_ptr(i)
    let jit_size_bytes = jm.get_memory_size(i)

    // If the JIT doesn't have this memory, skip.
    if mem_ptr == 0L && jit_size_bytes > 0L {
      continue
    }
    let page_size_bytes = old_mem.page_size_bytes()
    if page_size_bytes <= 0L {
      continue
    }
    let new_pages = ((jit_size_bytes + page_size_bytes - 1L) / page_size_bytes).to_int()
    let (_, max_pages) = old_mem.get_limits()

    // Derive log2(page_size_bytes) for Memory::new.
    let mut l2 = 0
    let mut v = 1L
    while v < page_size_bytes {
      v = v << 1
      l2 = l2 + 1
    }
    let new_mem = @runtime.Memory::new(
      new_pages,
      max_pages,
      is_memory64=old_mem.is_memory64(),
      page_size_log2=l2,
    )
    let mut off = 0L
    while off < jit_size_bytes {
      let remaining = jit_size_bytes - off
      let chunk_len = if remaining >= 65536L {
        65536
      } else {
        remaining.to_int()
      }
      let chunk = @jit.memory_read(mem_ptr, off, chunk_len)
      if chunk.length() == chunk_len && !is_all_zero(chunk) {
        try new_mem.init_data(off.to_int(), chunk) |> ignore catch {
          _ => ()
        }
      }
      off = off + chunk_len.to_int64()
    }
    store.mems[mem_addr] = new_mem
  }
}
