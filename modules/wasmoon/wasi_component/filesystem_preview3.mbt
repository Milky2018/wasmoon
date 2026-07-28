///|
fn preview3_filesystem_error_index(preview1_errno : Int) -> Int {
  match preview1_errno {
    2 => 0
    7 => 1
    8 => 2
    10 => 3
    16 => 4
    19 => 5
    20 => 6
    22 => 7
    25 => 8
    26 => 9
    27 => 10
    28 => 11
    29 => 12
    31 => 13
    32 => 14
    34 => 15
    35 => 16
    37 => 17
    43 => 18
    44 => 19
    46 => 20
    48 => 21
    51 => 22
    54 => 23
    55 => 24
    56 => 25
    58 => 26
    59 => 27
    60 => 28
    61 => 29
    63 => 30
    64 => 31
    69 => 32
    70 => 33
    74 => 34
    75 => 35
    _ => 12
  }
}

///|
fn preview3_filesystem_error_code(index : Int) -> @runtime_impl.ComponentValue {
  Variant(1, Some(U32(index)))
}

///|
fn preview3_filesystem_error_for(
  errno : @wasi.Errno,
) -> @runtime_impl.ComponentValue {
  preview3_filesystem_error_code(
    preview3_filesystem_error_index(errno.to_i32()),
  )
}

///|
fn preview3_filesystem_error() -> @runtime_impl.ComponentValue {
  preview3_filesystem_error_code(
    preview3_filesystem_error_index(@wasi.native_last_errno_to_wasi()),
  )
}

///|
fn preview3_filesystem_ok_void() -> @runtime_impl.ComponentValue {
  Variant(0, None)
}

///|
fn preview3_filesystem_ok(
  value : @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  Variant(0, Some(value))
}

///|
fn preview3_ready_future(
  values : Array[@runtime_impl.ComponentValue],
) -> @runtime_impl.HostFuture {
  HostFuture(fn() { Ready(values.copy()) }, fn() { () })
}

///|
fn preview3_filesystem_types(
  host : WasiComponentHost,
) -> Array[@component.TypeDef?] {
  wasi_preview3_type_space(name => host.resolve_resource_type(name))
}

///|
fn preview3_stream_future_types(
  host : WasiComponentHost,
  interface : String,
  function : String,
) -> (@component.ValType, @component.ValType, Array[@component.TypeDef?]) raise @runtime_impl.ComponentRuntimeError {
  let types = preview3_filesystem_types(host)
  guard preview3_func(interface, function).result is Some(TypeIdx(tuple_index)) &&
    types.get(tuple_index)
    is Some(Some(Tuple([TypeIdx(stream_index), TypeIdx(future_index)]))) &&
    types.get(stream_index) is Some(Some(Stream(Some(stream_element)))) &&
    types.get(future_index) is Some(Some(Future(Some(future_element)))) else {
    raise HostCallError("generated Preview 3 stream contract is malformed")
  }
  (stream_element, future_element, types)
}

