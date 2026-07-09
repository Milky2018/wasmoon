///|
/// Complete ABI contract supplied by an embedding runtime.
///
/// MachV treats this as data: the embedding owns the concrete runtime layout
/// and calling convention policy, while reusable lowering, allocation, and
/// emission consume this contract without interpreting product-specific names.
pub(all) struct EmbeddingABI {
  ///
  /// Calling-convention layout for generated code and calls made by it.
  call_conv : CallConventionLayout
  ///
  /// Optional embedding-owned physical register roles.
  reg_roles : EmbeddingRegRoles
  ///
  /// Optional embedding-context memory layout.
  context_layout : EmbeddingContextLayout?
  ///
  /// Whether `reg_roles.context` is reserved globally from register allocation.
  reserve_context_role : Bool
}

///|
pub fn EmbeddingABI::new(
  call_conv : CallConventionLayout,
  reg_roles? : EmbeddingRegRoles = EmbeddingRegRoles::none(),
  context_layout? : EmbeddingContextLayout? = None,
  reserve_context_role? : Bool = true,
) -> EmbeddingABI {
  { call_conv, reg_roles, context_layout, reserve_context_role }
}

///|
pub fn EmbeddingABI::reserved_int_indices(
  self : EmbeddingABI,
  reserve_context_cache_0? : Bool = false,
  reserve_context_cache_1? : Bool = false,
  reserve_extra_results_ptr? : Bool = false,
) -> Array[Int] {
  self.reg_roles.reserved_int_indices(
    reserve_context=self.reserve_context_role,
    reserve_context_cache_0~,
    reserve_context_cache_1~,
    reserve_extra_results_ptr~,
  )
}
