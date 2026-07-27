///|
fn filesystem_error_index(preview1_errno : Int) -> Int {
  match preview1_errno {
    2 => 0
    6 => 1
    7 => 2
    8 => 3
    10 => 4
    16 => 5
    19 => 6
    20 => 7
    22 => 8
    25 => 9
    26 => 10
    27 => 11
    28 => 12
    29 => 13
    31 => 14
    32 => 15
    34 => 16
    35 => 17
    37 => 18
    43 => 19
    44 => 20
    46 => 21
    48 => 22
    51 => 23
    54 => 24
    55 => 25
    56 => 26
    58 => 27
    59 => 28
    60 => 29
    61 => 30
    63 => 31
    64 => 32
    69 => 33
    70 => 34
    74 => 35
    75 => 36
    _ => 13
  }
}

///|
fn filesystem_error() -> @runtime_impl.ComponentValue {
  Variant(
    1,
    Some(
      Variant(filesystem_error_index(@wasi.native_last_errno_to_wasi()), None),
    ),
  )
}

///|
fn filesystem_error_code(index : Int) -> @runtime_impl.ComponentValue {
  Variant(1, Some(Variant(index, None)))
}

///|
fn filesystem_ok_void() -> @runtime_impl.ComponentValue {
  Variant(0, None)
}

///|
fn filesystem_ok(
  value : @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  Variant(0, Some(value))
}

///|
fn filesystem_flags_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing filesystem flags")
  }
  match args[index] {
    U32(flags) => flags
    _ => raise HostCallError("expected filesystem flags")
  }
}

///|
fn filesystem_u64_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> Int64 raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing filesystem integer")
  }
  match args[index] {
    U64(value) => value
    _ => raise HostCallError("expected filesystem u64")
  }
}

///|
fn filesystem_string_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> String raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing filesystem path")
  }
  match args[index] {
    String(value) => value
    _ => raise HostCallError("expected filesystem path")
  }
}

///|
fn normalize_capability_path(path : String) -> Array[String]? {
  if path == "" || path.has_prefix("/") {
    return None
  }
  let parts : Array[String] = []
  for part in path.split("/") {
    if part == "" || part == "." {
      continue
    }
    if part == ".." {
      if parts.length() == 0 {
        return None
      }
      parts.pop() |> ignore
    } else {
      parts.push(part.to_owned())
    }
  }
  if parts.length() == 0 {
    None
  } else {
    Some(parts)
  }
}

///|
fn capability_parent_and_leaf(path : String) -> (String, String)? {
  match normalize_capability_path(path) {
    None => None
    Some(parts) => {
      let leaf = parts.pop().unwrap()
      Some((parts.join("/"), leaf))
    }
  }
}

///|
fn descriptor_state(
  ctx : WasiComponentCtx,
  rep : Int,
) -> DescriptorState raise @runtime_impl.ComponentRuntimeError {
  match ctx.get_resource(rep) {
    Some(Descriptor(state)) if !state.closed.val => state
    _ => raise HostCallError("filesystem descriptor is not live")
  }
}

///|
fn descriptor_has(state : DescriptorState, flags : Int) -> Bool {
  (state.flags & flags) == flags
}

///|
fn native_file_type_to_component(file_type : Int) -> Int {
  match file_type {
    1 => 1
    2 => 2
    3 => 3
    7 => 5
    4 => 6
    5 | 6 => 7
    _ => 0
  }
}

///|
fn datetime_value(timestamp : UInt64) -> @runtime_impl.ComponentValue {
  let seconds = timestamp / 1_000_000_000UL
  let nanoseconds = timestamp % 1_000_000_000UL
  Variant(
    1,
    Some(
      Tuple([U64(seconds.reinterpret_as_int64()), U32(nanoseconds.to_int())]),
    ),
  )
}