///|
fn preview3_descriptor_state(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  descriptor_type : @component.TypeDef?,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> DescriptorState raise @runtime_impl.ComponentRuntimeError {
  descriptor_state(
    host.ctx,
    resource_rep(table, resource_handle_arg(args, index), descriptor_type),
  )
}

///|
fn preview3_descriptor_stat_value(
  stat : @wasi.FileStat,
) -> @runtime_impl.ComponentValue {
  Tuple([
    U32(native_file_type_to_component(stat.filetype)),
    U64(stat.nlink.reinterpret_as_int64()),
    U64(stat.size.reinterpret_as_int64()),
    datetime_value(stat.atim),
    datetime_value(stat.mtim),
    datetime_value(stat.ctim),
  ])
}

///|
fn preview3_result_future(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  interface : String,
  function : String,
  error_case? : Int,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  let (element, types) = preview3_future_element(host, interface, function)
  match error_case {
    Some(error_case) =>
      host.runtime.new_host_unit_result_future(
        table,
        element,
        types,
        error_case~,
      )
    None => host.runtime.new_host_unit_result_future(table, element, types)
  }
}

///|
fn preview3_read_file(state : DescriptorState, offset : Int64) -> (Bytes, Int?) {
  if !descriptor_has(state, descriptor_read) {
    return (
      b"",
      Some(preview3_filesystem_error_index(@wasi.Errno::Acces.to_i32())),
    )
  }
  if offset < 0L {
    return (
      b"",
      Some(preview3_filesystem_error_index(@wasi.Errno::Overflow.to_i32())),
    )
  }
  let bytes : Array[Byte] = []
  let mut position = offset
  let mut done = false
  while !done {
    let buffer = FixedArray::make(65536, b'\x00')
    match @wasi.native_pread(state.fd, buffer, buffer.length(), position) {
      None =>
        return (
          b"",
          Some(
            preview3_filesystem_error_index(@wasi.native_last_errno_to_wasi()),
          ),
        )
      Some(count) => {
        for i in 0..<count {
          bytes.push(buffer[i])
        }
        position = position + count.to_int64()
        done = count < buffer.length()
      }
    }
  }
  (Bytes::from_array(bytes), None)
}

///|
fn preview3_file_write_future(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  state : DescriptorState,
  readable : Int,
  initial_offset : Int64,
  append : Bool,
) -> @runtime_impl.HostFuture {
  let offset = Ref(initial_offset)
  let done = Ref(false)
  fn cleanup() -> Unit raise @runtime_impl.ComponentRuntimeError {
    if !done.val {
      host.runtime.drop_host_readable_stream(table, readable)
      done.val = true
    }
  }

  HostFuture(
    () => {
      if done.val {
        return Ready([preview3_filesystem_ok_void()])
      }
      while true {
        match host.runtime.read_host_byte_stream(table, readable) {
          Pending => return Pending
          Closed => {
            cleanup()
            return Ready([preview3_filesystem_ok_void()])
          }
          Data(bytes) => {
            let mut written_total = 0
            while written_total < bytes.length() {
              let remaining = bytes.length() - written_total
              let buffer = FixedArray::makei(remaining, fn(i) {
                bytes[written_total + i]
              })
              let write_offset = if append {
                match @wasi.native_fstat(state.fd) {
                  Some(stat) if stat.size <= 0x7fffffffffffffffUL =>
                    stat.size.reinterpret_as_int64()
                  _ => {
                    cleanup()
                    return Ready([preview3_filesystem_error()])
                  }
                }
              } else {
                offset.val
              }
              match
                @wasi.native_pwrite(
                  state.fd,
                  buffer,
                  buffer.length(),
                  write_offset,
                ) {
                Some(written) if written > 0 => {
                  written_total = written_total + written
                  if !append {
                    offset.val = offset.val + written.to_int64()
                  }
                }
                _ => {
                  let error = preview3_filesystem_error()
                  cleanup()
                  return Ready([error])
                }
              }
            }
          }
        }
      } nobreak {
        Ready([preview3_filesystem_error()])
      }
    },
    () => cleanup(),
  )
}

///|
fn add_preview3_filesystem_stream_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@\{preview3_version}/types"
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@\{preview3_version}/types.descriptor",
  )
  builder.add_func(
    "[method]descriptor.read-via-stream",
    preview3_func(interface, "[method]descriptor.read-via-stream"),
    (args, table) => {
      let state = preview3_descriptor_state(
        host, table, descriptor_type, args, 0,
      )
      let (bytes, error_case) = preview3_read_file(
        state,
        filesystem_u64_arg(args, 1),
      )
      let readable = host.runtime.new_host_byte_stream(table, bytes)
      let future = match error_case {
        Some(error_case) =>
          preview3_result_future(
            host,
            table,
            interface,
            "[method]descriptor.read-via-stream",
            error_case~,
          )
        None =>
          preview3_result_future(
            host, table, interface, "[method]descriptor.read-via-stream",
          )
      }
      [Tuple([U32(readable), U32(future)])]
    },
  )
  builder.add_async_func(
    "[method]descriptor.write-via-stream",
    preview3_func(interface, "[method]descriptor.write-via-stream"),
    (args, table) => {
      guard args is [U32(descriptor), U32(readable), U64(offset)] else {
        raise HostCallError("expected descriptor, byte stream, and offset")
      }
      let state = preview3_descriptor_state(
        host,
        table,
        descriptor_type,
        [U32(descriptor)],
        0,
      )
      if !descriptor_has(state, descriptor_write) {
        host.runtime.drop_host_readable_stream(table, readable)
        return preview3_ready_future([preview3_filesystem_error_for(Acces)])
      }
      if offset < 0L {
        host.runtime.drop_host_readable_stream(table, readable)
        return preview3_ready_future([preview3_filesystem_error_for(Overflow)])
      }
      preview3_file_write_future(host, table, state, readable, offset, false)
    },
  )
  builder.add_async_func(
    "[method]descriptor.append-via-stream",
    preview3_func(interface, "[method]descriptor.append-via-stream"),
    (args, table) => {
      guard args is [U32(descriptor), U32(readable)] else {
        raise HostCallError("expected descriptor and byte stream")
      }
      let state = preview3_descriptor_state(
        host,
        table,
        descriptor_type,
        [U32(descriptor)],
        0,
      )
      if !descriptor_has(state, descriptor_write) {
        host.runtime.drop_host_readable_stream(table, readable)
        return preview3_ready_future([preview3_filesystem_error_for(Acces)])
      }
      preview3_file_write_future(host, table, state, readable, 0L, true)
    },
  )
}

