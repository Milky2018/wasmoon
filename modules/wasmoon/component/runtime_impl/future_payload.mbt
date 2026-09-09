///|
fn store_future_payload(
  payload : CanonicalPayload,
  source_component_id : Int,
  destination : CanonicalPayloadType,
  async_state : AsyncState,
  store : @runtime.Store,
  resources : CanonResources,
  table : ResourceTable,
  ptr : Int64,
) -> Unit raise ComponentRuntimeError {
  guard async_state.resource_tables.get(source_component_id)
    is Some(source_table) else {
    raise CanonCallError("unknown payload owner")
  }
  payload.store(
    0, 1, source_table, destination, resources, store, table, async_state, ptr,
  )
}
