///|
/// A validated clock subscription. Timeout bits remain unsigned from guest
/// decoding through deadline comparison.
priv struct PollClockSubscription {
  userdata : Int64
  clock_id : ClockId
  timeout : UInt64
  absolute : Bool
  event_nbytes : Int64
}

///|
priv enum PollFdSource {
  Native(Int)
  Immediate
}

///|
priv enum PollDescriptorContext {
  InterpreterDescriptors(WasiContext)
  JitDescriptors(Int64)
}

///|
priv struct PollFdSubscription {
  userdata : Int64
  wasi_fd : Int
  event_type : Int
  source : PollFdSource
}

///|
priv enum PollSubscription {
  ClockPoll(PollClockSubscription)
  FdPoll(PollFdSubscription)
}

///|
priv struct PollEvent {
  userdata : Int64
  error : Int
  event_type : Int
  nbytes : Int64
  flags : Int
}

///|
priv enum PollHostResult {
  HostReady(Array[Int])
  HostInterrupted
  HostFailed(Int)
}

///|
fn read_poll_u16(mem : @runtime.Memory, addr : Int) -> Int {
  mem.read_byte(addr).to_int() | (mem.read_byte(addr + 1).to_int() << 8)
}

///|
fn check_poll_array_range(
  mem : @runtime.Memory,
  ptr : Int,
  count : UInt,
  element_size : UInt64,
) -> Bool {
  if ptr < 0 {
    return false
  }
  let start = ptr.to_int64().reinterpret_as_uint64()
  let bytes = count.to_uint64() * element_size
  let end = start + bytes
  end >= start && end <= mem.byte_len().reinterpret_as_uint64()
}

///|
fn poll_stdio_is_native(ctx : WasiContext, slot : Int) -> Bool {
  match slot {
    0 => ctx.stdin_is_native
    1 => ctx.stdout_is_native
    2 => ctx.stderr_is_native
    _ => false
  }
}

///|
fn poll_descriptor_context(ctx : WasiContext) -> PollDescriptorContext {
  let jit_context = active_jit_context_ptr()
  if jit_context == 0L {
    InterpreterDescriptors(ctx)
  } else {
    JitDescriptors(jit_context)
  }
}

///|
fn resolve_poll_fd_source(
  descriptors : PollDescriptorContext,
  fd : Int,
  event_type : Int,
) -> Result[PollFdSource, Errno] {
  match descriptors {
    JitDescriptors(jit_context) => {
      let source = jit_poll_resolve_fd(jit_context, fd, event_type)
      if source >= 0 {
        Ok(Native(source))
      } else if source == -2 {
        Ok(Immediate)
      } else if source == -3 {
        Err(NotCapable)
      } else {
        Err(Badf)
      }
    }
    InterpreterDescriptors(ctx) => {
      if stdio_slot_for_fd(ctx, fd) is Some(slot) {
        if !is_stdio_open(ctx, fd) {
          return Err(Badf)
        }
        if (slot == 0 && event_type != 1) || (slot != 0 && event_type != 2) {
          return Err(Badf)
        }
        if poll_stdio_is_native(ctx, slot) {
          return Ok(Native(slot))
        }
        return Ok(Immediate)
      }
      let file = match ctx.get_file(fd) {
        Some(file) => file
        None => return Err(Badf)
      }
      let direction_right = if event_type == 1 {
        right_fd_read
      } else {
        right_fd_write
      }
      if (file.rights_base & right_poll_fd_readwrite) == 0L ||
        (file.rights_base & direction_right) == 0L {
        return Err(NotCapable)
      }
      match file.file_type {
        RegularFile | CharacterDevice | SocketStream =>
          Ok(Native(file.native_fd))
        Directory => Err(Badf)
      }
    }
  }
}