///|
fn preview3_filesystem_basic_operation(
  host : WasiComponentHost,
  descriptor_type : @component.TypeDef?,
  name : String,
  args : Array[@runtime_impl.ComponentValue],
  table : @runtime_impl.ResourceTable,
) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
  let state = preview3_descriptor_state(host, table, descriptor_type, args, 0)
  match name {
    "advise" => {
      filesystem_u64_arg(args, 1) |> ignore
      filesystem_u64_arg(args, 2) |> ignore
      [preview3_filesystem_ok_void()]
    }
    "sync-data" =>
      [
        if @wasi.native_fdatasync(state.fd) {
          preview3_filesystem_ok_void()
        } else {
          preview3_filesystem_error()
        },
      ]
    "get-flags" => [preview3_filesystem_ok(U32(state.flags))]
    "get-type" =>
      [
        preview3_filesystem_ok(
          U32(native_file_type_to_component(state.file_type)),
        ),
      ]
    "set-size" => {
      let size = filesystem_u64_arg(args, 1)
      if !descriptor_has(state, descriptor_write) {
        [preview3_filesystem_error_for(Acces)]
      } else if size < 0L {
        [preview3_filesystem_error_for(Overflow)]
      } else {
        [
          if @wasi.native_ftruncate(state.fd, size) {
            preview3_filesystem_ok_void()
          } else {
            preview3_filesystem_error()
          },
        ]
      }
    }
    "set-times" =>
      [
        match
          (
            parse_new_timestamp(args[1], 0x01, 0x02),
            parse_new_timestamp(args[2], 0x04, 0x08),
          ) {
          (Some((atim, af)), Some((mtim, mf))) =>
            if @wasi.native_futimens(state.fd, atim, mtim, af | mf) {
              preview3_filesystem_ok_void()
            } else {
              preview3_filesystem_error()
            }
          _ => preview3_filesystem_error_for(Inval)
        },
      ]
    "sync" =>
      [
        if @wasi.native_fsync(state.fd) {
          preview3_filesystem_ok_void()
        } else {
          preview3_filesystem_error()
        },
      ]
    "stat" =>
      [
        match @wasi.native_fstat(state.fd) {
          Some(stat) =>
            preview3_filesystem_ok(preview3_descriptor_stat_value(stat))
          None => preview3_filesystem_error()
        },
      ]
    "is-same-object" => {
      let other = preview3_descriptor_state(
        host, table, descriptor_type, args, 1,
      )
      let same = match
        (@wasi.native_fstat(state.fd), @wasi.native_fstat(other.fd)) {
        (Some(a), Some(b)) => a.dev == b.dev && a.ino == b.ino
        _ => false
      }
      [Bool(same)]
    }
    "metadata-hash" =>
      [
        match @wasi.native_fstat(state.fd) {
          Some(stat) =>
            preview3_filesystem_ok(
              Tuple([
                U64((stat.dev ^ stat.ino ^ stat.size).reinterpret_as_int64()),
                U64((stat.mtim ^ stat.ctim ^ stat.nlink).reinterpret_as_int64()),
              ]),
            )
          None => preview3_filesystem_error()
        },
      ]
    _ => raise HostCallError("unknown Preview 3 filesystem operation")
  }
}

