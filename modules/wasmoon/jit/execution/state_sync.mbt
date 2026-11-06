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
  jm : @compiled_jit.JITModule,
) -> Array[@wasmoon_jit.MemoryInfo] raise @runtime.RuntimeError {
  store.check_instance(instance)
  if instance.mem_addrs.is_empty() {
    return []
  }
  let memories : Array[@wasmoon_jit.MemoryInfo] = []
  for mem_addr in instance.mem_addrs {
    let mem = store.get_mem(mem_addr)
    let size = mem.byte_len()
    let (_, max_pages) = mem.get_limits()
    let mem_desc_ptr = mem.desc_ptr()
    if mem_desc_ptr.is_null() {
      raise MemoryClosed
    }
    memories.push(MemoryInfo(mem_desc_ptr, size, max_pages))
  }
  jm.set_memory_pointers(memories) catch {
    MemoryBindingAllocationFailed => raise OutOfMemory
    error => raise LinkErrorDetail(error.to_string())
  }
  memories
}
