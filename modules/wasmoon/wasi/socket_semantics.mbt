///|
extern "c" fn c_socket_kind(fd : Int) -> Int = "wasmoon_wasi_socket_kind"

///|
#borrow(buffer, truncated)
extern "c" fn c_p1_recv(
  fd : Int,
  buffer : FixedArray[Byte],
  length : Int,
  flags : Int,
  truncated : FixedArray[Int],
) -> Int = "wasmoon_wasi_p1_recv"

///|
#borrow(buffer)
extern "c" fn c_p1_send(
  fd : Int,
  buffer : FixedArray[Byte],
  length : Int,
) -> Int = "wasmoon_wasi_p1_send"

///|
let socket_rights : Int64 = right_fd_read |
  right_fd_write |
  right_fd_fdstat_set_flags |
  right_fd_filestat_get |
  right_poll_fd_readwrite |
  right_sock_shutdown |
  right_sock_accept

///|
/// Transfer an already-created native socket into this context. On error the
/// caller retains ownership. On success close_fd owns its lifetime. Windows
/// sockets must be descriptors returned by the native socket adapter, not raw
/// pointer-sized Winsock SOCKET values. No guest network creation is granted.
pub fn WasiContext::take_socket(
  self : WasiContext,
  native_fd : Int,
  rights_base? : Int64 = socket_rights,
  rights_inheriting? : Int64 = socket_rights,
) -> Result[Int, Int] {
  if (rights_base & socket_rights.lnot()) != 0L ||
    (rights_inheriting & socket_rights.lnot()) != 0L {
    return Err(Errno::Inval.to_i32())
  }
  let kind = c_socket_kind(native_fd)
  if kind < 0 {
    return Err(native_last_errno_to_wasi())
  }
  let flags = match native_fcntl_getfl(native_fd) {
    Some(flags) => if (flags & native_o_nonblock()) != 0 { 4 } else { 0 }
    None => return Err(native_last_errno_to_wasi())
  }
  Ok(
    self.alloc_fd({
      native_fd,
      file_type: if kind == 1 {
        SocketStream
      } else {
        SocketDatagram
      },
      host_path: "",
      position: 0L,
      flags,
      rights_base,
      rights_inheriting,
    }),
  )
}

///|
fn socket_iovecs(
  mem : @runtime.Memory,
  ptr : Int,
  count : Int,
) -> Result[(Array[(Int, Int)], Int), Int] {
  if !check_iovecs_mem_range(mem, ptr, count) {
    return Err(Errno::Fault.to_i32())
  }
  let entries : Array[(Int, Int)] = []
  let mut length = 0L
  for i in 0..<count {
    let start = mem.read_i32(ptr + i * 8)
    let size = mem.read_i32(ptr + i * 8 + 4)
    length += size.to_int64()
    if length > 0x7FFFFFFFL {
      return Err(Errno::Overflow.to_i32())
    }
    entries.push((start, size))
  }
  Ok((entries, length.to_int()))
}

///|
fn socket_receive(
  mem : @runtime.Memory,
  file : OpenFile,
  ri_data_ptr : Int,
  ri_data_len : Int,
  ri_flags : Int,
) -> Result[(Int, Int), Int] {
  let (entries, length) = match socket_iovecs(mem, ri_data_ptr, ri_data_len) {
    Ok(value) => value
    Err(errno) => return Err(errno)
  }
  let buffer = FixedArray::make(length, b'\x00')
  let truncated = FixedArray::make(1, 0)
  let received = if length == 0 && file.file_type is SocketStream {
    0
  } else {
    c_p1_recv(file.native_fd, buffer, length, ri_flags, truncated)
  }
  if received < 0 {
    return Err(native_last_errno_to_wasi())
  }
  let mut offset = 0
  for entry in entries {
    let (start, size) = entry
    let copied = @cmp.minimum(size, received - offset)
    for i in 0..<copied {
      mem.write_byte(start + i, buffer[offset + i])
    }
    offset += copied
  }
  Ok((received, truncated[0]))
}