///|
fn descriptor_stat_value(stat : @wasi.FileStat) -> @runtime_impl.ComponentValue {
  Tuple([
    Variant(native_file_type_to_component(stat.filetype), None),
    U64(stat.nlink.reinterpret_as_int64()),
    U64(stat.size.reinterpret_as_int64()),
    datetime_value(stat.atim),
    datetime_value(stat.mtim),
    datetime_value(stat.ctim),
  ])
}

///|
fn descriptor_flags_to_open(flags : Int) -> Array[@wasi.OpenFlags] {
  let open_flags : Array[@wasi.OpenFlags] = []
  if (flags & descriptor_read) != 0 && (flags & descriptor_write) != 0 {
    open_flags.push(ReadWrite)
  } else if (flags & descriptor_write) != 0 {
    open_flags.push(WriteOnly)
  } else {
    open_flags.push(ReadOnly)
  }
  open_flags
}

///|
fn open_capability_parent(
  state : DescriptorState,
  path : String,
) -> (Int, String)? {
  match capability_parent_and_leaf(path) {
    None => None
    Some((parent, leaf)) =>
      match @wasi.native_open_parent_beneath(state.fd, parent) {
        Some(parent_fd) => Some((parent_fd, leaf))
        None => None
      }
  }
}

///|
fn new_descriptor_resource(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  descriptor_type : @component.TypeDef?,
  fd : Int,
  flags : Int,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  match @wasi.native_fstat(fd) {
    None => {
      @wasi.native_close(fd) |> ignore
      filesystem_error()
    }
    Some(stat) => {
      let rep = host.ctx.insert_resource(
        Descriptor({ fd, flags, file_type: stat.filetype, closed: Ref(false) }),
      )
      filesystem_ok(
        U32(allocate_resource_handle(host.ctx, table, descriptor_type, rep)),
      )
    }
  }
}

///|
fn add_descriptor_stream_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@0.2.11/types"
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@0.2.11/types.descriptor",
  )
  fn state_for(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
  ) -> DescriptorState raise @runtime_impl.ComponentRuntimeError {
    let rep = resource_rep(table, resource_handle_arg(args, 0), descriptor_type)
    descriptor_state(host.ctx, rep)
  }

  builder.add_func(
    "[method]descriptor.read-via-stream",
    preview2_func(interface, "[method]descriptor.read-via-stream"),
    (args, table) => {
      let state = state_for(args, table)
      if !descriptor_has(state, descriptor_read) {
        return [filesystem_error_code(0)]
      }
      let offset = filesystem_u64_arg(args, 1)
      if offset < 0L {
        return [filesystem_error_code(30)]
      }
      match @wasi.native_dup(state.fd) {
        None => [filesystem_error()]
        Some(fd) => {
          let rep = host.ctx.insert_resource(
            InputStream({
              bytes: Ref(b""),
              offset: Ref(0),
              native_fd: Some(fd),
              file_position: Some(Ref(offset)),
              owns_fd: true,
              closed: Ref(false),
            }),
          )
          [
            filesystem_ok(
              U32(
                allocate_resource_handle(
                  host.ctx,
                  table,
                  host.resource_types.input_stream,
                  rep,
                ),
              ),
            ),
          ]
        }
      }
    },
  )
  fn output_stream(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
    append : Bool,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    let state = state_for(args, table)
    if !descriptor_has(state, descriptor_write) {
      return [filesystem_error_code(0)]
    }
    let offset = if append { 0L } else { filesystem_u64_arg(args, 1) }
    if offset < 0L {
      return [filesystem_error_code(30)]
    }
    match @wasi.native_dup(state.fd) {
      None => [filesystem_error()]
      Some(fd) => {
        let rep = host.ctx.insert_resource(
          OutputStream({
            write: fn(_bytes) { true },
            native_fd: Some(fd),
            file_position: if append {
              None
            } else {
              Some(Ref(offset))
            },
            append,
            owns_fd: true,
            permit: Ref(0L),
            closed: Ref(false),
          }),
        )
        [
          filesystem_ok(
            U32(
              allocate_resource_handle(
                host.ctx,
                table,
                host.resource_types.output_stream,
                rep,
              ),
            ),
          ),
        ]
      }
    }
  }

  builder.add_func(
    "[method]descriptor.write-via-stream",
    preview2_func(interface, "[method]descriptor.write-via-stream"),
    (args, table) => output_stream(args, table, false),
  )
  builder.add_func(
    "[method]descriptor.append-via-stream",
    preview2_func(interface, "[method]descriptor.append-via-stream"),
    (args, table) => output_stream(args, table, true),
  )
}

