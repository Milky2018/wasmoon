///|
fn run_post_return(
  resources : CanonResources,
  core_results : Array[@types.Value],
  entry : ComponentInstanceEntryState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  if resources.post_return is Some(post_return) {
    let previous = canon_may_leave[0]
    canon_may_leave[0] = false
    defer {
      canon_may_leave[0] = previous
    }
    call_core_func_guarded(store, entry, post_return, core_results) |> ignore
  }
}
