///|
fn Store::register_managed_rollback(
  self : Store,
  registrar : RollbackRegistrar,
) -> Unit {
  self.instantiation = Some(registrar)
  self.references.instantiation = Some(registrar)
  registrar.on_finish(fn() {
    self.instantiation = None
    self.references.instantiation = None
  })
  // Heap cleanup runs last, after mutation-local rollbacks restore Store roots.
  registrar.on_rollback(
    self.heap.make_allocation_rollback(() => self.collect_roots([])),
  )
}

///|
fn Store::begin_close(self : Store) -> Bool {
  if self.closed.val {
    return false
  }
  self.closed.val = true
  let suspended = self.suspended_executions.values().to_array()
  self.suspended_executions.clear()
  for cleanup in suspended {
    if cleanup.lease is Some(lease) {
      lease.release()
    }
    (cleanup.run)()
  }
  let guest_bodies = self.guest_continuations.values().to_array()
  self.guest_continuations.clear()
  for body in guest_bodies {
    (body.cancel)()
  }
  // Clear logical contents and release retained backing slots to break cycles.
  // Array.clear alone can retain references beyond the new length.
  self.guest_continuations.clear()
  true
}

///|
fn Store::close_roots_and_types(self : Store) -> Unit {
  for roots in self.pinned_gc_roots.values() {
    roots.active.val = false
    if roots.lease is Some(lease) {
      lease.release()
    }
  }
  self.pinned_gc_roots.clear()
  self.funcref_registry.clear()
  self.native_types.representatives.clear()
  self.native_types.representatives.shrink_to_fit()
  self.native_types.group_buckets.clear()
  self.native_types.mappings.clear()
  self.native_types.initialization_graph = None
  self.native_types.parents.clear()
  self.native_types.parents.shrink_to_fit()
  self.native_types.views.clear()
  self.native_types.views.shrink_to_fit()
  self.native_types.entries.clear()
  if self.native_types.native_registry is Some(registry) {
    registry.clear()
    self.native_types.native_registry = None
  }
  self.native_types.heap_types.clear()
}

///|
fn Store::invalidate_functions(self : Store) -> Unit {
  for function in self.funcs {
    function.lifetime.active.val = false
  }
  self.funcs.clear()
  self.funcs.shrink_to_fit()
  self.func_types.clear()
  self.func_types.shrink_to_fit()
  self.func_type_indices.clear()
  self.func_type_indices.shrink_to_fit()
  self.func_owners.clear()
  self.func_owners.shrink_to_fit()
}

///|
fn Store::close_instances(self : Store) -> Unit {
  self.instance_leases.clear()
  self.instance_leases.shrink_to_fit()
  self.instances.clear()
  self.instances.shrink_to_fit()
  for table in self.tables {
    table.close()
  }
  self.tables.clear()
  self.tables.shrink_to_fit()
  for memory in self.mems {
    memory.close()
  }
  self.mems.clear()
  self.mems.shrink_to_fit()
  for global in self.globals {
    global.close()
  }
  self.globals.clear()
  self.globals.shrink_to_fit()
  self.tag_lifetimes.clear()
  self.tag_lifetimes.shrink_to_fit()
  self.tags.clear()
  self.tags.shrink_to_fit()
  self.tag_type_indices.clear()
  self.tag_type_indices.shrink_to_fit()
  self.tag_owners.clear()
  self.tag_owners.shrink_to_fit()
}

///|
fn Store::clear_module_references(self : Store) -> Unit {
  // These arrays are borrowed from the parsed module and may be reused by
  // other stores. Closing a store must only drop its own references.
  self.module_types = []
  self.module_rec_groups = []
  self.references.wrapped_externs.clear()
}

///|
fn Store::finish_close(self : Store) -> Unit {
  self.wasi_mem_addr = None
  self.wasi_ctx_handle = 0
  self.instantiation = None
}