///|
fn add_descriptor_basic_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@0.2.11/types"
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@0.2.11/types.descriptor",
  )
  fn state_for(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
  ) -> DescriptorState raise @runtime_impl.ComponentRuntimeError {
    descriptor_state(
      host.ctx,
      resource_rep(table, resource_handle_arg(args, 0), descriptor_type),
    )
  }
  builder.add_func(
    "[method]descriptor.advise",
    preview2_func(interface, "[method]descriptor.advise"),
    (args, table) => {
      state_for(args, table) |> ignore
      filesystem_u64_arg(args, 1) |> ignore
      filesystem_u64_arg(args, 2) |> ignore
      [filesystem_ok_void()]
    },
  )
  builder.add_func(
    "[method]descriptor.sync-data",
    preview2_func(interface, "[method]descriptor.sync-data"),
    (args, table) => {
      let state = state_for(args, table)
      [
        if @wasi.native_fdatasync(state.fd) {
          filesystem_ok_void()
        } else {
          filesystem_error()
        },
      ]
    },
  )
  builder.add_func(
    "[method]descriptor.get-flags",
    preview2_func(interface, "[method]descriptor.get-flags"),
    (args, table) => [filesystem_ok(U32(state_for(args, table).flags))],
  )
  builder.add_func(
    "[method]descriptor.get-type",
    preview2_func(interface, "[method]descriptor.get-type"),
    (args, table) => {
      [
        filesystem_ok(
          Variant(
            native_file_type_to_component(state_for(args, table).file_type),
            None,
          ),
        ),
      ]
    },
  )
  builder.add_func(
    "[method]descriptor.set-size",
    preview2_func(interface, "[method]descriptor.set-size"),
    (args, table) => {
      let state = state_for(args, table)
      let size = filesystem_u64_arg(args, 1)
      if !descriptor_has(state, descriptor_write) {
        [filesystem_error_code(0)]
      } else if size < 0L {
        [filesystem_error_code(30)]
      } else {
        [
          if @wasi.native_ftruncate(state.fd, size) {
            filesystem_ok_void()
          } else {
            filesystem_error()
          },
        ]
      }
    },
  )
  builder.add_func(
    "[method]descriptor.read",
    preview2_func(interface, "[method]descriptor.read"),
    (args, table) => {
      let state = state_for(args, table)
      let length = filesystem_u64_arg(args, 1)
      let offset = filesystem_u64_arg(args, 2)
      if !descriptor_has(state, descriptor_read) {
        return [filesystem_error_code(0)]
      }
      if length < 0L || length > 0x7fffffffL || offset < 0L {
        return [filesystem_error_code(30)]
      }
      let buffer = FixedArray::make(length.to_int(), b'\x00')
      match @wasi.native_pread(state.fd, buffer, buffer.length(), offset) {
        None => [filesystem_error()]
        Some(count) => {
          let values : Array[@runtime_impl.ComponentValue] = []
          for i in 0..<count {
            values.push(U8(buffer[i].to_int()))
          }
          let eof = match @wasi.native_fstat(state.fd) {
            Some(stat) =>
              offset.reinterpret_as_uint64() + count.to_uint64() >= stat.size
            None => count == 0
          }
          [filesystem_ok(Tuple([List(values), Bool(eof)]))]
        }
      }
    },
  )
  builder.add_func(
    "[method]descriptor.write",
    preview2_func(interface, "[method]descriptor.write"),
    (args, table) => {
      let state = state_for(args, table)
      let offset = filesystem_u64_arg(args, 2)
      if !descriptor_has(state, descriptor_write) {
        return [filesystem_error_code(0)]
      }
      if offset < 0L {
        return [filesystem_error_code(30)]
      }
      let bytes = component_list_to_bytes(args[1])
      let buffer = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
      match @wasi.native_pwrite(state.fd, buffer, buffer.length(), offset) {
        Some(count) => [filesystem_ok(U64(count.to_int64()))]
        None => [filesystem_error()]
      }
    },
  )
  builder.add_func(
    "[method]descriptor.sync",
    preview2_func(interface, "[method]descriptor.sync"),
    (args, table) => {
      [
        if @wasi.native_fsync(state_for(args, table).fd) {
          filesystem_ok_void()
        } else {
          filesystem_error()
        },
      ]
    },
  )
  builder.add_func(
    "[method]descriptor.stat",
    preview2_func(interface, "[method]descriptor.stat"),
    (args, table) => {
      match @wasi.native_fstat(state_for(args, table).fd) {
        Some(stat) => [filesystem_ok(descriptor_stat_value(stat))]
        None => [filesystem_error()]
      }
    },
  )
  builder.add_func(
    "[method]descriptor.is-same-object",
    preview2_func(interface, "[method]descriptor.is-same-object"),
    (args, table) => {
      let left = state_for(args, table)
      let right = descriptor_state(
        host.ctx,
        resource_rep(table, resource_handle_arg(args, 1), descriptor_type),
      )
      let same = match
        (@wasi.native_fstat(left.fd), @wasi.native_fstat(right.fd)) {
        (Some(a), Some(b)) => a.dev == b.dev && a.ino == b.ino
        _ => false
      }
      [Bool(same)]
    },
  )
  fn metadata_hash(state : DescriptorState) -> @runtime_impl.ComponentValue {
    match @wasi.native_fstat(state.fd) {
      None => filesystem_error()
      Some(stat) => {
        let lower = stat.dev ^ stat.ino ^ stat.size
        let upper = stat.mtim ^ stat.ctim ^ stat.nlink
        filesystem_ok(
          Tuple([
            U64(lower.reinterpret_as_int64()),
            U64(upper.reinterpret_as_int64()),
          ]),
        )
      }
    }
  }

  builder.add_func(
    "[method]descriptor.metadata-hash",
    preview2_func(interface, "[method]descriptor.metadata-hash"),
    (args, table) => [metadata_hash(state_for(args, table))],
  )
}

