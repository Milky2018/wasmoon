# WASI Preview1 Parity Tracker (vs wasmtime `crates/wasi/src/p1.rs`)

Legend: `[x] done`, `[~] in progress`, `[ ] pending`

## Eventing / Poll

- [x] `poll_oneoff`
  - absolute deadline honors `clock_id` (realtime vs monotonic)
  - clock events are not dropped when fds are ready
  - emits events in subscription order
  - `nsubscriptions == 0 -> Inval`
  - rejects invalid `clock_id` / invalid tag / invalid fd
  - sets `fd_read` hangup flag on EOF for regular files
  - fd/clock event `nbytes` aligned (`1` / `0`)

## File Descriptor Ops

- [ ] `fd_read`
- [ ] `fd_pread`
- [ ] `fd_write`
- [ ] `fd_pwrite`
- [ ] `fd_seek`
- [ ] `fd_tell`
- [ ] `fd_close`
- [ ] `fd_sync`
- [ ] `fd_datasync`
- [ ] `fd_fdstat_get`
- [ ] `fd_fdstat_set_flags`
- [ ] `fd_fdstat_set_rights`
- [ ] `fd_filestat_get`
- [ ] `fd_filestat_set_size`
- [ ] `fd_filestat_set_times`
- [ ] `fd_advise`
- [ ] `fd_allocate`
- [ ] `fd_readdir`
- [ ] `fd_renumber`

## Path Ops

- [ ] `path_open`
- [ ] `path_create_directory`
- [ ] `path_filestat_get`
- [ ] `path_filestat_set_times`
- [ ] `path_link`
- [ ] `path_readlink`
- [ ] `path_remove_directory`
- [ ] `path_rename`
- [ ] `path_symlink`
- [ ] `path_unlink_file`

## Process / Clock / Misc

- [ ] `proc_exit`
- [ ] `proc_raise`
- [ ] `sched_yield`
- [ ] `clock_time_get`
- [ ] `clock_res_get`
- [ ] `random_get`
- [ ] `args_get` / `args_sizes_get`
- [ ] `environ_get` / `environ_sizes_get`
- [ ] `fd_prestat_get` / `fd_prestat_dir_name`

## Socket

- [ ] `sock_recv`
- [ ] `sock_send`
- [ ] `sock_shutdown`
- [ ] `sock_accept`

