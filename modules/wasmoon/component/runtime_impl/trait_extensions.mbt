///|
pub extend AsyncState with Debug::{to_repr}

///|
pub extend CallbackTask with Debug::{to_repr}

///|
pub extend CanonResources with Debug::{to_repr}

///|
pub extend ComponentClosure with Show::{to_string, output}

///|
pub extend ComponentExtern with Show::{to_string, output}

///|
pub extend ComponentFunc with Debug::{to_repr}

///|
pub extend ComponentFunc with Show::{to_string, output}

///|
pub extend ComponentInvocationPoll with Debug::{to_repr}

///|
pub extend ComponentValue with Debug::{to_repr}

///|
pub extend ComponentValue with Eq::{not_equal, equal}

///|
pub extend ComponentValue with Show::{to_string, output}

///|
pub extend CoreInstance with Show::{to_string, output}

///|
pub extend DecodedCallbackCode with Debug::{to_repr}

///|
pub extend FlatStorageField with Debug::{to_repr}

///|
pub extend FutureEndpoint with Debug::{to_repr}

///|
pub extend FutureState with Debug::{to_repr}

///|
pub extend GuestThread with Debug::{to_repr}

///|
pub extend GuestThreadPhase with Debug::{to_repr}

///|
pub extend GuestThreadPhase with Eq::{not_equal, equal}

///|
pub extend HostByteStreamRead with Debug::{to_repr}

///|
pub extend HostFutureValuePoll with Debug::{to_repr}

///|
pub extend HostValueStreamPoll with Debug::{to_repr}

///|
pub extend PendingFutureRead with Debug::{to_repr}

///|
pub extend PendingFutureWrite with Debug::{to_repr}

///|
pub extend PendingStreamRead with Debug::{to_repr}

///|
pub extend PendingStreamWrite with Debug::{to_repr}

///|
pub extend ResourceHandle with Debug::{to_repr}

///|
pub extend ResourceTable with Debug::{to_repr}

///|
pub extend StreamEndpoint with Debug::{to_repr}

///|
pub extend StreamState with Debug::{to_repr}

///|
pub extend StreamTable with Debug::{to_repr}

///|
pub extend Subtask with Debug::{to_repr}

///|
pub extend SubtaskDriver with Debug::{to_repr}

///|
pub extend SubtaskPhase with Debug::{to_repr}

///|
pub extend SubtaskPhase with Eq::{not_equal, equal}

///|
pub extend SyncLowerState with Debug::{to_repr}

///|
pub extend TaskStep with Debug::{to_repr}

///|
pub extend TaskStep with Eq::{not_equal, equal}

///|
pub extend WaitEvent with Debug::{to_repr}

///|
pub extend WaitableSet with Debug::{to_repr}

///|
pub extend TaskReturnContract with Debug::{to_repr}

///|
pub extend CanonicalRealloc with Debug::{to_repr}

///|
pub extend CanonicalPayload with Debug::{to_repr}

///|
pub extend CanonicalPayloadType with Debug::{to_repr}
