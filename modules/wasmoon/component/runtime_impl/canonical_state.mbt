///| True while doing a "best-effort pre-run" of an async-lowered call.

///|
/// During this phase we must not allow sync-lowered async calls to actually
/// block/spin; otherwise the caller core code can deadlock before it has a
/// chance to make progress (component-spec/async).
let canon_in_prerun : Array[Bool] = [false]

///|
/// True while executing the "handle-less initial step" of an async-lowered call.
/// Nested sync-lowered async calls must avoid consuming the shared handle space
/// during this phase; otherwise it perturbs the outer subtask numbering
/// expected by component-spec (e.g. async-calls-sync.wast).
let canon_in_handleless_step : Array[Bool] = [false]

///|
/// Some operations are guarded by `may_leave` in the component model; for
/// example, post-return functions cannot "leave" the current component
/// instance. We model this with a global flag checked by canonical host funcs.
let canon_may_leave : Array[Bool] = [true]
