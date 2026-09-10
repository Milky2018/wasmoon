///|
/// Delivery at a guest suspension point, including exception injection.
pub(all) enum GuestContinuationInput {
  Values(Array[@types.Value])
  Exception(Int, Array[@types.Value])
} derive(Debug)

///|
/// Engine-owned execution state. The Store owns its cancellation capability.
pub(all) struct GuestContinuationBody {
  run : (GuestContinuationInput) -> Array[@types.Value] raise
  cancel : () -> Unit
}

///|
pub impl Debug for GuestContinuationBody with fn to_repr(_self) {
  Repr::literal("<guest-continuation>")
}

///|
pub fn Store::put_guest_continuation(
  self : Store,
  body : GuestContinuationBody,
) -> Int64 raise RuntimeError {
  self.ensure_open()
  let handle = self.guest_continuations.length().to_int64()
  let active = Ref(true)
  let owned : GuestContinuationBody = {
    run: fn(input) raise {
      if !active.val {
        raise ContinuationAlreadyConsumed
      }
      active.val = false
      errdefer (body.cancel)()
      (body.run)(input)
    },
    cancel: fn() {
      if active.val {
        active.val = false
        (body.cancel)()
      }
    },
  }
  self.guest_continuations.push(Some(owned))
  handle
}

///|
/// Consume before executing or rebinding. Handles are never reused in a Store.
pub fn Store::take_guest_continuation(
  self : Store,
  handle : Int64,
) -> GuestContinuationBody raise RuntimeError {
  self.ensure_open()
  if handle < 0L || handle >= self.guest_continuations.length().to_int64() {
    raise ContinuationAlreadyConsumed
  }
  let index = handle.to_int()
  guard self.guest_continuations[index] is Some(body) else {
    raise ContinuationAlreadyConsumed
  }
  self.guest_continuations[index] = None
  body
}

///|
pub(all) enum GuestContinuationEffect {
  Suspend(Int, Array[@types.Value])
  Switch(Int, GuestContinuationBody, Array[@types.Value])
} derive(Debug)

///|
pub(all) suberror GuestContinuationSignal {
  GuestContinuationYield(GuestContinuationEffect, GuestContinuationBody)
} derive(Debug)

///|
pub extend GuestContinuationInput with Debug::{to_repr}

///|
pub extend GuestContinuationBody with Debug::{to_repr}

///|
pub extend GuestContinuationEffect with Debug::{to_repr}

///|
pub extend GuestContinuationSignal with Debug::{to_repr}