///|
fn decode_poll_subscriptions(
  descriptors : PollDescriptorContext,
  mem : @runtime.Memory,
  in_ptr : Int,
  nsubscriptions : Int,
) -> Result[Array[PollSubscription], Errno] {
  let subscriptions : Array[PollSubscription] = []
  for i in 0..<nsubscriptions {
    let sub_ptr = in_ptr + i * 48
    let userdata = mem.read_i64(sub_ptr)
    let tag = mem.read_byte(sub_ptr + 8).to_int()
    if tag == 0 {
      let clock_id = match ClockId::from_i32(mem.read_i32(sub_ptr + 16)) {
        Some(id) => id
        None => return Err(Inval)
      }
      let flags = read_poll_u16(mem, sub_ptr + 40)
      let known_flags = 0x01
      if (flags & known_flags.lnot()) != 0 {
        return Err(Inval)
      }
      let absolute = (flags & 0x01) != 0
      // Match the Preview1 compatibility behavior used by Wasmtime: a single
      // relative CPU-clock subscription is treated as a duration-only sleep.
      // CPU clocks are otherwise not supported by this poll backend.
      if clock_id is (ProcessCPUTimeId | ThreadCPUTimeId) &&
        (absolute || nsubscriptions != 1) {
        return Err(Inval)
      }
      subscriptions.push(
        ClockPoll({
          userdata,
          clock_id,
          timeout: mem.read_i64(sub_ptr + 24).reinterpret_as_uint64(),
          absolute,
          event_nbytes: if nsubscriptions == 1 && !absolute {
            1L
          } else {
            0L
          },
        }),
      )
    } else if tag == 1 || tag == 2 {
      let wasi_fd = mem.read_i32(sub_ptr + 12)
      let source = match resolve_poll_fd_source(descriptors, wasi_fd, tag) {
        Ok(source) => source
        Err(errno) => return Err(errno)
      }
      subscriptions.push(FdPoll({ userdata, wasi_fd, event_type: tag, source }))
    } else {
      return Err(Inval)
    }
  }
  Ok(subscriptions)
}

///|
fn poll_now_monotonic() -> UInt64 {
  let now = native_clock_gettime_monotonic()
  if now < 0L {
    0UL
  } else {
    now.reinterpret_as_uint64()
  }
}

///|
fn poll_now_realtime() -> UInt64 {
  let now = native_clock_gettime_realtime()
  if now < 0L {
    0UL
  } else {
    now.reinterpret_as_uint64()
  }
}

///|
fn PollClockSubscription::remaining_ns(
  self : PollClockSubscription,
  elapsed : UInt64,
  now_monotonic : UInt64,
  now_realtime : UInt64,
) -> UInt64 {
  if !self.absolute {
    return if elapsed >= self.timeout { 0UL } else { self.timeout - elapsed }
  }
  let now = match self.clock_id {
    Monotonic => now_monotonic
    Realtime => now_realtime
    ProcessCPUTimeId | ThreadCPUTimeId => return 0UL
  }
  if now >= self.timeout {
    0UL
  } else {
    self.timeout - now
  }
}

///|
fn poll_timeout_ms(remaining_ns : UInt64) -> Int {
  if remaining_ns == 0UL {
    return 0
  }
  let whole_ms = remaining_ns / 1_000_000UL
  let rounded_ms = if remaining_ns % 1_000_000UL == 0UL {
    whole_ms
  } else {
    whole_ms + 1UL
  }
  let max_poll_ms = 2_147_483_647UL
  if rounded_ms > max_poll_ms {
    max_poll_ms.to_int()
  } else {
    rounded_ms.to_int()
  }
}

///|
fn poll_sleep_ns(remaining_ns : UInt64) -> Int64 {
  let max_sleep_ns = 2_147_483_647UL * 1_000_000UL
  if remaining_ns > max_sleep_ns {
    max_sleep_ns.reinterpret_as_int64()
  } else {
    remaining_ns.reinterpret_as_int64()
  }
}

///|
fn poll_native_once(
  fds : Array[Int],
  events : Array[Int],
  timeout_ms : Int,
) -> PollHostResult {
  let nfds = fds.length()
  let fds_arr = FixedArray::make(nfds, 0)
  let events_arr = FixedArray::make(nfds, 0)
  let revents_arr = FixedArray::make(nfds, 0)
  for i in 0..<nfds {
    fds_arr[i] = fds[i]
    events_arr[i] = events[i]
  }
  let result = c_poll(fds_arr, events_arr, revents_arr, nfds, timeout_ms)
  if result < 0 {
    let errno = native_last_errno_to_wasi()
    if errno == Errno::Intr.to_i32() {
      HostInterrupted
    } else {
      HostFailed(errno)
    }
  } else {
    let revents : Array[Int] = []
    for i in 0..<nfds {
      revents.push(revents_arr[i])
    }
    HostReady(revents)
  }
}

