///|
/// Canonical section instantiation (section id 8).
///
/// NOTE: Implementations live in runtime_instantiate_canon_section_*.mbt.

///|
fn process_canon_section(
  payload : Bytes,
  state : BuildState,
  store : @runtime.Store,
  may_enter_self : Array[Bool],
) -> Unit raise ComponentRuntimeError {
  let canons = parse_canon_section(payload) catch {
    e => raise CoreModuleInstantiateError(e.to_string())
  }
  for c in canons {
    match c {
      Canon::Lift(core_func_idx, opts, type_idx) =>
        instantiate_canon_lift(
          core_func_idx, opts, type_idx, state, may_enter_self,
        )
      Canon::Lower(func_idx, opts) =>
        instantiate_canon_lower(func_idx, opts, state, store)
      Canon::ResourceNew(tyidx) =>
        instantiate_canon_resource_new(tyidx, state, store)
      Canon::ResourceRep(tyidx) =>
        instantiate_canon_resource_rep(tyidx, state, store)
      Canon::ResourceDrop(tyidx) =>
        instantiate_canon_resource_drop(tyidx, state, store)
      Canon::TaskReturn(result, opts) =>
        instantiate_canon_task_return(result, opts, state, store)
      Canon::TaskCancel => instantiate_canon_task_cancel(state, store)
      Canon::ThreadIndex => instantiate_canon_thread_index(state, store)
      Canon::ThreadYield(_cancellable) =>
        instantiate_canon_thread_yield(_cancellable, state, store)
      Canon::ThreadYieldTo(_cancellable) =>
        instantiate_canon_thread_yield_to(_cancellable, state, store)
      Canon::ThreadSwitchTo(_cancellable) =>
        instantiate_canon_thread_switch_to(_cancellable, state, store)
      Canon::ThreadResumeLater =>
        instantiate_canon_thread_resume_later(state, store)
      Canon::ThreadSuspend(_cancellable) =>
        instantiate_canon_thread_suspend(_cancellable, state, store)
      Canon::ThreadNewIndirect(_type_idx, _table_idx) =>
        instantiate_canon_thread_new_indirect(
          _type_idx, _table_idx, state, store,
        )
      Canon::WaitableSetNew => instantiate_canon_waitable_set_new(state, store)
      Canon::WaitableSetWait(_cancellable, memidx) =>
        instantiate_canon_waitable_set_wait(_cancellable, memidx, state, store)
      Canon::WaitableSetPoll(_cancellable, memidx) =>
        instantiate_canon_waitable_set_poll(_cancellable, memidx, state, store)
      Canon::WaitableSetDrop =>
        instantiate_canon_waitable_set_drop(state, store)
      Canon::WaitableJoin => instantiate_canon_waitable_join(state, store)
      Canon::SubtaskCancel(is_async_cancel) =>
        instantiate_canon_subtask_cancel(is_async_cancel, state, store)
      Canon::SubtaskDrop => instantiate_canon_subtask_drop(state, store)
      Canon::StreamNew(_tyidx) =>
        instantiate_canon_stream_new(_tyidx, state, store)
      Canon::StreamRead(_tyidx, opts) =>
        instantiate_canon_stream_read(_tyidx, opts, state, store)
      Canon::StreamWrite(_tyidx, opts) =>
        instantiate_canon_stream_write(_tyidx, opts, state, store)
      Canon::StreamCancelRead(_tyidx, is_async_cancel) =>
        instantiate_canon_stream_cancel_read(
          _tyidx, is_async_cancel, state, store,
        )
      Canon::StreamCancelWrite(_tyidx, is_async_cancel) =>
        instantiate_canon_stream_cancel_write(
          _tyidx, is_async_cancel, state, store,
        )
      Canon::StreamDropReadable(_tyidx) =>
        instantiate_canon_stream_drop_readable(_tyidx, state, store)
      Canon::StreamDropWritable(_tyidx) =>
        instantiate_canon_stream_drop_writable(_tyidx, state, store)
      Canon::FutureNew(_tyidx) =>
        instantiate_canon_future_new(_tyidx, state, store)
      Canon::FutureRead(_tyidx, _opts) =>
        instantiate_canon_future_read(_tyidx, _opts, state, store)
      Canon::FutureWrite(_tyidx, _opts) =>
        instantiate_canon_future_write(_tyidx, _opts, state, store)
      Canon::FutureCancelRead(_tyidx, _is_async) =>
        instantiate_canon_future_cancel_read(_tyidx, _is_async, state, store)
      Canon::FutureCancelWrite(_tyidx, _is_async) =>
        instantiate_canon_future_cancel_write(_tyidx, _is_async, state, store)
      Canon::FutureDropReadable(_tyidx) =>
        instantiate_canon_future_drop_readable(_tyidx, state, store)
      Canon::FutureDropWritable(_tyidx) =>
        instantiate_canon_future_drop_writable(_tyidx, state, store)
      Canon::ContextGet(_vt, _idx) =>
        instantiate_canon_context_get(_vt, _idx, state, store)
      Canon::ContextSet(_vt, _idx) =>
        instantiate_canon_context_set(_vt, _idx, state, store)
    }
  }
}
