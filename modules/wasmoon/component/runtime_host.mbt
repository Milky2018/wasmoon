///|
priv struct ComponentHostInstallerState {
  claim : () -> Unit raise ComponentRuntimeError
  install : (@runtime_impl.ComponentLinker) -> Unit raise @runtime_impl.ComponentRuntimeError
  close : () -> Unit
  consumed : Ref[Bool]
  closed : Ref[Bool]
}

///|
struct ComponentHostInstaller {
  state : ComponentHostInstallerState
}

///|
fn ComponentHostInstaller::from_linker_installer(
  install : (@runtime_impl.ComponentLinker) -> Unit raise @runtime_impl.ComponentRuntimeError,
  claim? : () -> Unit raise ComponentRuntimeError = fn() { () },
  close? : () -> Unit = fn() { () },
) -> ComponentHostInstaller {
  {
    state: { claim, install, close, consumed: Ref(false), closed: Ref(false), },
  }
}

///|
fn ComponentHostInstaller::claim(
  self : ComponentHostInstaller,
) -> Unit raise ComponentRuntimeError {
  if self.state.consumed.val {
    raise HostInstallerAlreadyConsumed
  }
  (self.state.claim)()
  self.state.consumed.val = true
}

///|
fn ComponentHostInstaller::populate(
  self : ComponentHostInstaller,
  linker : @runtime_impl.ComponentLinker,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  (self.state.install)(linker)
}

///|
fn ComponentHostInstaller::close(self : ComponentHostInstaller) -> Unit {
  if !self.state.consumed.val || self.state.closed.val {
    return
  }
  self.state.closed.val = true
  (self.state.close)()
}

///|
pub fn wasi_command_component_host(
  ctx : @wasi_component.WasiComponentCtx,
) -> ComponentHostInstaller {
  let runtime_owner : Ref[@wasi_component.WasiComponentCtxRuntimeOwner?] = Ref(
    None,
  )
  ComponentHostInstaller::from_linker_installer(
    fn(linker) raise @runtime_impl.ComponentRuntimeError {
      @wasi_component.install_command_world(linker, ctx)
    },
    claim=fn() raise ComponentRuntimeError {
      match ctx.try_claim_runtime_owner() {
        Some(owner) => runtime_owner.val = Some(owner)
        None => raise HostContextAlreadyOwned
      }
    },
    close=fn() {
      match runtime_owner.val {
        Some(owner) => {
          runtime_owner.val = None
          owner.close()
        }
        None => ()
      }
    },
  )
}