///|
fn add_preview3_filesystem_basic_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@\{preview3_version}/types"
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@\{preview3_version}/types.descriptor",
  )
  for
    name in [
      "advise", "sync-data", "get-flags", "get-type", "set-size", "set-times", "sync",
      "stat", "is-same-object", "metadata-hash",
    ] {
    let export_name = "[method]descriptor.\{name}"
    builder.add_async_func(export_name, preview3_func(interface, export_name), (
      args,
      table,
    ) => {
      preview3_ready_future(
        preview3_filesystem_basic_operation(
          host, descriptor_type, name, args, table,
        ),
      )
    })
  }
}

///|
fn preview3_filesystem_path_operation(
  host : WasiComponentHost,
  descriptor_type : @component.TypeDef?,
  name : String,
  args : Array[@runtime_impl.ComponentValue],
  table : @runtime_impl.ResourceTable,
) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
  let state = preview3_descriptor_state(host, table, descriptor_type, args, 0)
  fn reject_path(path : String) -> Bool {
    capability_parent_and_leaf(path) is None
  }

  match name {
    "create-directory-at" => {
      let path = filesystem_string_arg(args, 1)
      if !descriptor_has(state, descriptor_mutate_directory) {
        return [preview3_filesystem_error_for(ROFS)]
      }
      if reject_path(path) {
        return [preview3_filesystem_error_for(Perm)]
      }
      match open_capability_parent(state, path) {
        None => [preview3_filesystem_error()]
        Some((parent, leaf)) => {
          let success = @wasi.native_mkdirat(parent, leaf, 0o755)
          @wasi.native_close(parent) |> ignore
          [
            if success {
              preview3_filesystem_ok_void()
            } else {
              preview3_filesystem_error()
            },
          ]
        }
      }
    }
    "stat-at" | "metadata-hash-at" => {
      let follow = (filesystem_flags_arg(args, 1) & 0x01) != 0
      let path = filesystem_string_arg(args, 2)
      if reject_path(path) {
        return [preview3_filesystem_error_for(Perm)]
      }
      match stat_capability_path(state, path, follow) {
        None => [preview3_filesystem_error()]
        Some(stat) =>
          if name == "stat-at" {
            [preview3_filesystem_ok(preview3_descriptor_stat_value(stat))]
          } else {
            [
              preview3_filesystem_ok(
                Tuple([
                  U64((stat.dev ^ stat.ino ^ stat.size).reinterpret_as_int64()),
                  U64(
                    (stat.mtim ^ stat.ctim ^ stat.nlink).reinterpret_as_int64(),
                  ),
                ]),
              ),
            ]
          }
      }
    }
    "set-times-at" => {
      if !descriptor_has(state, descriptor_mutate_directory) {
        return [preview3_filesystem_error_for(ROFS)]
      }
      let follow = (filesystem_flags_arg(args, 1) & 0x01) != 0
      let path = filesystem_string_arg(args, 2)
      if reject_path(path) {
        return [preview3_filesystem_error_for(Perm)]
      }
      guard parse_new_timestamp(args[3], 0x01, 0x02) is Some((atim, af)) &&
        parse_new_timestamp(args[4], 0x04, 0x08) is Some((mtim, mf)) else {
        return [preview3_filesystem_error_for(Inval)]
      }
      if follow {
        match capability_parent_and_leaf(path) {
          None => [preview3_filesystem_error_for(Perm)]
          Some((parent, leaf)) =>
            match
              @wasi.native_openat_beneath(
                state.fd,
                parent,
                leaf,
                [ReadOnly],
                0,
                true,
              ) {
              None => [preview3_filesystem_error()]
              Some(fd) => {
                let success = @wasi.native_futimens(fd, atim, mtim, af | mf)
                @wasi.native_close(fd) |> ignore
                [
                  if success {
                    preview3_filesystem_ok_void()
                  } else {
                    preview3_filesystem_error()
                  },
                ]
              }
            }
        }
      } else {
        match open_capability_parent(state, path) {
          None => [preview3_filesystem_error()]
          Some((parent, leaf)) => {
            let success = @wasi.native_utimensat(
              parent,
              leaf,
              atim,
              mtim,
              af | mf,
              @wasi.AT_SYMLINK_NOFOLLOW,
            )
            @wasi.native_close(parent) |> ignore
            [
              if success {
                preview3_filesystem_ok_void()
              } else {
                preview3_filesystem_error()
              },
            ]
          }
        }
      }
    }
    "open-at" => {
      let path_flags = filesystem_flags_arg(args, 1)
      let path = filesystem_string_arg(args, 2)
      let open_flags = filesystem_flags_arg(args, 3)
      let requested_flags = filesystem_flags_arg(args, 4)
      let mutating = (
          requested_flags & (descriptor_write | descriptor_mutate_directory)
        ) !=
        0 ||
        (open_flags & (0x01 | 0x08)) != 0
      if mutating && !descriptor_has(state, descriptor_mutate_directory) {
        return [preview3_filesystem_error_for(ROFS)]
      }
      if (requested_flags & descriptor_read) != 0 &&
        !descriptor_has(state, descriptor_read) {
        return [preview3_filesystem_error_for(Acces)]
      }
      let native_flags = descriptor_flags_to_open(requested_flags)
      if (open_flags & 0x01) != 0 {
        native_flags.push(Create)
      }
      if (open_flags & 0x02) != 0 {
        native_flags.push(Directory)
      }
      if (open_flags & 0x04) != 0 {
        native_flags.push(Exclusive)
      }
      if (open_flags & 0x08) != 0 {
        native_flags.push(Truncate)
      }
      match capability_parent_and_leaf(path) {
        None => [preview3_filesystem_error_for(Perm)]
        Some((parent, leaf)) =>
          match
            @wasi.native_openat_beneath(
              state.fd,
              parent,
              leaf,
              native_flags,
              0o644,
              (path_flags & 0x01) != 0,
            ) {
            Some(fd) =>
              [
                new_descriptor_resource(
                  host, table, descriptor_type, fd, requested_flags,
                ),
              ]
            None => [preview3_filesystem_error()]
          }
      }
    }
    "readlink-at" => {
      let path = filesystem_string_arg(args, 1)
      if reject_path(path) {
        return [preview3_filesystem_error_for(Perm)]
      }
      match open_capability_parent(state, path) {
        None => [preview3_filesystem_error()]
        Some((parent, leaf)) => {
          let target = @wasi.native_readlinkat(parent, leaf, 65536)
          @wasi.native_close(parent) |> ignore
          match target {
            Some(target) =>
              if target.has_prefix("/") {
                [preview3_filesystem_error_for(Perm)]
              } else {
                [preview3_filesystem_ok(String(target))]
              }
            None => [preview3_filesystem_error()]
          }
        }
      }
    }
    "remove-directory-at" | "unlink-file-at" => {
      if !descriptor_has(state, descriptor_mutate_directory) {
        return [preview3_filesystem_error_for(ROFS)]
      }
      let path = filesystem_string_arg(args, 1)
      if reject_path(path) {
        return [preview3_filesystem_error_for(Perm)]
      }
      match open_capability_parent(state, path) {
        None => [preview3_filesystem_error()]
        Some((parent, leaf)) => {
          let success = @wasi.native_unlinkat(
            parent,
            leaf,
            if name == "remove-directory-at" {
              @wasi.AT_REMOVEDIR
            } else {
              0
            },
          )
          @wasi.native_close(parent) |> ignore
          [
            if success {
              preview3_filesystem_ok_void()
            } else {
              preview3_filesystem_error()
            },
          ]
        }
      }
    }
    "rename-at" | "link-at" => {
      let (old_path_index, new_descriptor_index, new_path_index) = if name ==
        "link-at" {
        (2, 3, 4)
      } else {
        (1, 2, 3)
      }
      if name == "link-at" && (filesystem_flags_arg(args, 1) & 0x01) != 0 {
        return [preview3_filesystem_error_for(NotSup)]
      }
      let target_state = preview3_descriptor_state(
        host, table, descriptor_type, args, new_descriptor_index,
      )
      if !descriptor_has(target_state, descriptor_mutate_directory) ||
        (
          name == "rename-at" &&
          !descriptor_has(state, descriptor_mutate_directory)
        ) {
        return [preview3_filesystem_error_for(ROFS)]
      }
      let old_path = filesystem_string_arg(args, old_path_index)
      let new_path = filesystem_string_arg(args, new_path_index)
      if reject_path(old_path) || reject_path(new_path) {
        return [preview3_filesystem_error_for(Perm)]
      }
      match
        (
          open_capability_parent(state, old_path),
          open_capability_parent(target_state, new_path),
        ) {
        (Some((old_fd, old_leaf)), Some((new_fd, new_leaf))) => {
          let success = if name == "link-at" {
            @wasi.native_linkat(old_fd, old_leaf, new_fd, new_leaf, 0)
          } else {
            @wasi.native_renameat(old_fd, old_leaf, new_fd, new_leaf)
          }
          @wasi.native_close(old_fd) |> ignore
          @wasi.native_close(new_fd) |> ignore
          [
            if success {
              preview3_filesystem_ok_void()
            } else {
              preview3_filesystem_error()
            },
          ]
        }
        (Some((old_fd, _)), None) => {
          @wasi.native_close(old_fd) |> ignore
          [preview3_filesystem_error()]
        }
        (None, Some((new_fd, _))) => {
          @wasi.native_close(new_fd) |> ignore
          [preview3_filesystem_error()]
        }
        _ => [preview3_filesystem_error()]
      }
    }
    "symlink-at" => {
      if !descriptor_has(state, descriptor_mutate_directory) {
        return [preview3_filesystem_error_for(ROFS)]
      }
      let target = filesystem_string_arg(args, 1)
      let path = filesystem_string_arg(args, 2)
      if target.has_prefix("/") || reject_path(path) {
        return [preview3_filesystem_error_for(Perm)]
      }
      match open_capability_parent(state, path) {
        None => [preview3_filesystem_error()]
        Some((parent, leaf)) => {
          let success = @wasi.native_symlinkat(target, parent, leaf)
          @wasi.native_close(parent) |> ignore
          [
            if success {
              preview3_filesystem_ok_void()
            } else {
              preview3_filesystem_error()
            },
          ]
        }
      }
    }
    _ => raise HostCallError("unknown Preview 3 filesystem path operation")
  }
}

