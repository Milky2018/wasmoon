///|
/// WASI module registration
/// Registers all WASI functions with a Linker

///|
/// Helper to create FuncType from param and result types
fn make_func_type(
  params : Array[@types.ValueType],
  results : Array[@types.ValueType],
) -> @types.FuncType {
  { params, results }
}

///|
/// Register all WASI snapshot preview1 functions with a linker
pub fn register_wasi(linker : @runtime.Linker, ctx : WasiContext) -> Unit {
  let store = linker.get_store()
  // We need to get memory from the module being instantiated
  // For now, we'll create wrapper functions that access memory through the store
  // The wrappers will be called with proper arguments

  // Common types
  let i32 = @types.ValueType::I32
  let i64 = @types.ValueType::I64

  // fd_write(fd, iovs, iovs_len, nwritten) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_write",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let iovs = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let iovs_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let nwritten = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      // Get memory from store (memory 0)
      let mem = store.get_memory(0)
      let result = fd_write(ctx, mem, fd, iovs, iovs_len, nwritten)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32], [i32]),
  )

  // fd_read(fd, iovs, iovs_len, nread) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_read",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let iovs = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let iovs_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let nread = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_read(ctx, mem, fd, iovs, iovs_len, nread)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32], [i32]),
  )

  // args_sizes_get(argc, argv_buf_size) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "args_sizes_get",
    fn(args) {
      let argc_ptr = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let argv_buf_size_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = args_sizes_get(ctx, mem, argc_ptr, argv_buf_size_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // args_get(argv, argv_buf) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "args_get",
    fn(args) {
      let argv_ptr = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let argv_buf_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = args_get(ctx, mem, argv_ptr, argv_buf_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // environ_sizes_get(environc, environ_buf_size) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "environ_sizes_get",
    fn(args) {
      let environc_ptr = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let environ_buf_size_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = environ_sizes_get(
        ctx, mem, environc_ptr, environ_buf_size_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // environ_get(environ, environ_buf) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "environ_get",
    fn(args) {
      let environ_ptr = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let environ_buf_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = environ_get(ctx, mem, environ_ptr, environ_buf_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // proc_exit(exit_code) -> !
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "proc_exit",
    fn(args) {
      let exit_code = match args[0] {
        I32(v) => v
        _ => 1
      }
      // This will raise WasiExit
      proc_exit(ctx, exit_code) catch {
        _ => ()
      }
      // This line is never reached in normal execution
      []
    },
    func_type=make_func_type([i32], []),
  )

  // clock_time_get(clock_id, precision, time) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "clock_time_get",
    fn(args) {
      let clock_id = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let precision = match args[1] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let time_ptr = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = clock_time_get(mem, clock_id, precision, time_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i64, i32], [i32]),
  )

  // fd_prestat_get(fd, prestat) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_prestat_get",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let prestat_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_prestat_get(ctx, mem, fd, prestat_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // fd_prestat_dir_name(fd, path, path_len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_prestat_dir_name",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let path_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let path_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_prestat_dir_name(ctx, mem, fd, path_ptr, path_len)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32], [i32]),
  )

  // fd_close(fd) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_close",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_close(ctx, fd)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32], [i32]),
  )

  // random_get(buf, buf_len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "random_get",
    fn(args) {
      let buf_ptr = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let buf_len = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = random_get(mem, buf_ptr, buf_len)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // fd_seek(fd, offset, whence, newoffset) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_seek",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let offset = match args[1] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let whence = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let newoffset_ptr = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_seek(ctx, mem, fd, offset, whence, newoffset_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i64, i32, i32], [i32]),
  )

  // fd_tell(fd, offset) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_tell",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let offset_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_tell(ctx, mem, fd, offset_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // fd_pread(fd, iovs, iovs_len, offset, nread) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_pread",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let iovs = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let iovs_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let offset = match args[3] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let nread_ptr = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_pread(ctx, mem, fd, iovs, iovs_len, offset, nread_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i64, i32], [i32]),
  )

  // fd_pwrite(fd, iovs, iovs_len, offset, nwritten) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_pwrite",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let iovs = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let iovs_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let offset = match args[3] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let nwritten_ptr = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_pwrite(ctx, mem, fd, iovs, iovs_len, offset, nwritten_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i64, i32], [i32]),
  )

  // path_open(fd, dirflags, path, path_len, oflags, fs_rights_base, fs_rights_inheriting, fdflags, opened_fd) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_open",
    fn(args) {
      let dir_fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let dirflags = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let path_ptr = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let path_len = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let oflags = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let fs_rights_base = match args[5] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let fs_rights_inheriting = match args[6] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let fdflags = match args[7] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let opened_fd_ptr = match args[8] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = path_open(
        ctx, mem, dir_fd, dirflags, path_ptr, path_len, oflags, fs_rights_base, fs_rights_inheriting,
        fdflags, opened_fd_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i32, i64, i64, i32, i32], [
      i32,
    ]),
  )

  // fd_fdstat_get(fd, fdstat) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_fdstat_get",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let fdstat_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_fdstat_get(ctx, mem, fd, fdstat_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // clock_res_get(clock_id, resolution) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "clock_res_get",
    fn(args) {
      let clock_id = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let resolution_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = clock_res_get(mem, clock_id, resolution_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // sched_yield() -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "sched_yield",
    fn(_args) {
      let result = sched_yield()
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([], [i32]),
  )

  // path_create_directory(fd, path, path_len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_create_directory",
    fn(args) {
      let dir_fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let path_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let path_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = path_create_directory(ctx, mem, dir_fd, path_ptr, path_len)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32], [i32]),
  )

  // fd_readdir(fd, buf, buf_len, cookie, bufused) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_readdir",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let buf_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let buf_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let cookie = match args[3] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let bufused_ptr = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_memory(0)
      let result = fd_readdir(
        ctx, mem, fd, buf_ptr, buf_len, cookie, bufused_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i64, i32], [i32]),
  )

  // Stub functions that return ENOSYS (not implemented)
  // Each tuple: (name, param_types)
  let stub_funcs : Array[(String, Array[@types.ValueType])] = [
    ("fd_advise", [i32, i64, i64, i32]), // fd, offset, len, advice
    ("fd_allocate", [i32, i64, i64]), // fd, offset, len
    ("fd_datasync", [i32]), // fd
    ("fd_fdstat_set_flags", [i32, i32]), // fd, flags
    ("fd_fdstat_set_rights", [i32, i64, i64]), // fd, fs_rights_base, fs_rights_inheriting
    ("fd_filestat_get", [i32, i32]), // fd, buf
    ("fd_filestat_set_size", [i32, i64]), // fd, size
    ("fd_filestat_set_times", [i32, i64, i64, i32]), // fd, atim, mtim, fst_flags
    ("fd_renumber", [i32, i32]), // fd, to
    ("fd_sync", [i32]), // fd
    ("path_filestat_get", [i32, i32, i32, i32, i32]), // fd, flags, path, path_len, buf
    ("path_filestat_set_times", [i32, i32, i32, i32, i64, i64, i32]), // fd, flags, path, path_len, atim, mtim, fst_flags
    ("path_link", [i32, i32, i32, i32, i32, i32, i32]), // old_fd, old_flags, old_path, old_path_len, new_fd, new_path, new_path_len
    ("path_readlink", [i32, i32, i32, i32, i32, i32]), // fd, path, path_len, buf, buf_len, bufused
    ("path_remove_directory", [i32, i32, i32]), // fd, path, path_len
    ("path_rename", [i32, i32, i32, i32, i32, i32]), // fd, old_path, old_path_len, new_fd, new_path, new_path_len
    ("path_symlink", [i32, i32, i32, i32, i32]), // old_path, old_path_len, fd, new_path, new_path_len
    ("path_unlink_file", [i32, i32, i32]), // fd, path, path_len
    ("poll_oneoff", [i32, i32, i32, i32]), // in, out, nsubscriptions, nevents
    ("sock_accept", [i32, i32, i32]), // fd, flags, result_fd
    ("sock_recv", [i32, i32, i32, i32, i32, i32]), // fd, ri_data, ri_data_len, ri_flags, ro_datalen, ro_flags
    ("sock_send", [i32, i32, i32, i32, i32]), // fd, si_data, si_data_len, si_flags, so_datalen
    ("sock_shutdown", [i32, i32]), // fd, how
  ]
  for stub in stub_funcs {
    let (name, params) = stub
    linker.add_host_func(
      "wasi_snapshot_preview1",
      name,
      fn(_args) { [@types.Value::I32(Errno::NoSys.to_i32())] },
      func_type=make_func_type(params, [i32]),
    )
  }
}
