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
  successor_argument_counts : Array[Int]
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
) -> (String, Array[Int], Array[Int]) {
  match record.kind {
    Jump(edge) =>
      (
        "jump",
        [function.block_index(edge.target).unwrap()],
        [edge.arguments.length()],
      )
    Branch(_, true_edge, false_edge) =>
      (
        "branch",
        [
          function.block_index(true_edge.target).unwrap(),
          function.block_index(false_edge.target).unwrap(),
        ],
        [true_edge.arguments.length(), false_edge.arguments.length()],
      )
    Switch(_, cases, default_edge) => {
      let successors : Array[Int] = []
      let argument_counts : Array[Int] = []
      for case in cases {
        successors.push(function.block_index(case.edge.target).unwrap())
        argument_counts.push(case.edge.arguments.length())
      }
      successors.push(function.block_index(default_edge.target).unwrap())
      argument_counts.push(default_edge.arguments.length())
      ("switch", successors, argument_counts)
    }
    Return(values) => ("return(values=\{values.length()})", [], [])
    TailCall(call, _) =>
      ("tail-call:\{normalized_semantic_target(call)}", [], [])
    NoReturnCall(call, _) =>
      ("noreturn-call:\{normalized_semantic_target(call)}", [], [])
    Trap(_) => ("trap", [], [])
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
    let (terminator, successors, successor_argument_counts) = normalized_semantic_terminator(
      function,
      function.block_terminator(block).unwrap(),
    )
    blocks.push({
      parameters: block_parameters,
      terminator,
      successors,
      successor_argument_counts,
    })
  }
  ({ name: function.name(), parameters, results, blocks, calls }, call_facts)
}

///|
fn normalized_legacy_terminator(
  terminator : @instr.Terminator,
) -> (String, Array[Int], Array[Int]) {
  match terminator {
    Jump(target, arguments) => ("jump", [target], [arguments.length()])
    Branch(_, true_block, false_block)
    | BranchCmp(_, _, _, _, true_block, false_block)
    | BranchZero(_, _, _, true_block, false_block)
    | BranchCmpImm(_, _, _, _, true_block, false_block) =>
      ("branch", [true_block, false_block], [0, 0])
    Return(values) => ("return(values=\{values.length()})", [], [])
    Trap(_) => ("trap", [], [])
    BrTable(_, targets, default) => {
      let successors = targets.copy()
      successors.push(default)
      ("switch", successors, Array::make(successors.length(), 0))
    }
  }
}

///|
fn resolve_legacy_synthetic_edge(
  function : @machv.Function,
  source_block_count : Int,
  target : Int,
  argument_count : Int,
) -> (Int, Int) {
  let blocks = function.get_blocks()
  let mut target = target
  let mut argument_count = argument_count
  while target >= source_block_count {
    if target < 0 ||
      target >= blocks.length() ||
      blocks[target].id != target ||
      !blocks[target].params.is_empty() ||
      !blocks[target].insts.is_empty() {
      break
    }
    match blocks[target].terminator {
      Some(Jump(next_target, arguments)) => {
        target = next_target
        argument_count = arguments.length()
      }
      _ => break
    }
  }
  (target, argument_count)
}

