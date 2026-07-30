///|
struct ComponentHostInstaller {
  install : (@runtime_impl.ComponentLinker) -> Unit raise @runtime_impl.ComponentRuntimeError
  close : () -> Unit
}

///|
pub fn ComponentHostInstaller::from_linker_installer(
  install : (@runtime_impl.ComponentLinker) -> Unit raise @runtime_impl.ComponentRuntimeError,
  close? : () -> Unit = () => (),
) -> ComponentHostInstaller {
  { install, close }
}

///|
pub fn ComponentHostInstaller::install(
  self : ComponentHostInstaller,
  linker : @runtime_impl.ComponentLinker,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  (self.install)(linker)
}

///|
pub fn ComponentHostInstaller::close(self : ComponentHostInstaller) -> Unit {
  (self.close)()
}
