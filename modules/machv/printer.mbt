///|
fn format_value(value : Value) -> String {
  "v\{value.id}"
}

///|
fn format_value_with_type(function : Function, value : Value) -> String {
  "\{format_value(value)}:\{function.values[value.id].ty}"
}

///|
fn format_values(values : Array[Value]) -> String {
  values.map(format_value).join(", ")
}

///|
fn format_signature(signature : Signature) -> String {
  let params = signature.params.map(type_ => type_.to_string()).join(", ")
  let results = signature.results.map(type_ => type_.to_string()).join(", ")
  "(\{params}) -> (\{results})"
}

///|
fn format_protocol(protocol : CallProtocol) -> String {
  match protocol {
    Internal => "internal"
    Platform => "platform"
  }
}

///|
fn format_callee(callee : Callee) -> String {
  match callee {
    Internal(symbol) => "internal @\{symbol.name}"
    External(symbol) => "external @\{symbol.name}"
    Indirect => "indirect"
  }
}

///|
fn format_call(call : SemanticCall) -> String {
  "\{format_callee(call.callee)} \{format_signature(call.signature)} [\{format_protocol(call.protocol)}]"
}

///|
fn format_operation(operation : Operation) -> String {
  match operation {
    I32Const(bits) => "i32.const \{bits}"
    I64Const(bits) => "i64.const \{bits}"
    F32Const(bits) => "f32.const_bits \{bits}"
    F64Const(bits) => "f64.const_bits \{bits}"
    V128Const(low, high) => "v128.const_bits \{low}, \{high}"
    NullPtr => "ptr.null"
    NullGcRef => "gcref.null"
    CodeAddress(symbol) => "code.address @\{symbol.name}"
    ExternalAddress(symbol) => "external.address @\{symbol.name}"
    DataAddress(symbol) => "data.address @\{symbol.name}"
    Copy => "copy"
    Select => "select"
    GcRefAddress => "gcref.address"
    GcRefFromBits => "gcref.from_bits"
    PointerOffset => "pointer.offset"
    ReferenceCompare(op) => "reference.compare.\{to_repr(op)}"
    IntUnary(op) => "int.unary.\{to_repr(op)}"
    IntBinary(op) => "int.binary.\{to_repr(op)}"
    IntHighMultiply(signedness) => "int.high_multiply.\{to_repr(signedness)}"
    IntWithOverflow(op) => "int.with_overflow.\{to_repr(op)}"
    IntCompare(op) => "int.compare.\{to_repr(op)}"
    FloatUnary(op) => "float.unary.\{to_repr(op)}"
    FloatBinary(op) => "float.binary.\{to_repr(op)}"
    FloatTernary(op) => "float.ternary.\{to_repr(op)}"
    FloatCompare(op) => "float.compare.\{to_repr(op)}"
    Convert(op) => "convert.\{to_repr(op)}"
    Load(spec) => "load \{to_repr(spec)}"
    Store(spec) => "store \{to_repr(spec)}"
    AtomicLoad(spec) => "atomic.load \{to_repr(spec)}"
    AtomicStore(spec) => "atomic.store \{to_repr(spec)}"
    AtomicRmw(spec, op) => "atomic.rmw.\{to_repr(op)} \{to_repr(spec)}"
    AtomicCompareExchange(spec) => "atomic.compare_exchange \{to_repr(spec)}"
    AtomicFence => "atomic.fence"
    Vector(op) => "vector.\{to_repr(op)}"
    VectorLoad(spec) => "vector.load \{to_repr(spec)}"
    VectorStoreLane(spec) => "vector.store_lane \{to_repr(spec)}"
    Call(call) => "call \{format_call(call)}"
    Safepoint(kind) => "safepoint.\{to_repr(kind)}"
  }
}

///|
fn format_memory_effect(effect : MemoryEffect) -> String {
  match effect {
    None => "none"
    Read => "read"
    Write => "write"
    ReadWrite => "read-write"
  }
}

