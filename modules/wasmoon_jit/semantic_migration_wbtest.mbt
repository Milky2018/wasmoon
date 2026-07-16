///|
fn semantic_wasm_environment(
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
) -> @wasm_machv.Environment {
  let helper_symbols = @wasm_isa_lower.external_helper_symbols(
    wasm_runtime_symbols(),
  )
  let canonical_type_indices = canonical_type_indices.copy()
  @wasm_machv.Environment::new(
    fn(index) { @semantic_machv.CodeSymbol::new("wasm.func.\{index}") },
    fn(index) {
      @semantic_machv.EnvironmentField::new(
        "wasmoon.vmctx.memory.\{index}.base",
        Ptr64,
      )
    },
    @semantic_machv.EnvironmentField::new("wasmoon.vmctx.function_table", Ptr64),
    fn(index) {
      @semantic_machv.EnvironmentField::new(
        "wasmoon.vmctx.table.\{index}.base",
        Ptr64,
      )
    },
    fn(raw_type_index) {
      if use_subtype_indirect_check {
        return raw_type_index
      }
      if raw_type_index >= 0 && raw_type_index < canonical_type_indices.length() {
        canonical_type_indices[raw_type_index]
      } else {
        raw_type_index
      }
    },
    fn(capability) {
      match helper_symbols.get(capability) {
        Some(symbol) => @semantic_machv.ExternalSymbol::new(symbol)
        None => abort("missing Wasmoon runtime capability '\{capability}'")
      }
    },
  )
}

///|
struct NormalizedCallSite {
  block : Int
  kind : String
  target : String
  argument_count : Int
  result_count : Int
} derive(Debug, Eq)

///|
struct NormalizedBlock {
  parameters : Array[String]
  terminator : String
  successors : Array[Int]
} derive(Debug, Eq)

///|
struct NormalizedFunction {
  name : String
  parameters : Array[String]
  results : Array[String]
  blocks : Array[NormalizedBlock]
  calls : Array[NormalizedCallSite]
} derive(Debug, Eq)

///|
struct SemanticCallFacts {
  block : Int
  target : String
  protocol : @semantic_machv.CallProtocol
  behavior : @semantic_machv.CallBehavior
  live_gc_roots : Int
} derive(Debug, Eq)

///|
struct MigrationComparison {
  legacy : NormalizedFunction
  semantic : NormalizedFunction
  semantic_call_facts : Array[SemanticCallFacts]
} derive(Debug, Eq)

///|
impl Show for MigrationComparison with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn normalized_semantic_type(ty : @semantic_machv.ValueType) -> String {
  match ty {
    I32 | I64 | Ptr64 | GcRef64 => "int"
    F32 => "float32"
    F64 => "float64"
    V128 => "vector"
  }
}

///|
fn normalized_legacy_reg_class(class : @abi.RegClass) -> String {
  match class {
    Int => "int"
    Float32 => "float32"
    Float64 => "float64"
    Vector => "vector"
  }
}

///|
fn normalized_legacy_value_kind(kind : @machv.ValueKind) -> String {
  normalized_legacy_reg_class(kind.reg_class())
}

///|
fn normalized_semantic_target(call : @semantic_machv.SemanticCall) -> String {
  match call.callee {
    Internal(symbol) => "internal:\{symbol.name}"
    External(symbol) => "external:\{symbol.name}"
    Indirect => "indirect"
  }
}

///|
fn normalized_semantic_terminator(
  function : @semantic_machv.Function,
  record : @semantic_machv.TerminatorRecord,
) -> (String, Array[Int]) {
  match record.kind {
    Jump(edge) =>
      (
        "jump(args=\{edge.arguments.length()})",
        [function.block_index(edge.target).unwrap()],
      )
    Branch(_, true_edge, false_edge) =>
      (
        "branch",
        [
          function.block_index(true_edge.target).unwrap(),
          function.block_index(false_edge.target).unwrap(),
        ],
      )
    Switch(_, cases, default_edge) => {
      let successors : Array[Int] = []
      for case in cases {
        successors.push(function.block_index(case.edge.target).unwrap())
      }
      successors.push(function.block_index(default_edge.target).unwrap())
      ("switch", successors)
    }
    Return(values) => ("return(values=\{values.length()})", [])
    TailCall(call, _) => ("tail-call:\{normalized_semantic_target(call)}", [])
    NoReturnCall(call, _) =>
      ("noreturn-call:\{normalized_semantic_target(call)}", [])
    Trap(reason) => ("trap:\{to_repr(reason)}", [])
  }
}

