///|
/// Install the complete Preview 2 and Preview 3 WASI command world.
pub fn install_command_world(
  linker : @runtime_impl.ComponentLinker,
  ctx : WasiComponentCtx,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let host = WasiComponentHost(linker, ctx)
  host.add_preview2_cli_clocks_random()
  host.add_preview2_io()
  host.add_preview2_filesystem()
  host.add_preview2_sockets()
  host.add_preview3_cli_clocks_random()
  host.add_preview3_filesystem()
  host.add_preview3_sockets()
}
