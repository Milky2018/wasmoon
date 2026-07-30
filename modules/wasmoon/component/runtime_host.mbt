///|
struct ComponentHostInstaller {
  install : (@runtime_impl.ComponentLinker) -> Unit raise @runtime_impl.ComponentRuntimeError
  close : () -> Unit
}

///|
fn ComponentHostInstaller::from_linker_installer(
  install : (@runtime_impl.ComponentLinker) -> Unit raise @runtime_impl.ComponentRuntimeError,
  close? : () -> Unit = fn() { () },
) -> ComponentHostInstaller {
  { install, close }
}

///|
fn ComponentHostInstaller::install(
  self : ComponentHostInstaller,
  linker : @runtime_impl.ComponentLinker,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  (self.install)(linker)
}

///|
fn ComponentHostInstaller::close(self : ComponentHostInstaller) -> Unit {
  (self.close)()
}

///|
pub fn wasi_command_component_host(
  ctx : @wasi_component.WasiComponentCtx,
) -> ComponentHostInstaller {
  ComponentHostInstaller::from_linker_installer(
    fn(linker) raise @runtime_impl.ComponentRuntimeError {
      @wasi_component.install_command_world(linker, ctx)
    },
    close=fn() { ctx.close() },
  )
}