///|
fn add_preview3_filesystem_path_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@\{preview3_version}/types"
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@\{preview3_version}/types.descriptor",
  )
  for
    name in [
      "create-directory-at", "stat-at", "set-times-at", "link-at", "open-at", "readlink-at",
      "remove-directory-at", "rename-at", "symlink-at", "unlink-file-at", "metadata-hash-at",
    ] {
    let export_name = "[method]descriptor.\{name}"
    builder.add_async_func(export_name, preview3_func(interface, export_name), (
      args,
      table,
    ) => {
      preview3_ready_future(
        preview3_filesystem_path_operation(
          host, descriptor_type, name, args, table,
        ),
      )
    })
  }
}

///|
fn add_preview3_read_directory(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@\{preview3_version}/types"
  let function = "[method]descriptor.read-directory"
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@\{preview3_version}/types.descriptor",
  )
  builder.add_async_func(function, preview3_func(interface, function), (
    args,
    table,
  ) => {
    let state = preview3_descriptor_state(host, table, descriptor_type, args, 0)
    let (stream_element, _future_element, types) = preview3_stream_future_types(
      host, interface, function,
    )
    let entries : Array[@runtime_impl.ComponentValue] = []
    let error_case = if state.file_type != 3 {
      Some(preview3_filesystem_error_index(@wasi.Errno::NotDir.to_i32()))
    } else {
      match @wasi.native_readdir_fd(state.fd) {
        None =>
          Some(
            preview3_filesystem_error_index(@wasi.native_last_errno_to_wasi()),
          )
        Some(native_entries) => {
          for entry in native_entries {
            let (name, is_directory) = entry
            entries.push(
              Tuple([U32(if is_directory { 3 } else { 4 }), String(name)]),
            )
          }
          None
        }
      }
    }
    let readable = host.runtime.new_host_value_stream(
      table, stream_element, types, entries,
    )
    let future = match error_case {
      Some(error_case) =>
        preview3_result_future(host, table, interface, function, error_case~)
      None => preview3_result_future(host, table, interface, function)
    }
    preview3_ready_future([Tuple([U32(readable), U32(future)])])
  })
}

