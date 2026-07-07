///|
/// Optional physical-register roles supplied by an embedding ABI.
///
/// MachV does not assign semantic meaning to these registers. Embeddings use
/// them to describe pinned context pointers, cached context-derived pointers,
/// and an out-of-line result area pointer when their ABI requires such roles.
pub(all) struct EmbeddingRegRoles {
  context : PReg?
  context_cache_0 : PReg?
  context_cache_1 : PReg?
  extra_results_ptr : PReg?
}

///|
pub fn EmbeddingRegRoles::none() -> EmbeddingRegRoles {
  {
    context: None,
    context_cache_0: None,
    context_cache_1: None,
    extra_results_ptr: None,
  }
}
