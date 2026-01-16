///
/// Shared JIT/interpreter state setup.
///
/// With descriptor-backed memories, JIT and interpreter share the same underlying
/// linear memory backing directly through `wasmoon_memory_t`.

///|
/// Initialize JIT memory pointers by pointing the JIT context at the store's
/// existing memory descriptors.
///
/// Returns the MemoryInfo list on success.
pub fn init_jit_memories_from_store(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jm : @jit.JITModule,
) -> Array[@jit.MemoryInfo]? {
  if instance.mem_addrs.is_empty() {
    return Some([])
  }
  let memories : Array[@jit.MemoryInfo] = []
  for mem_addr in instance.mem_addrs {
    let mem = store.get_mem(mem_addr) catch { _ => return None }
    let size = mem.byte_len()
    let (_, max_pages) = mem.get_limits()
    let mem_desc_ptr = mem.desc_ptr()
    if mem_desc_ptr == 0L && size > 0L {
      return None
    }
    memories.push(@jit.MemoryInfo::new(mem_desc_ptr, size, max_pages))
  }
  jm.set_memory_pointers(memories)
  Some(memories)
}

///|
/// Sync is no longer necessary once JIT/interpreter share descriptor-backed
/// memories. This function is kept as a no-op for callers that still invoke it.
pub fn sync_jit_memories_to_store(
  _instance : @runtime.ModuleInstance,
  _store : @runtime.Store,
  _jm : @jit.JITModule,
) -> Unit {
  ()
}
