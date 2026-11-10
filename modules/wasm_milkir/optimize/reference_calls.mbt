///|
/// A unique small scalar implementation can be guarded by function identity.
/// The checked comparison still resolves the original executable target. Misses
/// retain call_ref, and every entry poll in a candidate prevents admission.
fn inline_guarded_reference_calls(
  function : @milkir.Function,
  callees : Map[Int32, @milkir.Function],
  context : @wasm_milkir.WasmValidationContext,
) -> Bool raise @milkir.VerifyError {
  if callees.is_empty() ||
    function.params.is_empty() ||
    function.params[0].1 != I64 {
    return false
  }
  let candidates : Map[Int32, Int32] = Map([])
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      guard @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        )
        is Some(CallRef(type_index)) &&
        !candidates.contains(type_index) &&
        candidates.length() < 4 else {
        continue
      }
      let mut selected = -1
      for index, callee in callees {
        if !context.function_has_type_index(index, type_index) ||
          !context.admits_function_body(index, callee) {
          continue
        }
        callee.verify()
        guard leaf_cost(callee) is Some((_, false)) &&
          callee.blocks[0]
          .instruction_ids()
          .all(id => callee.instruction_by_id(id).unwrap().opcode is Scalar(_)) else {
          continue
        }
        @wasm_milkir.verify_function_with_context(callee, context)
        if selected >= 0 {
          selected = -1
          break
        }
        selected = index
      }
      candidates[type_index] = selected
    }
  }
  if !candidates.values().any(index => index >= 0) {
    return false
  }
  let entry = function.blocks[0]
  if !@milkir.CFG::build(function).get_predecessors(entry.id).is_empty() {
    return false
  }
  let expected : Map[Int32, @milkir.Value] = Map([])
  let queries : Array[@milkir.Inst] = []
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        )
        is Some(CallRef(type_index)) &&
        candidates.get(type_index) is Some(index) &&
        index >= 0 &&
        !expected.contains(index) {
        let value = function.new_value(CallableRef)
        queries.push(
          function.new_inst(
            Ext(
              @wasm_milkir.encode(GetFuncRef(index)),
              Signature([], [CallableRef]),
            ),
            [],
            [value],
          ),
        )
        expected[index] = value
      }
    }
  }
  let mut inserted_queries = false
  let mut expanded = 0
  for block in function.blocks.copy() {
    let ids = function.block_instruction_ids(block).to_owned()
    let term = block.terminator.unwrap()
    let metadata = block.terminator_metadata()
    block.clear_instructions_for_move()
    let mut current = block
    for id in ids {
      let call = function.instruction_by_id(id).unwrap()
      guard expanded < 4 &&
        @wasm_milkir.decode_opcode(call.opcode) is Some(CallRef(type_index)) &&
        candidates.get(type_index) is Some(index) &&
        index >= 0 &&
        call.results is [result] else {
        current.append_inst(call)
        continue
      }
      if block.id == entry.id && !inserted_queries {
        for query in queries {
          current.append_inst(query)
        }
        inserted_queries = true
      }
      let fast = function.new_block0()
      let slow = function.new_block0()
      let join = function.new_block0()
      let joined = function.append_block_param(join, result.ty)
      let condition = function.new_value(I32)
      let guard_ = function.new_inst(
        Ext(
          @wasm_milkir.encode(ExecutableFuncRefEq),
          Signature([CallableRef, CallableRef], [I32]),
        ),
        [call.args[0], expected[index]],
        [condition],
      )
      let fast_result = function.new_value(result.ty)
      let args = call.args[1:].to_owned()
      let direct = function.new_inst(
        Ext(
          @wasm_milkir.encode(WasmCall(index)),
          Signature(args.map(value => value.ty), [result.ty]),
        ),
        args,
        [fast_result],
      )
      let slow_result = function.new_value(result.ty)
      let indirect = function.new_inst(call.opcode, call.args.copy(), [
        slow_result,
      ])
      for item in call.metadata {
        guard_.add_metadata(item)
        direct.add_metadata(item)
        indirect.add_metadata(item)
      }
      current.append_inst(guard_)
      current.set_terminator(
        Branch(condition, fast.id, [], slow.id, []),
        metadata=call.metadata.copy(),
      )
      fast.append_inst(direct)
      fast.set_terminator(Jump(join.id, [fast_result]))
      slow.append_inst(indirect)
      slow.set_terminator(Jump(join.id, [slow_result]))
      call.set_opcode(Scalar(Copy))
      call.operands.clear()
      call.operands.push(joined)
      join.append_inst(call)
      current = join
      expanded += 1
    }
    if block.id == entry.id && !inserted_queries {
      for query in queries {
        current.append_inst(query)
      }
      inserted_queries = true
    }
    current.set_terminator(term, metadata~)
  }
  expanded > 0
}