///|
fn poll_fd_read_nbytes_and_flags(
  descriptors : PollDescriptorContext,
  fd : Int,
) -> (Int64, Int) {
  match descriptors {
    JitDescriptors(jit_context) =>
      (
        jit_poll_fd_read_nbytes(jit_context, fd),
        jit_poll_fd_read_flags(jit_context, fd),
      )
    InterpreterDescriptors(ctx) => {
      if stdio_slot_for_fd(ctx, fd) is Some(_) {
        return (1L, 0)
      }
      let file = match ctx.get_file(fd) {
        Some(file) => file
        None => return (0L, 0)
      }
      if file.file_type is SocketStream {
        return (native_socket_bytes_available(file.native_fd).unwrap_or(1L), 0)
      }
      if !(file.file_type is RegularFile) {
        return (1L, 0)
      }
      let stat = match native_fstat(file.native_fd) {
        Some(stat) => stat
        None => return (1L, 0)
      }
      let position = match native_tell(file.native_fd) {
        Some(position) => position
        None => return (1L, 0)
      }
      let position_u = position.reinterpret_as_uint64()
      if stat.size <= position_u {
        (0L, 0x01)
      } else {
        ((stat.size - position_u).reinterpret_as_int64(), 0)
      }
    }
  }
}

///|
fn poll_fd_event(
  descriptors : PollDescriptorContext,
  sub : PollFdSubscription,
  revents : Int,
) -> PollEvent? {
  let poll_error = 0x08
  let poll_hangup = 0x10
  let poll_invalid = 0x20
  if (revents & poll_invalid) != 0 {
    return Some({
      userdata: sub.userdata,
      error: Errno::Badf.to_i32(),
      event_type: sub.event_type,
      nbytes: 0L,
      flags: 0,
    })
  }
  if (revents & poll_error) != 0 {
    return Some({
      userdata: sub.userdata,
      error: Errno::IO.to_i32(),
      event_type: sub.event_type,
      nbytes: 0L,
      flags: 0,
    })
  }
  let requested = if sub.event_type == 1 { 0x01 } else { 0x04 }
  if (revents & (requested | poll_hangup)) == 0 {
    return None
  }
  let (nbytes, flags) = if sub.event_type == 1 {
    poll_fd_read_nbytes_and_flags(descriptors, sub.wasi_fd)
  } else {
    (1L, 0)
  }
  Some({
    userdata: sub.userdata,
    error: 0,
    event_type: sub.event_type,
    nbytes,
    flags: if (revents & poll_hangup) != 0 {
      flags | 0x01
    } else {
      flags
    },
  })
}

///|
fn immediate_poll_fd_event(
  descriptors : PollDescriptorContext,
  sub : PollFdSubscription,
) -> PollEvent {
  let (nbytes, flags) = if sub.event_type == 1 {
    poll_fd_read_nbytes_and_flags(descriptors, sub.wasi_fd)
  } else {
    (1L, 0)
  }
  {
    userdata: sub.userdata,
    error: 0,
    event_type: sub.event_type,
    nbytes,
    flags,
  }
}

///|
fn poll_has_ready(events : Array[PollEvent?]) -> Bool {
  events.any(fn(event) { event is Some(_) })
}

///|
fn mark_ready_clocks(
  subscriptions : Array[PollSubscription],
  ready : Array[PollEvent?],
  start_monotonic : UInt64,
) -> UInt64? {
  let now_monotonic = poll_now_monotonic()
  let now_realtime = poll_now_realtime()
  let elapsed = if now_monotonic >= start_monotonic {
    now_monotonic - start_monotonic
  } else {
    0UL
  }
  let mut minimum : UInt64? = None
  for i, subscription in subscriptions {
    if subscription is ClockPoll(clock) && ready[i] is None {
      let remaining = clock.remaining_ns(elapsed, now_monotonic, now_realtime)
      if remaining == 0UL {
        ready[i] = Some({
          userdata: clock.userdata,
          error: 0,
          event_type: 0,
          nbytes: clock.event_nbytes,
          flags: 0,
        })
      } else {
        match minimum {
          Some(current) if current <= remaining => ()
          _ => minimum = Some(remaining)
        }
      }
    }
  }
  minimum
}

