///|
fn capability_parent_and_leaf(path : String) -> (String, String)? {
  if path == "" || path.has_prefix("/") {
    return None
  }
  let requires_directory = path.has_suffix("/")
  let parts : Array[String] = []
  for part in path.split("/") {
    if part == "" {
      continue
    }
    parts.push(part.to_owned())
  }
  if parts.length() == 0 {
    return None
  }
  let leaf = parts.pop().unwrap()
  let leaf = if requires_directory { leaf + "/" } else { leaf }
  Some((parts.join("/"), leaf))
}

///|
fn descriptor_open_flags(
  requested_flags : Int32,
  flags : Int32,
) -> Array[@wasi.OpenFlags] {
  let access : @wasi.OpenFlags = if (requested_flags & descriptor_write) == 0 {
    ReadOnly
  } else if (requested_flags & descriptor_read) == 0 {
    WriteOnly
  } else {
    ReadWrite
  }
  let native_flags = [access]
  if (flags & 0x01) != 0 {
    native_flags.push(Create)
  }
  if (flags & 0x02) != 0 {
    native_flags.push(Directory)
  }
  if (flags & 0x04) != 0 {
    native_flags.push(Exclusive)
  }
  if (flags & 0x08) != 0 {
    native_flags.push(Truncate)
  }
  native_flags
}

///|
fn open_capability_parent(
  state : DescriptorState,
  path : String,
) -> (Int32, String)? {
  match capability_parent_and_leaf(path) {
    None => None
    Some((parent, leaf)) =>
      if leaf == "." || leaf == ".." || leaf == "./" || leaf == "../" {
        match @wasi.native_open_parent_beneath(state.fd, path) {
          Some(fd) => Some((fd, "."))
          None => None
        }
      } else {
        match @wasi.native_open_parent_beneath(state.fd, parent) {
          Some(parent_fd) => Some((parent_fd, leaf))
          None => None
        }
      }
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
      if leaf == "." || leaf == ".." || leaf == "./" || leaf == "../" {
        match @wasi.native_open_parent_beneath(state.fd, path) {
          None => None
          Some(fd) => {
            let stat = @wasi.native_fstat(fd)
            @wasi.native_close(fd) |> ignore
            stat
          }
        }
      } else if follow_final || path.has_suffix("/") {
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
fn[T] with_capability_parent(
  state : DescriptorState,
  path : String,
  operation : (Int32, String) -> T,
) -> T? {
  guard open_capability_parent(state, path) is Some((fd, leaf)) else {
    return None
  }
  let result = operation(fd, leaf)
  @wasi.native_close(fd) |> ignore
  Some(result)
}

///|
fn set_capability_path_times(
  state : DescriptorState,
  path : String,
  follow : Bool,
  atim : Int64,
  mtim : Int64,
  flags : Int32,
) -> Bool {
  if follow {
    guard capability_parent_and_leaf(path) is Some((parent, leaf)) &&
      @wasi.native_openat_beneath(state.fd, parent, leaf, [ReadOnly], 0, true)
      is Some(fd) else {
      return false
    }
    let result = @wasi.native_futimens(fd, atim, mtim, flags)
    @wasi.native_close(fd) |> ignore
    result
  } else {
    with_capability_parent(state, path, (fd, leaf) => {
      @wasi.native_utimensat(
        fd,
        leaf,
        atim,
        mtim,
        flags,
        @wasi.AT_SYMLINK_NOFOLLOW,
      )
    }).unwrap_or(false)
  }
}

///|
priv enum CapabilityPairOperation {
  Link
  Rename
}

///|
fn operate_on_capability_pair(
  source : DescriptorState,
  source_path : String,
  destination : DescriptorState,
  destination_path : String,
  operation : CapabilityPairOperation,
) -> Bool {
  let old_parent = open_capability_parent(source, source_path)
  let new_parent = open_capability_parent(destination, destination_path)
  let success = match (old_parent, new_parent) {
    (Some((old_fd, old_leaf)), Some((new_fd, new_leaf))) =>
      match operation {
        Link => @wasi.native_linkat(old_fd, old_leaf, new_fd, new_leaf, 0)
        Rename => @wasi.native_renameat(old_fd, old_leaf, new_fd, new_leaf)
      }
    _ => false
  }
  if old_parent is Some((old_fd, _)) {
    @wasi.native_close(old_fd) |> ignore
  }
  if new_parent is Some((new_fd, _)) {
    @wasi.native_close(new_fd) |> ignore
  }
  success
}

///|
fn metadata_hash_value(stat : @wasi.FileStat) -> @runtime_impl.ComponentValue {
  Tuple([
    U64((stat.dev ^ stat.ino ^ stat.size).reinterpret_as_int64()),
    U64((stat.mtim ^ stat.ctim ^ stat.nlink).reinterpret_as_int64()),
  ])
}