///|
fn parse_new_timestamp(
  value : @runtime_impl.ComponentValue,
  set_flag : Int,
  now_flag : Int,
) -> (Int64, Int)? {
  match value {
    Variant(0, None) => Some((0L, 0))
    Variant(1, None) => Some((0L, now_flag))
    Variant(2, Some(Tuple([U64(seconds), U32(nanoseconds)]))) =>
      if seconds < 0L ||
        nanoseconds < 0 ||
        nanoseconds >= 1_000_000_000 ||
        seconds >
        (0x7fffffffffffffffL - nanoseconds.to_int64()) / 1_000_000_000L {
        None
      } else {
        Some((seconds * 1_000_000_000L + nanoseconds.to_int64(), set_flag))
      }
    _ => None
  }
}

///|
fn descriptor_set_times(
  state : DescriptorState,
  access : @runtime_impl.ComponentValue,
  modification : @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  match
    (
      parse_new_timestamp(access, 0x01, 0x02),
      parse_new_timestamp(modification, 0x04, 0x08),
    ) {
    (Some((atim, access_flags)), Some((mtim, modification_flags))) =>
      if @wasi.native_futimens(
          state.fd,
          atim,
          mtim,
          access_flags | modification_flags,
        ) {
        filesystem_ok_void()
      } else {
        filesystem_error()
      }
    _ => filesystem_error_code(12)
  }
}