///|
fn write_poll_event(
  mem : @runtime.Memory,
  event_ptr : Int,
  event : PollEvent,
) -> Unit {
  mem.write_i64(event_ptr, event.userdata)
  mem.write_byte(event_ptr + 8, (event.error & 0xFF).to_byte())
  mem.write_byte(event_ptr + 9, ((event.error >> 8) & 0xFF).to_byte())
  mem.write_byte(event_ptr + 10, event.event_type.to_byte())
  for j in 11..<16 {
    mem.write_byte(event_ptr + j, b'\x00')
  }
  mem.write_i64(event_ptr + 16, event.nbytes)
  mem.write_byte(event_ptr + 24, (event.flags & 0xFF).to_byte())
  mem.write_byte(event_ptr + 25, ((event.flags >> 8) & 0xFF).to_byte())
  for j in 26..<32 {
    mem.write_byte(event_ptr + j, b'\x00')
  }
}

///|
/// Wait for one or more WASI Preview 1 subscriptions.
///
/// All guest subscriptions are decoded and validated before waiting or writing
/// output. This keeps fast paths from accepting a wider ABI than the general
/// path and makes overlapping input/output buffers safe.
pub fn poll_oneoff_impl(
  ctx : WasiContext,
  mem : @runtime.Memory,
  in_ptr : Int,
  out_ptr : Int,
  nsubscriptions : Int,
  nevents_ptr : Int,
) -> Int {
  let subscription_count = nsubscriptions.reinterpret_as_uint()
  if subscription_count == 0U {
    return Errno::Inval.to_i32()
  }
  if !check_mem_range(mem, nevents_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  if !check_poll_array_range(mem, in_ptr, subscription_count, 48UL) ||
    !check_poll_array_range(mem, out_ptr, subscription_count, 32UL) ||
    subscription_count.to_uint64() > 2_147_483_647UL {
    return Errno::Fault.to_i32()
  }
  let count = subscription_count.reinterpret_as_int()
  let descriptors = poll_descriptor_context(ctx)
  let subscriptions = match
    decode_poll_subscriptions(descriptors, mem, in_ptr, count) {
    Ok(subscriptions) => subscriptions
    Err(errno) => return errno.to_i32()
  }
  let ready : Array[PollEvent?] = Array::make(count, None)
  let fds : Array[Int] = []
  let fd_events : Array[Int] = []
  let fd_subscription_indices : Array[Int] = []
  let fd_subscription_poll_indices : Array[Int] = []
  let poll_index_by_fd : Map[Int, Int] = Map([])
  for i, subscription in subscriptions {
    if subscription is FdPoll(fd_sub) {
      match fd_sub.source {
        Native(fd) => {
          let requested = if fd_sub.event_type == 1 { 0x01 } else { 0x04 }
          let poll_idx = match poll_index_by_fd.get(fd) {
            Some(existing) => {
              fd_events[existing] = fd_events[existing] | requested
              existing
            }
            None => {
              let new_idx = fds.length()
              poll_index_by_fd.set(fd, new_idx)
              fds.push(fd)
              fd_events.push(requested)
              new_idx
            }
          }
          fd_subscription_indices.push(i)
          fd_subscription_poll_indices.push(poll_idx)
        }
        Immediate =>
          ready[i] = Some(immediate_poll_fd_event(descriptors, fd_sub))
      }
    }
  }

  let start_monotonic = poll_now_monotonic()
  for ;; {
    let minimum = mark_ready_clocks(subscriptions, ready, start_monotonic)
    let already_ready = poll_has_ready(ready)
    if fds.length() > 0 {
      let timeout_ms = if already_ready {
        0
      } else {
        match minimum {
          Some(remaining) => poll_timeout_ms(remaining)
          None => -1
        }
      }
      match poll_native_once(fds, fd_events, timeout_ms) {
        HostInterrupted => continue
        HostFailed(errno) => return errno
        HostReady(revents) =>
          for i, sub_idx in fd_subscription_indices {
            let poll_idx = fd_subscription_poll_indices[i]
            if ready[sub_idx] is None &&
              subscriptions[sub_idx] is FdPoll(fd_sub) &&
              poll_fd_event(descriptors, fd_sub, revents[poll_idx])
              is Some(event) {
              ready[sub_idx] = Some(event)
            }
          }
      }
    } else if !already_ready && minimum is Some(remaining) {
      native_nanosleep(poll_sleep_ns(remaining)) |> ignore
    }

    mark_ready_clocks(subscriptions, ready, start_monotonic) |> ignore
    if poll_has_ready(ready) {
      let mut events_written = 0
      for event in ready {
        if event is Some(ready_event) {
          write_poll_event(mem, out_ptr + events_written * 32, ready_event)
          events_written = events_written + 1
        }
      }
      mem.write_i32(nevents_ptr, events_written)
      return Errno::Success.to_i32()
    }
  }
}