///|
fn normalize_legacy_function(
  function : @machv.Function,
  source_block_count : Int,
) -> NormalizedFunction {
  let parameters = function
    .get_params()
    .map(parameter => normalized_legacy_reg_class(parameter.class))
  let results = function.get_result_kinds().map(normalized_legacy_value_kind)
  let blocks : Array[NormalizedBlock] = []
  let calls : Array[NormalizedCallSite] = []
  let known_call_targets : Map[Int, String] = Map([])
  for block in function.get_blocks() {
    if block.id >= source_block_count {
      continue
    }
    for instruction in block.insts {
      match instruction.opcode {
        LoadExternalFuncAddr(symbol) =>
          if instruction.defs.length() == 1 &&
            instruction.defs[0].reg is Virtual(vreg) {
            known_call_targets[vreg.id] = "external:\{symbol}"
          }
        LoadCodeAddr(symbol) =>
          if instruction.defs.length() == 1 &&
            instruction.defs[0].reg is Virtual(vreg) {
            known_call_targets[vreg.id] = "internal:\{symbol}"
          }
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
            target: match instruction.uses {
              [Virtual(callee), ..] =>
                known_call_targets.get(callee.id).unwrap_or("indirect")
              _ => "indirect"
            },
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
    let (terminator, successors, successor_argument_counts) = normalized_legacy_terminator(
      block.terminator.unwrap(),
    )
    for index in 0..<successors.length() {
      let (target, argument_count) = resolve_legacy_synthetic_edge(
        function,
        source_block_count,
        successors[index],
        successor_argument_counts[index],
      )
      successors[index] = target
      successor_argument_counts[index] = argument_count
    }
    blocks.push({
      parameters: block_parameters,
      terminator,
      successors,
      successor_argument_counts,
    })
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
      legacy: normalize_legacy_function(legacy, function.blocks.length()),
      semantic: semantic_contract,
      semantic_call_facts,
    },
    content=(
      #|{
      #|  legacy: {
      #|    name: "migration_caller",
      #|    parameters: ["int", "int"],
      #|    results: ["int"],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
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
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
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

///|
test "normalized migration contract preserves conditional edge arguments" {
  let function = @milkir.Function::with_signature(
    "migration_branch",
    Signature([I64, I32, I64, I64], [I64]),
  )
  let condition = function.param(1).unwrap()
  let true_value = function.param(2).unwrap()
  let false_value = function.param(3).unwrap()
  let true_parameter = function.new_value(I64)
  let false_parameter = function.new_value(I64)
  let entry = function.new_block([])
  let true_block = function.new_block([true_parameter])
  let false_block = function.new_block([false_parameter])
  entry.set_terminator(
    Branch(condition, true_block.id, [true_value], false_block.id, [false_value]),
  )
  true_block.set_terminator(Return([true_parameter]))
  false_block.set_terminator(Return([false_parameter]))
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
      legacy: normalize_legacy_function(legacy, function.blocks.length()),
      semantic: semantic_contract,
      semantic_call_facts,
    },
    content=(
      #|{
      #|  legacy: {
      #|    name: "migration_branch",
      #|    parameters: ["int", "int", "int", "int"],
      #|    results: ["int"],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "branch",
      #|        successors: [1, 2],
      #|        successor_argument_counts: [1, 1],
      #|      },
      #|      {
      #|        parameters: ["int"],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|      {
      #|        parameters: ["int"],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
      #|    calls: [],
      #|  },
      #|  semantic: {
      #|    name: "migration_branch",
      #|    parameters: ["int", "int", "int", "int"],
      #|    results: ["int"],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "branch",
      #|        successors: [1, 2],
      #|        successor_argument_counts: [1, 1],
      #|      },
      #|      {
      #|        parameters: ["int"],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|      {
      #|        parameters: ["int"],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
      #|    calls: [],
      #|  },
      #|  semantic_call_facts: [],
      #|}
    ),
  )
}

///|
test "normalized migration contract preserves indirect-call GC roots" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "migration_reference_call",
  )
  builder.add_param(I64) |> ignore
  let callee = builder.add_param(CallableRef)
  let argument = builder.add_param(I32)
  builder.add_result(I32)
  let results = builder.emit_multi_ext_inst(
    [I32],
    @wasm_milkir.encode(CallRef(2)),
    [callee, argument],
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
      legacy: normalize_legacy_function(legacy, function.blocks.length()),
      semantic: semantic_contract,
      semantic_call_facts,
    },
    content=(
      #|{
      #|  legacy: {
      #|    name: "migration_reference_call",
      #|    parameters: ["int", "int", "int"],
      #|    results: ["int"],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
      #|    calls: [
      #|      {
      #|        block: 0,
      #|        kind: "call",
      #|        target: "indirect",
      #|        argument_count: 2,
      #|        result_count: 1,
      #|      },
      #|    ],
      #|  },
      #|  semantic: {
      #|    name: "migration_reference_call",
      #|    parameters: ["int", "int", "int"],
      #|    results: ["int"],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
      #|    calls: [
      #|      {
      #|        block: 0,
      #|        kind: "call",
      #|        target: "indirect",
      #|        argument_count: 2,
      #|        result_count: 1,
      #|      },
      #|    ],
      #|  },
      #|  semantic_call_facts: [
      #|    {
      #|      block: 0,
      #|      target: "indirect",
      #|      protocol: Internal,
      #|      behavior: {
      #|        memory: ReadWrite,
      #|        may_trap: true,
      #|        may_unwind: true,
      #|        gc_safepoint: true,
      #|        cancellation_safepoint: true,
      #|        returns_twice: false,
      #|      },
      #|      live_gc_roots: 1,
      #|    },
      #|  ],
      #|}
    ),
  )
}