///|
fn normalize_semantic_function(
  function : @semantic_machv.Function,
) -> (NormalizedFunction, Array[SemanticCallFacts]) {
  let parameters : Array[String] = []
  for parameter in function.parameters() {
    parameters.push(
      normalized_semantic_type(function.value_type(parameter).unwrap()),
    )
  }
  let results = function.signature().results.map(normalized_semantic_type)
  let blocks : Array[NormalizedBlock] = []
  let calls : Array[NormalizedCallSite] = []
  let call_facts : Array[SemanticCallFacts] = []
  for block in function.blocks() {
    let block_index = function.block_index(block).unwrap()
    let block_parameters : Array[String] = []
    for parameter in function.block_parameters(block) {
      block_parameters.push(
        normalized_semantic_type(function.value_type(parameter).unwrap()),
      )
    }
    for instruction in function.block_instructions(block) {
      if function.instruction_operation(instruction) is Some(Call(call)) {
        let metadata = function.instruction_metadata(instruction).unwrap()
        calls.push({
          block: block_index,
          kind: "call",
          target: normalized_semantic_target(call),
          argument_count: call.signature.params.length(),
          result_count: call.signature.results.length(),
        })
        call_facts.push({
          block: block_index,
          target: normalized_semantic_target(call),
          protocol: call.protocol,
          behavior: call.behavior,
          live_gc_roots: metadata.live_gc_roots.length(),
        })
      }
    }
    let (terminator, successors) = normalized_semantic_terminator(
      function,
      function.block_terminator(block).unwrap(),
    )
    blocks.push({ parameters: block_parameters, terminator, successors })
  }
  ({ name: function.name(), parameters, results, blocks, calls }, call_facts)
}

///|
fn normalized_legacy_terminator(
  terminator : @instr.Terminator,
) -> (String, Array[Int]) {
  match terminator {
    Jump(target, arguments) => ("jump(args=\{arguments.length()})", [target])
    Branch(_, true_block, false_block)
    | BranchCmp(_, _, _, _, true_block, false_block)
    | BranchZero(_, _, _, true_block, false_block)
    | BranchCmpImm(_, _, _, _, true_block, false_block) =>
      ("branch", [true_block, false_block])
    Return(values) => ("return(values=\{values.length()})", [])
    Trap(_) => ("trap", [])
    BrTable(_, targets, default) => {
      let successors = targets.copy()
      successors.push(default)
      ("switch", successors)
    }
  }
}

///|
fn normalize_legacy_function(function : @machv.Function) -> NormalizedFunction {
  let parameters = function
    .get_params()
    .map(parameter => normalized_legacy_reg_class(parameter.class))
  let results = function.get_result_kinds().map(normalized_legacy_value_kind)
  let blocks : Array[NormalizedBlock] = []
  let calls : Array[NormalizedCallSite] = []
  for block in function.get_blocks() {
    for instruction in block.insts {
      match instruction.opcode {
        CallDirect(symbol, _, result_classes, _) =>
          calls.push({
            block: block.id,
            kind: "call",
            target: "internal:\{symbol}",
            argument_count: instruction.uses.length(),
            result_count: result_classes.length(),
          })
        CallExternal(symbol, _, result_classes, _) =>
          calls.push({
            block: block.id,
            kind: "call",
            target: "external:\{symbol}",
            argument_count: instruction.uses.length(),
            result_count: result_classes.length(),
          })
        CallPtr(_, result_classes, _) =>
          calls.push({
            block: block.id,
            kind: "call",
            target: "indirect",
            argument_count: instruction.uses.length() - 1,
            result_count: result_classes.length(),
          })
        ReturnCallIndirect(_, result_count) =>
          calls.push({
            block: block.id,
            kind: "tail-call",
            target: "indirect",
            argument_count: instruction.uses.length() - 1,
            result_count,
          })
        _ => ()
      }
    }
    let block_parameters = block.params.map(parameter => {
      normalized_legacy_reg_class(parameter.class)
    })
    let (terminator, successors) = normalized_legacy_terminator(
      block.terminator.unwrap(),
    )
    blocks.push({ parameters: block_parameters, terminator, successors })
  }
  { name: function.get_name(), parameters, results, blocks, calls }
}

