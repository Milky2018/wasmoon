///|
/// Wasmoon JIT embedding register roles for a target ISA.
///
/// These numbers preserve the historical Wasmoon ABI. They are owned here so
/// reusable MachV ISA policy does not decide VMContext or cached-pointer roles.
pub fn wasm_embedding_reg_roles_for_isa(
  isa : @isa.ISA,
) -> @abi.EmbeddingRegRoles {
  match isa {
    AArch64 =>
      {
        context: Some({ index: 21, class: Int }),
        context_cache_0: Some({ index: 20, class: Int }),
        context_cache_1: Some({ index: 19, class: Int }),
        extra_results_ptr: Some({ index: 23, class: Int }),
      }
    AMD64 =>
      {
        context: Some({ index: 15, class: Int }),
        context_cache_0: Some({ index: 14, class: Int }),
        context_cache_1: Some({ index: 13, class: Int }),
        extra_results_ptr: Some({ index: 12, class: Int }),
      }
  }
}

///|
pub fn wasm_embedding_reg_roles(
  isa? : @isa.ISA = AArch64,
) -> @abi.EmbeddingRegRoles {
  wasm_embedding_reg_roles_for_isa(isa)
}