///|
fn stat_capability_path(
  state : DescriptorState,
  path : String,
  follow_final : Bool,
) -> @wasi.FileStat? {
  match capability_parent_and_leaf(path) {
    None => None
    Some((parent, leaf)) =>
      if follow_final {
        match
          @wasi.native_openat_beneath(
            state.fd,
            parent,
            leaf,
            [ReadOnly],
            0,
            true,
          ) {
          None => None
          Some(fd) => {
            let stat = @wasi.native_fstat(fd)
            @wasi.native_close(fd) |> ignore
            stat
          }
        }
      } else {
        match @wasi.native_open_parent_beneath(state.fd, parent) {
          None => None
          Some(parent_fd) => {
            let stat = @wasi.native_fstatat(
              parent_fd,
              leaf,
              @wasi.AT_SYMLINK_NOFOLLOW,
            )
            @wasi.native_close(parent_fd) |> ignore
            stat
          }
        }
      }
  }
}

///|
fn add_descriptor_path_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@0.2.11/types"
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@0.2.11/types.descriptor",
  )
  fn state_for(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
    index : Int,
  ) -> DescriptorState raise @runtime_impl.ComponentRuntimeError {
    descriptor_state(
      host.ctx,
      resource_rep(table, resource_handle_arg(args, index), descriptor_type),
    )
  }
  builder.add_func(
    "[method]descriptor.set-times",
    preview2_func(interface, "[method]descriptor.set-times"),
    (args, table) => {
      [descriptor_set_times(state_for(args, table, 0), args[1], args[2])]
    },
  )
  builder.add_func(
    "[method]descriptor.create-directory-at",
    preview2_func(interface, "[method]descriptor.create-directory-at"),
    (args, table) => {
      let state = state_for(args, table, 0)
      if !descriptor_has(state, descriptor_mutate_directory) {
        return [filesystem_error_code(33)]
      }
      let path = filesystem_string_arg(args, 1)
      if capability_parent_and_leaf(path) is None {
        return [filesystem_error_code(31)]
      }
      match open_capability_parent(state, path) {
        None => [filesystem_error()]
        Some((parent_fd, leaf)) => {
          let success = @wasi.native_mkdirat(parent_fd, leaf, 0o755)
          @wasi.native_close(parent_fd) |> ignore
          [if success { filesystem_ok_void() } else { filesystem_error() }]
        }
      }
    },
  )
  builder.add_func(
    "[method]descriptor.stat-at",
    preview2_func(interface, "[method]descriptor.stat-at"),
    (args, table) => {
      let state = state_for(args, table, 0)
      let follow = (filesystem_flags_arg(args, 1) & 0x01) != 0
      let path = filesystem_string_arg(args, 2)
      if capability_parent_and_leaf(path) is None {
        return [filesystem_error_code(31)]
      }
      match stat_capability_path(state, path, follow) {
        Some(stat) => [filesystem_ok(descriptor_stat_value(stat))]
        None => [filesystem_error()]
      }
    },
  )
  builder.add_func(
    "[method]descriptor.set-times-at",
    preview2_func(interface, "[method]descriptor.set-times-at"),
    (args, table) => {
      let state = state_for(args, table, 0)
      if !descriptor_has(state, descriptor_mutate_directory) {
        return [filesystem_error_code(33)]
      }
      let follow = (filesystem_flags_arg(args, 1) & 0x01) != 0
      let path = filesystem_string_arg(args, 2)
      if capability_parent_and_leaf(path) is None {
        return [filesystem_error_code(31)]
      }
      match
        (
          parse_new_timestamp(args[3], 0x01, 0x02),
          parse_new_timestamp(args[4], 0x04, 0x08),
        ) {
        (Some((atim, af)), Some((mtim, mf))) =>
          if follow {
            match capability_parent_and_leaf(path) {
              None => [filesystem_error_code(31)]
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
                  None => [filesystem_error()]
                  Some(fd) => {
                    let success = @wasi.native_futimens(fd, atim, mtim, af | mf)
                    @wasi.native_close(fd) |> ignore
                    [
                      if success {
                        filesystem_ok_void()
                      } else {
                        filesystem_error()
                      },
                    ]
                  }
                }
            }
          } else {
            match open_capability_parent(state, path) {
              None => [filesystem_error()]
              Some((parent_fd, leaf)) => {
                let success = @wasi.native_utimensat(
                  parent_fd,
                  leaf,
                  atim,
                  mtim,
                  af | mf,
                  @wasi.AT_SYMLINK_NOFOLLOW,
                )
                @wasi.native_close(parent_fd) |> ignore
                [
                  if success {
                    filesystem_ok_void()
                  } else {
                    filesystem_error()
                  },
                ]
              }
            }
          }
        _ => [filesystem_error_code(12)]
      }
    },
  )
  builder.add_func(
    "[method]descriptor.open-at",
    preview2_func(interface, "[method]descriptor.open-at"),
    (args, table) => {
      let state = state_for(args, table, 0)
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
        return [filesystem_error_code(33)]
      }
      if (requested_flags & descriptor_read) != 0 &&
        !descriptor_has(state, descriptor_read) {
        return [filesystem_error_code(0)]
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
        None => [filesystem_error_code(31)]
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
            None => [filesystem_error()]
          }
      }
    },
  )
  builder.add_func(
    "[method]descriptor.readlink-at",
    preview2_func(interface, "[method]descriptor.readlink-at"),
    (args, table) => {
      let state = state_for(args, table, 0)
      let path = filesystem_string_arg(args, 1)
      if capability_parent_and_leaf(path) is None {
        return [filesystem_error_code(31)]
      }
      match open_capability_parent(state, path) {
        None => [filesystem_error()]
        Some((parent_fd, leaf)) => {
          let target = @wasi.native_readlinkat(parent_fd, leaf, 65536)
          @wasi.native_close(parent_fd) |> ignore
          match target {
            Some(target) =>
              if target.has_prefix("/") {
                [filesystem_error_code(31)]
              } else {
                [filesystem_ok(String(target))]
              }
            None => [filesystem_error()]
          }
        }
      }
    },
  )
  fn unlink_at(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
    flags : Int,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    let state = state_for(args, table, 0)
    if !descriptor_has(state, descriptor_mutate_directory) {
      return [filesystem_error_code(33)]
    }
    let path = filesystem_string_arg(args, 1)
    if capability_parent_and_leaf(path) is None {
      return [filesystem_error_code(31)]
    }
    match open_capability_parent(state, path) {
      None => [filesystem_error()]
      Some((parent_fd, leaf)) => {
        let success = @wasi.native_unlinkat(parent_fd, leaf, flags)
        @wasi.native_close(parent_fd) |> ignore
        [if success { filesystem_ok_void() } else { filesystem_error() }]
      }
    }
  }

  builder.add_func(
    "[method]descriptor.remove-directory-at",
    preview2_func(interface, "[method]descriptor.remove-directory-at"),
    (args, table) => unlink_at(args, table, @wasi.AT_REMOVEDIR),
  )
  builder.add_func(
    "[method]descriptor.unlink-file-at",
    preview2_func(interface, "[method]descriptor.unlink-file-at"),
    (args, table) => unlink_at(args, table, 0),
  )
  builder.add_func(
    "[method]descriptor.rename-at",
    preview2_func(interface, "[method]descriptor.rename-at"),
    (args, table) => {
      let old_state = state_for(args, table, 0)
      let new_state = state_for(args, table, 2)
      if !descriptor_has(old_state, descriptor_mutate_directory) ||
        !descriptor_has(new_state, descriptor_mutate_directory) {
        return [filesystem_error_code(33)]
      }
      let old_path = filesystem_string_arg(args, 1)
      let new_path = filesystem_string_arg(args, 3)
      if capability_parent_and_leaf(old_path) is None ||
        capability_parent_and_leaf(new_path) is None {
        return [filesystem_error_code(31)]
      }
      match
        (
          open_capability_parent(old_state, old_path),
          open_capability_parent(new_state, new_path),
        ) {
        (Some((old_fd, old_leaf)), Some((new_fd, new_leaf))) => {
          let success = @wasi.native_renameat(
            old_fd, old_leaf, new_fd, new_leaf,
          )
          @wasi.native_close(old_fd) |> ignore
          @wasi.native_close(new_fd) |> ignore
          [if success { filesystem_ok_void() } else { filesystem_error() }]
        }
        (Some((old_fd, _)), None) => {
          @wasi.native_close(old_fd) |> ignore
          [filesystem_error()]
        }
        (None, Some((new_fd, _))) => {
          @wasi.native_close(new_fd) |> ignore
          [filesystem_error()]
        }
        _ => [filesystem_error()]
      }
    },
  )
  builder.add_func(
    "[method]descriptor.link-at",
    preview2_func(interface, "[method]descriptor.link-at"),
    (args, table) => {
      let old_state = state_for(args, table, 0)
      let new_state = state_for(args, table, 3)
      if !descriptor_has(new_state, descriptor_mutate_directory) {
        return [filesystem_error_code(33)]
      }
      if (filesystem_flags_arg(args, 1) & 0x01) != 0 {
        return [filesystem_error_code(27)]
      }
      let old_path = filesystem_string_arg(args, 2)
      let new_path = filesystem_string_arg(args, 4)
      if capability_parent_and_leaf(old_path) is None ||
        capability_parent_and_leaf(new_path) is None {
        return [filesystem_error_code(31)]
      }
      match
        (
          open_capability_parent(old_state, old_path),
          open_capability_parent(new_state, new_path),
        ) {
        (Some((old_fd, old_leaf)), Some((new_fd, new_leaf))) => {
          let success = @wasi.native_linkat(
            old_fd, old_leaf, new_fd, new_leaf, 0,
          )
          @wasi.native_close(old_fd) |> ignore
          @wasi.native_close(new_fd) |> ignore
          [if success { filesystem_ok_void() } else { filesystem_error() }]
        }
        (Some((old_fd, _)), None) => {
          @wasi.native_close(old_fd) |> ignore
          [filesystem_error()]
        }
        (None, Some((new_fd, _))) => {
          @wasi.native_close(new_fd) |> ignore
          [filesystem_error()]
        }
        _ => [filesystem_error()]
      }
    },
  )
  builder.add_func(
    "[method]descriptor.symlink-at",
    preview2_func(interface, "[method]descriptor.symlink-at"),
    (args, table) => {
      let state = state_for(args, table, 0)
      let target = filesystem_string_arg(args, 1)
      if !descriptor_has(state, descriptor_mutate_directory) {
        return [filesystem_error_code(33)]
      }
      if target.has_prefix("/") {
        return [filesystem_error_code(31)]
      }
      let path = filesystem_string_arg(args, 2)
      if capability_parent_and_leaf(path) is None {
        return [filesystem_error_code(31)]
      }
      match open_capability_parent(state, path) {
        None => [filesystem_error()]
        Some((parent_fd, leaf)) => {
          let success = @wasi.native_symlinkat(target, parent_fd, leaf)
          @wasi.native_close(parent_fd) |> ignore
          [if success { filesystem_ok_void() } else { filesystem_error() }]
        }
      }
    },
  )
  builder.add_func(
    "[method]descriptor.metadata-hash-at",
    preview2_func(interface, "[method]descriptor.metadata-hash-at"),
    (args, table) => {
      let state = state_for(args, table, 0)
      let follow = (filesystem_flags_arg(args, 1) & 0x01) != 0
      let path = filesystem_string_arg(args, 2)
      if capability_parent_and_leaf(path) is None {
        return [filesystem_error_code(31)]
      }
      match stat_capability_path(state, path, follow) {
        None => [filesystem_error()]
        Some(stat) => {
          let lower = stat.dev ^ stat.ino ^ stat.size
          let upper = stat.mtim ^ stat.ctim ^ stat.nlink
          [
            filesystem_ok(
              Tuple([
                U64(lower.reinterpret_as_int64()),
                U64(upper.reinterpret_as_int64()),
              ]),
            ),
          ]
        }
      }
    },
  )
}

