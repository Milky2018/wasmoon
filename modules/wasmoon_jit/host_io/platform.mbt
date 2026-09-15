///|
/// platform predicate for native host adapters.
extern "c" fn c_is_windows() -> Int = "wasmoon_host_is_windows"

///|
pub fn is_windows() -> Bool {
  c_is_windows() != 0
}

///|
/// Claim exclusive consumption of a host input descriptor. Returns zero on
/// success, or a host errno. The caller must exclude other readers (including
/// readers through OS-level aliases) until release. Runtime descriptor
/// duplicates share buffered input. Unix keeps its native readiness path;
/// Windows may prefetch up to 4096 bytes after a read/readiness request.
pub extern "c" fn claim_exclusive_input(fd : Int) -> Int = "wasmoon_host_claim_input"

///|
/// End exclusive input consumption after all readers and waiters have stopped.
/// Cancels and joins pending native input work and discards unread prefetched
/// bytes. This does not close the descriptor. Use only when the input session
/// has ended, not to temporarily switch between runtime and external readers.
pub extern "c" fn release_exclusive_input(fd : Int) -> Unit = "wasmoon_host_release_input"
