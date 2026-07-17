///|
test "allocation verifier accepts the pinned embedding context parameter" {
  let builder = @machv.FunctionBuilder::FunctionBuilder("pinned_context")
  let context = builder.add_param(Int)
  builder.add_result(I64)
  builder.append(CallExternal(ExternalName("host.observe"), 0, [], Foreign))
  |> ignore
  builder.terminate(Return([Virtual(context)]))
  let function = builder.finish()
  let liveness = compute_liveness(function)
  let pinned : @abi.PReg = { index: 21, class: Int }
  let allocation : RegAllocResult = {
    assignments: Map([(context.id, pinned)]),
    spill_slots: Map([]),
    num_spill_slots: 0,
    inst_edits: [],
  }
  let call_conv : @abi.CallConventionLayout = {
    context_arg: { index: 0, class: Int },
    user_arg_gprs: [],
    arg_fprs: [],
    ret_gprs: [{ index: 0, class: Int }],
    ret_fprs: [],
  }
  let embedding_abi = @abi.EmbeddingABI(call_conv, reg_roles={
    context: Some(pinned),
    context_cache_0: None,
    context_cache_1: None,
    extra_results_ptr: None,
  })
  verify_allocation(function, liveness, allocation, AArch64, embedding_abi)
  inspect(allocation.assignments.get(context.id).unwrap(), content="x21")
}