///|
fn add_directory_stream_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@0.2.11/types"
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@0.2.11/types.descriptor",
  )
  let stream_type = host.resolve_resource_type(
    "wasi:filesystem@0.2.11/types.directory-entry-stream",
  )
  builder.add_func(
    "[method]descriptor.read-directory",
    preview2_func(interface, "[method]descriptor.read-directory"),
    (args, table) => {
      let state = descriptor_state(
        host.ctx,
        resource_rep(table, resource_handle_arg(args, 0), descriptor_type),
      )
      if state.file_type != 3 {
        return [filesystem_error_code(24)]
      }
      match @wasi.native_readdir_fd(state.fd) {
        None => [filesystem_error()]
        Some(native_entries) => {
          let entries : Array[DirectoryEntryState] = []
          for entry in native_entries {
            let (name, is_directory) = entry
            entries.push({ name, file_type: if is_directory { 3 } else { 4 } })
          }
          let rep = host.ctx.insert_resource(
            DirectoryEntryStream({ entries, index: Ref(0) }),
          )
          [
            filesystem_ok(
              U32(allocate_resource_handle(host.ctx, table, stream_type, rep)),
            ),
          ]
        }
      }
    },
  )
  builder.add_func(
    "[method]directory-entry-stream.read-directory-entry",
    preview2_func(
      interface, "[method]directory-entry-stream.read-directory-entry",
    ),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), stream_type)
      match host.ctx.get_resource(rep) {
        Some(DirectoryEntryStream(state)) =>
          if state.index.val >= state.entries.length() {
            [filesystem_ok(Variant(0, None))]
          } else {
            let entry = state.entries[state.index.val]
            state.index.val = state.index.val + 1
            [
              filesystem_ok(
                Variant(
                  1,
                  Some(
                    Tuple([
                      Variant(
                        native_file_type_to_component(entry.file_type),
                        None,
                      ),
                      String(entry.name),
                    ]),
                  ),
                ),
              ),
            ]
          }
        _ => raise HostCallError("directory entry stream is not live")
      }
    },
  )
}

