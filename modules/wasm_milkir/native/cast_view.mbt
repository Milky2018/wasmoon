///|
/// Plan on the final, borrow-verified instruction order. A view can be passed
/// only to the very next instruction in the same block, whose only operand is
/// the cast result. Neither the view nor its fast-path status enters MilkIR.
fn adjacent_cast_views(
  function : @milkir.Function,
  environment : Environment,
) -> Map[Int32, Int32] {
  let pairs : Map[Int32, Int32] = Map([])
  if !environment.ordinary_view_publication ||
    environment.struct_views is None ||
    environment.gc_heap_field is None {
    return pairs
  }
  for block in function.blocks {
    let ids = function.block_instruction_ids(block)
    for index in 1..<ids.length() {
      let projection = function.instruction_by_id(ids[index]).unwrap()
      if projection.opcode is Ext(op, _) &&
        decode_projection(op) is Some(StructData(type_index)) &&
        projection.args is [source] {
        let cast = function.instruction_by_id(ids[index - 1]).unwrap()
        if @wasm_milkir.decode_opcode(cast.opcode)
          is Some(RefCast(target, false)) &&
          cast.results is [result] &&
          target == type_index &&
          result.id == source.id {
          pairs[cast.id] = projection.id
        }
      }
    }
  }
  pairs
}

///|
/// An exact live identity and checked physical layout admit both operations.
/// On a miss the original cast executes here, so its trap retains its own
/// source location. The following projection performs its own checked miss.
fn lower_cast_with_view(
  context : @adapter.InstructionContext,
  environment : Environment,
  type_index : Int32,
  shape : UInt64,
  fields : Int32,
) -> @lowering.Value {
  let slow = context.create_block([])
  let ready = context.create_block([GcRef64, Ptr64])
  let reference = context.operands()[0]
  let view = checked_cached_struct_view(
    context,
    environment,
    environment.struct_views.unwrap(),
    type_index,
    shape,
    fields,
    slow,
    exact_type=true,
    cast_exact=true,
  )
  context.jump(ready, [reference, view])
  context.switch_to_block(slow)
  let result = emit_ref_cast(context, environment, type_index, false)
  let zero = context.emit(I64Const(0UL), [], [I64])[0]
  let no_view = context.emit(Convert(Bitcast(I64, Ptr64)), [zero], [Ptr64])[0]
  context.jump(ready, [result, no_view])
  context.switch_to_block(ready)
  let values = context.block_parameters(ready)
  context.forward_results([values[0]])
  values[1]
}

///|
fn lower_cast_view_use(
  context : @adapter.InstructionContext,
  environment : Environment,
  type_index : Int32,
  shape : UInt64,
  fields : Int32,
  view : @lowering.Value,
) -> Unit {
  let slow = context.create_block([])
  let ready = context.create_block([Ptr64])
  view_guard_nonzero(context, view, slow)
  context.jump(ready, [view])
  context.switch_to_block(slow)
  let view = emit_struct_data(context, environment, type_index, shape, fields)
  context.jump(ready, [view])
  context.switch_to_block(ready)
  context.forward_results(context.block_parameters(ready))
}