///|
test "normalized migration contract preserves explicit traps" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("migration_trap")
  builder.add_param(I64) |> ignore
  builder.trap("unreachable")
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
      legacy: normalize_legacy_function(legacy, function.blocks.length()),
      semantic: semantic_contract,
      semantic_call_facts,
    },
    content=(
      #|{
      #|  legacy: {
      #|    name: "migration_trap",
      #|    parameters: ["int"],
      #|    results: [],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "trap",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
      #|    calls: [],
      #|  },
      #|  semantic: {
      #|    name: "migration_trap",
      #|    parameters: ["int"],
      #|    results: [],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "trap",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
      #|    calls: [],
      #|  },
      #|  semantic_call_facts: [],
      #|}
    ),
  )
}

///|
test "normalized migration contract preserves non-safepoint runtime calls" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("migration_array_len")
  builder.add_param(I64) |> ignore
  let reference = builder.add_param(Ref)
  builder.add_result(I32)
  let length = @wasm_milkir.array_len(builder, reference)
  builder.return_([length])
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
      legacy: normalize_legacy_function(legacy, function.blocks.length()),
      semantic: semantic_contract,
      semantic_call_facts,
    },
    content=(
      #|{
      #|  legacy: {
      #|    name: "migration_array_len",
      #|    parameters: ["int", "int"],
      #|    results: ["int"],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
      #|    calls: [
      #|      {
      #|        block: 0,
      #|        kind: "call",
      #|        target: "external:wasmoon.runtime.gc.array_len",
      #|        argument_count: 1,
      #|        result_count: 1,
      #|      },
      #|    ],
      #|  },
      #|  semantic: {
      #|    name: "migration_array_len",
      #|    parameters: ["int", "int"],
      #|    results: ["int"],
      #|    blocks: [
      #|      {
      #|        parameters: [],
      #|        terminator: "return(values=1)",
      #|        successors: [],
      #|        successor_argument_counts: [],
      #|      },
      #|    ],
      #|    calls: [
      #|      {
      #|        block: 0,
      #|        kind: "call",
      #|        target: "external:wasmoon.runtime.gc.array_len",
      #|        argument_count: 1,
      #|        result_count: 1,
      #|      },
      #|    ],
      #|  },
      #|  semantic_call_facts: [
      #|    {
      #|      block: 0,
      #|      target: "external:wasmoon.runtime.gc.array_len",
      #|      protocol: Platform,
      #|      behavior: {
      #|        memory: Read,
      #|        may_trap: true,
      #|        may_unwind: false,
      #|        gc_safepoint: false,
      #|        cancellation_safepoint: false,
      #|        returns_twice: false,
      #|      },
      #|      live_gc_roots: 0,
      #|    },
      #|  ],
      #|}
    ),
  )
}
