///|
pub fn wasi_command_component_host(
  ctx : WasiComponentCtx,
) -> @component_host.ComponentHostInstaller {
  @component_host.ComponentHostInstaller::from_linker_installer(
    fn(linker) raise @runtime_impl.ComponentRuntimeError {
      let host = WasiComponentHost(linker, ctx)
      host.add_preview2_cli_clocks_random()
      host.add_preview2_io()
      host.add_preview2_filesystem()
      host.add_preview2_sockets()
      host.add_preview3_cli_clocks_random()
      host.add_preview3_filesystem()
      host.add_preview3_sockets()
    },
    close=() => ctx.close(),
  )
}