///|
fn add_preview3_filesystem_types(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@\{preview3_version}/types"
  let builder = host.linker.host_instance_builder(
    "wasi:filesystem/types@\{preview3_version}",
    host.runtime,
  )
  host.prepare_preview3_interface(builder, interface)
  add_preview3_filesystem_stream_methods(host, builder)
  add_preview3_filesystem_basic_methods(host, builder)
  add_preview3_filesystem_path_methods(host, builder)
  add_preview3_read_directory(host, builder)
  host.linker.add_instance(
    "wasi:filesystem/types@\{preview3_version}",
    builder.finish(),
  )
}

///|
fn add_preview3_preopens(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@\{preview3_version}/preopens"
  let builder = host.linker.host_instance_builder(
    "wasi:filesystem/preopens@\{preview3_version}",
    host.runtime,
  )
  host.prepare_preview3_interface(builder, interface)
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@\{preview3_version}/types.descriptor",
  )
  builder.add_func(
    "get-directories",
    preview3_func(interface, "get-directories"),
    (args, table) => {
      empty_args(args)
      let values : Array[@runtime_impl.ComponentValue] = []
      for preopen in host.ctx.preopens {
        if preopen.closed.val {
          raise HostCallError("preopen '\{preopen.guest_path}' is closed")
        }
        guard @wasi.native_dup(preopen.fd) is Some(fd) else {
          raise HostCallError(
            "cannot duplicate preopen '\{preopen.guest_path}'",
          )
        }
        let rep = host.ctx.insert_resource(
          Descriptor({
            fd,
            flags: preopen.flags,
            file_type: 3,
            closed: Ref(false),
          }),
        )
        let handle = allocate_resource_handle(
          host.ctx,
          table,
          descriptor_type,
          rep,
        )
        values.push(Tuple([U32(handle), String(preopen.guest_path)]))
      }
      [List(values)]
    },
  )
  host.linker.add_instance(
    "wasi:filesystem/preopens@\{preview3_version}",
    builder.finish(),
  )
}

///|
pub fn WasiComponentHost::add_preview3_filesystem(
  self : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_preview3_filesystem_types(self)
  add_preview3_preopens(self)
}
