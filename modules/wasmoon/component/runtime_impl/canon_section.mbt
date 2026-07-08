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
      Lift(core_func_idx, opts, type_idx) =>
        instantiate_canon_lift(
          core_func_idx, opts, type_idx, state, may_enter_self,
        )
      Lower(func_idx, opts) =>
        instantiate_canon_lower(func_idx, opts, state, store)
      BackpressureSet => instantiate_canon_backpressure_set(state, store)
      BackpressureInc => instantiate_canon_backpressure_inc(state, store)
      BackpressureDec => instantiate_canon_backpressure_dec(state, store)
      ResourceNew(tyidx) => instantiate_canon_resource_new(tyidx, state, store)
      ResourceRep(tyidx) => instantiate_canon_resource_rep(tyidx, state, store)
      ResourceDrop(tyidx) =>
        instantiate_canon_resource_drop(tyidx, state, store)
      TaskReturn(result, opts) =>
        instantiate_canon_task_return(result, opts, state, store)
      TaskCancel => instantiate_canon_task_cancel(state, store)
      ThreadIndex => instantiate_canon_thread_index(state, store)
      ThreadYield(_cancellable) =>
        instantiate_canon_thread_yield(_cancellable, state, store)
      ThreadYieldTo(_cancellable) =>
        instantiate_canon_thread_yield_to(_cancellable, state, store)
      ThreadSwitchTo(_cancellable) =>
        instantiate_canon_thread_switch_to(_cancellable, state, store)
      ThreadResumeLater => instantiate_canon_thread_resume_later(state, store)
      ThreadSuspend(_cancellable) =>
        instantiate_canon_thread_suspend(_cancellable, state, store)
      ThreadNewIndirect(_type_idx, _table_idx) =>
        instantiate_canon_thread_new_indirect(
          _type_idx, _table_idx, state, store,
        )
      WaitableSetNew => instantiate_canon_waitable_set_new(state, store)
      WaitableSetWait(_cancellable, memidx) =>
        instantiate_canon_waitable_set_wait(_cancellable, memidx, state, store)
      WaitableSetPoll(_cancellable, memidx) =>
        instantiate_canon_waitable_set_poll(_cancellable, memidx, state, store)
      WaitableSetDrop => instantiate_canon_waitable_set_drop(state, store)
      WaitableJoin => instantiate_canon_waitable_join(state, store)
      SubtaskCancel(is_async_cancel) =>
        instantiate_canon_subtask_cancel(is_async_cancel, state, store)
      SubtaskDrop => instantiate_canon_subtask_drop(state, store)
      StreamNew(_tyidx) => instantiate_canon_stream_new(_tyidx, state, store)
      StreamRead(_tyidx, opts) =>
        instantiate_canon_stream_read(_tyidx, opts, state, store)
      StreamWrite(_tyidx, opts) =>
        instantiate_canon_stream_write(_tyidx, opts, state, store)
      StreamCancelRead(_tyidx, is_async_cancel) =>
        instantiate_canon_stream_cancel_read(
          _tyidx, is_async_cancel, state, store,
        )
      StreamCancelWrite(_tyidx, is_async_cancel) =>
        instantiate_canon_stream_cancel_write(
          _tyidx, is_async_cancel, state, store,
        )
      StreamDropReadable(_tyidx) =>
        instantiate_canon_stream_drop_readable(_tyidx, state, store)
      StreamDropWritable(_tyidx) =>
        instantiate_canon_stream_drop_writable(_tyidx, state, store)
      FutureNew(_tyidx) => instantiate_canon_future_new(_tyidx, state, store)
      FutureRead(_tyidx, _opts) =>
        instantiate_canon_future_read(_tyidx, _opts, state, store)
      FutureWrite(_tyidx, _opts) =>
        instantiate_canon_future_write(_tyidx, _opts, state, store)
      FutureCancelRead(_tyidx, _is_async) =>
        instantiate_canon_future_cancel_read(_tyidx, _is_async, state, store)
      FutureCancelWrite(_tyidx, _is_async) =>
        instantiate_canon_future_cancel_write(_tyidx, _is_async, state, store)
      FutureDropReadable(_tyidx) =>
        instantiate_canon_future_drop_readable(_tyidx, state, store)
      FutureDropWritable(_tyidx) =>
        instantiate_canon_future_drop_writable(_tyidx, state, store)
      ErrorContextNew(opts) =>
        instantiate_canon_error_context_new(opts, state, store)
      ErrorContextDebugMessage(opts) =>
        instantiate_canon_error_context_debug_message(opts, state, store)
      ErrorContextDrop => instantiate_canon_error_context_drop(state, store)
      ContextGet(_vt, _idx) =>
        instantiate_canon_context_get(_vt, _idx, state, store)
      ContextSet(_vt, _idx) =>
        instantiate_canon_context_set(_vt, _idx, state, store)
    }
  }
}