///|
fn format_semantics(semantics : OperationSemantics) -> String {
  let facts : Array[String] = []
  if semantics.memory != None {
    facts.push("memory=\{format_memory_effect(semantics.memory)}")
  }
  if semantics.may_trap {
    facts.push("trap")
  }
  if semantics.may_unwind {
    facts.push("unwind")
  }
  if semantics.gc_safepoint {
    facts.push("gc-safepoint")
  }
  if semantics.cancellation_safepoint {
    facts.push("cancel-safepoint")
  }
  if facts.is_empty() {
    ""
  } else {
    let summary = facts.join(", ")
    " [\{summary}]"
  }
}

///|
fn format_source(source : SourceLocation?) -> String {
  match source {
    None => ""
    Some(location) =>
      " source=\{location.file}:\{location.line}:\{location.column}"
  }
}

///|
fn format_roots(roots : Array[Value]) -> String {
  if roots.is_empty() {
    ""
  } else {
    " roots=[\{format_values(roots)}]"
  }
}

///|
fn format_edge(edge : Edge) -> String {
  let arguments = format_values(edge.arguments)
  if arguments.is_empty() {
    "block\{edge.target.id}"
  } else {
    "block\{edge.target.id}(\{arguments})"
  }
}

///|
fn format_terminator(record : TerminatorRecord) -> String {
  let text = match record.kind {
    Jump(edge) => "jump \{format_edge(edge)}"
    Branch(condition, true_edge, false_edge) =>
      "branch \{format_value(condition)}, \{format_edge(true_edge)}, \{format_edge(false_edge)}"
    Switch(index, cases, default_edge) => {
      let arms = cases.map(case => "\{case.bits}: \{format_edge(case.edge)}")
      arms.push("default: \{format_edge(default_edge)}")
      let formatted_arms = arms.join(", ")
      "switch \{format_value(index)} [\{formatted_arms}]"
    }
    Return(values) => {
      let values = format_values(values)
      if values.is_empty() {
        "return"
      } else {
        "return \{values}"
      }
    }
    TailCall(call, operands) => {
      let operands = format_values(operands)
      "tail_call \{format_call(call)} (\{operands})\{format_semantics(call.behavior.semantics())}"
    }
    Trap(reason) => "trap \{to_repr(reason)}"
  }
  "\{text}\{format_source(record.metadata.source)}\{format_roots(record.metadata.live_gc_roots)}"
}

///|
/// Render the complete semantic function in a stable target-neutral form.
pub fn Function::print(self : Function) -> String {
  let params = self.parameters
    .map(value => format_value_with_type(self, value))
    .join(", ")
  let results = self.signature.results
    .map(type_ => type_.to_string())
    .join(", ")
  let lines : Array[String] = [
    "machv \{self.name} [\{format_protocol(self.protocol)}](\{params}) -> (\{results}) {",
  ]
  for block_id, block in self.blocks {
    let block_params = block.parameters
      .map(value => format_value_with_type(self, value))
      .join(", ")
    if block_params.is_empty() {
      lines.push("block\{block_id}:")
    } else {
      lines.push("block\{block_id}(\{block_params}):")
    }
    for instruction in block.instructions {
      let data = self.instructions[instruction.id]
      let results = data.results
        .map(value => format_value_with_type(self, value))
        .join(", ")
      let operands = format_values(data.operands)
      let assignment = if results.is_empty() { "" } else { "\{results} = " }
      let operand_suffix = if operands.is_empty() { "" } else { " \{operands}" }
      lines.push(
        "  \{assignment}\{format_operation(data.operation)}\{operand_suffix}\{format_semantics(data.operation.semantics())}\{format_source(data.metadata.source)}\{format_roots(data.metadata.live_gc_roots)}",
      )
    }
    match block.terminator {
      Some(record) => lines.push("  \{format_terminator(record)}")
      None => lines.push("  <missing terminator>")
    }
  }
  lines.push("}")
  lines.join("\n")
}

///|
pub impl Debug for Function with fn to_repr(self) {
  Repr::literal(self.print())
}

///|
pub impl Show for Function with fn output(self, logger) {
  logger.write_string(self.print())
}
