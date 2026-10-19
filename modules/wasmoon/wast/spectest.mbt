///|
pub fn create_spectest_module(
  store : @runtime.Store,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  @spectest.create_spectest_module(store, print_char=c => @wasi.putchar(c))
}