///|
test "product semantic Wasm lowering keeps runtime identities unresolved" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("semantic_caller")
  builder.add_param(I64) |> ignore
  let argument = builder.add_param(I32)
  builder.add_result(I64)
  let results = builder.emit_multi_ext_inst(
    [I64],
    @wasm_milkir.encode(WasmCall(7)),
    [argument],
  )
  builder.return_(results)
  inspect(
    @wasm_machv.lower_function(
      builder.finalize(),
      semantic_wasm_environment(true, []),
    ),
    content=(
      #|machv semantic_caller [internal](v0:ptr64, v1:i32) -> (i64) {
      #|block0:
      #|  v2:i64 = call internal @wasm.func.7 (ptr64, i32) -> (i64) [internal] v0, v1 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v2
      #|}
    ),
  )
}

///|
test "normalized migration contract matches direct Wasm calls" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("migration_caller")
  builder.add_param(I64) |> ignore
  let argument = builder.add_param(I32)
  builder.add_result(I64)
  let results = builder.emit_multi_ext_inst(
    [I64],
    @wasm_milkir.encode(WasmCall(7)),
    [argument],
  )
  builder.return_(results)
  let function = builder.finalize()
  let legacy = @wasm_isa_lower.lower_function(
    function,
    wasm_context_slots(),
    isa=AMD64,
    embedding_abi=Some(wasm_embedding_abi_for_isa(AMD64)),
    runtime_symbols=wasm_runtime_symbols(),
    trap_payload_resolver=wasm_trap_payload,
  )
  let semantic = @wasm_machv.lower_function(
    function,
    semantic_wasm_environment(true, []),
  )
  let (semantic_contract, semantic_call_facts) = normalize_semantic_function(
    semantic,
  )
  inspect(
    MigrationComparison::{
      legacy: normalize_legacy_function(legacy),
      semantic: semantic_contract,
      semantic_call_facts,
    },
    content=(
      #|{
      #|  legacy: {
      #|    name: "migration_caller",
      #|    parameters: ["int", "int"],
      #|    results: ["int"],
      #|    blocks: [{ parameters: [], terminator: "return(values=1)", successors: [] }],
      #|    calls: [
      #|      {
      #|        block: 0,
      #|        kind: "call",
      #|        target: "internal:wasm.func.7",
      #|        argument_count: 2,
      #|        result_count: 1,
      #|      },
      #|    ],
      #|  },
      #|  semantic: {
      #|    name: "migration_caller",
      #|    parameters: ["int", "int"],
      #|    results: ["int"],
      #|    blocks: [{ parameters: [], terminator: "return(values=1)", successors: [] }],
      #|    calls: [
      #|      {
      #|        block: 0,
      #|        kind: "call",
      #|        target: "internal:wasm.func.7",
      #|        argument_count: 2,
      #|        result_count: 1,
      #|      },
      #|    ],
      #|  },
      #|  semantic_call_facts: [
      #|    {
      #|      block: 0,
      #|      target: "internal:wasm.func.7",
      #|      protocol: Internal,
      #|      behavior: {
      #|        memory: ReadWrite,
      #|        may_trap: true,
      #|        may_unwind: true,
      #|        gc_safepoint: true,
      #|        cancellation_safepoint: true,
      #|        returns_twice: false,
      #|      },
      #|      live_gc_roots: 0,
      #|    },
      #|  ],
      #|}
    ),
  )
}