///|
fn add_preview2_filesystem_types(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@0.2.11/types"
  let builder = host.linker.host_instance_builder(
    "wasi:filesystem/types@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, interface)
  add_descriptor_stream_methods(host, builder)
  add_descriptor_basic_methods(host, builder)
  add_descriptor_path_methods(host, builder)
  add_directory_stream_methods(host, builder)
  let error_type = host.resource_types.error
  builder.add_func(
    "filesystem-error-code",
    preview2_func(interface, "filesystem-error-code"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), error_type)
      match host.ctx.get_resource(rep) {
        Some(IoError(_, Some(code))) => [Variant(1, Some(Variant(code, None)))]
        Some(IoError(_, None)) => [Variant(0, None)]
        _ => raise HostCallError("I/O error resource is not live")
      }
    },
  )
  host.linker.add_instance(
    "wasi:filesystem/types@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn add_preview2_preopens(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:filesystem@0.2.11/preopens"
  let builder = host.linker.host_instance_builder(
    "wasi:filesystem/preopens@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, interface)
  let descriptor_type = host.resolve_resource_type(
    "wasi:filesystem@0.2.11/types.descriptor",
  )
  builder.add_func(
    "get-directories",
    preview2_func(interface, "get-directories"),
    (_args, table) => {
      let values : Array[@runtime_impl.ComponentValue] = []
      for preopen in host.ctx.preopens {
        if preopen.closed.val {
          raise HostCallError("preopen '\{preopen.guest_path}' is closed")
        }
        match @wasi.native_dup(preopen.fd) {
          None =>
            raise HostCallError(
              "cannot duplicate preopen '\{preopen.guest_path}'",
            )
          Some(fd) => {
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
        }
      }
      [List(values)]
    },
  )
  host.linker.add_instance(
    "wasi:filesystem/preopens@\{preview2_version}",
    builder.finish(),
  )
}

///|
pub fn WasiComponentHost::add_preview2_filesystem(
  self : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_preview2_filesystem_types(self)
  add_preview2_preopens(self)
}
