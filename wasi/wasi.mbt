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
      // Get memory from store (using WASI memory address)
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
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
      let mem = store.get_wasi_memory()
      let result = fd_readdir(
        ctx, mem, fd, buf_ptr, buf_len, cookie, bufused_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i64, i32], [i32]),
  )

  // ============================================================================
  // Phase 1: Core file operations
  // ============================================================================

  // fd_sync(fd) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_sync",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_sync_impl(ctx, fd)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32], [i32]),
  )

  // fd_datasync(fd) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_datasync",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_datasync_impl(ctx, fd)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32], [i32]),
  )

  // path_unlink_file(fd, path, path_len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_unlink_file",
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
      let mem = store.get_wasi_memory()
      let result = path_unlink_file_impl(ctx, mem, fd, path_ptr, path_len)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32], [i32]),
  )

  // path_remove_directory(fd, path, path_len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_remove_directory",
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
      let mem = store.get_wasi_memory()
      let result = path_remove_directory_impl(ctx, mem, fd, path_ptr, path_len)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32], [i32]),
  )

  // path_rename(fd, old_path, old_path_len, new_fd, new_path, new_path_len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_rename",
    fn(args) {
      let old_fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let old_path_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let old_path_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let new_fd = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let new_path_ptr = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let new_path_len = match args[5] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = path_rename_impl(
        ctx, mem, old_fd, old_path_ptr, old_path_len, new_fd, new_path_ptr, new_path_len,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i32, i32], [i32]),
  )

  // ============================================================================
  // Phase 2: File metadata operations
  // ============================================================================

  // fd_filestat_get(fd, buf) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_filestat_get",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let buf_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = fd_filestat_get_impl(ctx, mem, fd, buf_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // path_filestat_get(fd, flags, path, path_len, buf) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_filestat_get",
    fn(args) {
      let dir_fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let flags = match args[1] {
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
      let buf_ptr = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = path_filestat_get_impl(
        ctx, mem, dir_fd, flags, path_ptr, path_len, buf_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i32], [i32]),
  )

  // fd_filestat_set_size(fd, size) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_filestat_set_size",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let size = match args[1] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_filestat_set_size_impl(ctx, fd, size)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i64], [i32]),
  )

  // fd_filestat_set_times(fd, atim, mtim, fst_flags) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_filestat_set_times",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let atim = match args[1] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mtim = match args[2] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let fst_flags = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_filestat_set_times_impl(ctx, fd, atim, mtim, fst_flags)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i64, i64, i32], [i32]),
  )

  // path_filestat_set_times(fd, flags, path, path_len, atim, mtim, fst_flags) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_filestat_set_times",
    fn(args) {
      let dir_fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let flags = match args[1] {
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
      let atim = match args[4] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mtim = match args[5] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let fst_flags = match args[6] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = path_filestat_set_times_impl(
        ctx, mem, dir_fd, flags, path_ptr, path_len, atim, mtim, fst_flags,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i64, i64, i32], [i32]),
  )

  // ============================================================================
  // Phase 3: Auxiliary functions
  // ============================================================================

  // fd_advise(fd, offset, len, advice) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_advise",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let offset = match args[1] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let len = match args[2] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let advice = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_advise_impl(ctx, fd, offset, len, advice)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i64, i64, i32], [i32]),
  )

  // fd_allocate(fd, offset, len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_allocate",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let offset = match args[1] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let len = match args[2] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_allocate_impl(ctx, fd, offset, len)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i64, i64], [i32]),
  )

  // fd_fdstat_set_flags(fd, flags) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_fdstat_set_flags",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let flags = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_fdstat_set_flags_impl(ctx, fd, flags)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // fd_fdstat_set_rights(fd, fs_rights_base, fs_rights_inheriting) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_fdstat_set_rights",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let fs_rights_base = match args[1] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let fs_rights_inheriting = match args[2] {
        I64(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_fdstat_set_rights_impl(
        ctx, fd, fs_rights_base, fs_rights_inheriting,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i64, i64], [i32]),
  )

  // fd_renumber(from, to) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "fd_renumber",
    fn(args) {
      let from = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let to = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = fd_renumber_impl(ctx, from, to)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // ============================================================================
  // Phase 4: Symlink operations
  // ============================================================================

  // path_symlink(old_path, old_path_len, fd, new_path, new_path_len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_symlink",
    fn(args) {
      let old_path_ptr = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let old_path_len = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let dir_fd = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let new_path_ptr = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let new_path_len = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = path_symlink_impl(
        ctx, mem, old_path_ptr, old_path_len, dir_fd, new_path_ptr, new_path_len,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i32], [i32]),
  )

  // path_readlink(fd, path, path_len, buf, buf_len, bufused) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_readlink",
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
      let buf_ptr = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let buf_len = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let bufused_ptr = match args[5] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = path_readlink_impl(
        ctx, mem, dir_fd, path_ptr, path_len, buf_ptr, buf_len, bufused_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i32, i32], [i32]),
  )

  // path_link(old_fd, old_flags, old_path, old_path_len, new_fd, new_path, new_path_len) -> errno
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "path_link",
    fn(args) {
      let old_fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let old_flags = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let old_path_ptr = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let old_path_len = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let new_fd = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let new_path_ptr = match args[5] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let new_path_len = match args[6] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = path_link_impl(
        ctx, mem, old_fd, old_flags, old_path_ptr, old_path_len, new_fd, new_path_ptr,
        new_path_len,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i32, i32, i32], [i32]),
  )

  // ============================================================================
  // Phase 5: poll and socket
  // ============================================================================

  // poll_oneoff
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "poll_oneoff",
    fn(args) {
      let in_ptr = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let out_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let nsubscriptions = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let nevents_ptr = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = poll_oneoff_impl(
        ctx, mem, in_ptr, out_ptr, nsubscriptions, nevents_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32], [i32]),
  )

  // sock_recv
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "sock_recv",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let ri_data_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let ri_data_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let ri_flags = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let ro_datalen_ptr = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let ro_flags_ptr = match args[5] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = sock_recv_impl(
        ctx, mem, fd, ri_data_ptr, ri_data_len, ri_flags, ro_datalen_ptr, ro_flags_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i32, i32], [i32]),
  )

  // sock_send
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "sock_send",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let si_data_ptr = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let si_data_len = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let si_flags = match args[3] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let so_datalen_ptr = match args[4] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = sock_send_impl(
        ctx, mem, fd, si_data_ptr, si_data_len, si_flags, so_datalen_ptr,
      )
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32, i32, i32], [i32]),
  )

  // sock_shutdown
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "sock_shutdown",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let how = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = sock_shutdown_impl(ctx, fd, how)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32], [i32]),
  )

  // proc_raise
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "proc_raise",
    fn(args) {
      let signal = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result = proc_raise_impl(signal)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32], [i32]),
  )

  // sock_accept
  linker.add_host_func(
    "wasi_snapshot_preview1",
    "sock_accept",
    fn(args) {
      let fd = match args[0] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let flags = match args[1] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let result_fd_ptr = match args[2] {
        I32(v) => v
        _ => return [@types.Value::I32(Errno::Inval.to_i32())]
      }
      let mem = store.get_wasi_memory()
      let result = sock_accept_impl(ctx, mem, fd, flags, result_fd_ptr)
      [@types.Value::I32(result)]
    },
    func_type=make_func_type([i32, i32, i32], [i32]),
  )
}
