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

///|
pub fn EmbeddingRegRoles::reserved_int_indices(
  self : EmbeddingRegRoles,
  reserve_context? : Bool = false,
  reserve_context_cache_0? : Bool = false,
  reserve_context_cache_1? : Bool = false,
  reserve_extra_results_ptr? : Bool = false,
) -> Array[Int] {
  let out : Array[Int] = []
  fn push_if_int(out : Array[Int], preg : PReg?) -> Unit {
    if preg is Some({ index, class: Int }) {
      out.push(index)
    }
  }
  if reserve_context {
    push_if_int(out, self.context)
  }
  if reserve_context_cache_0 {
    push_if_int(out, self.context_cache_0)
  }
  if reserve_context_cache_1 {
    push_if_int(out, self.context_cache_1)
  }
  if reserve_extra_results_ptr {
    push_if_int(out, self.extra_results_ptr)
  }
  out
}
