// PROTOTYPE ONLY: this package answers the interface-shape question in
// issues/ISS-185.md. It is not a production MachV or Target VCode package.

///|
priv struct VReg(Int)

///|
priv struct BlockId(Int)

///|
priv struct InstId(Int)

///|
priv enum OperandKind {
  Use
  Def
}

///|
priv enum OperandConstraint {
  Any
  Fixed(Int)
  TiedTo(Int)
}

///|
priv struct Operand {
  reg : VReg
  kind : OperandKind
  constraint : OperandConstraint
}

///|
priv enum InstRole {
  Body
  Terminator
}

///|
priv trait AllocatableInst {
  fn operands(Self) -> Array[Operand]
}

///|
priv trait RenderInst {
  fn mnemonic(Self) -> String
}

///|
priv struct InstNode[Inst] {
  id : InstId
  inst : Inst
}

///|
priv struct Edge {
  target : BlockId
  arguments : Array[VReg]
}

///|
priv struct Terminator[Inst] {
  node : InstNode[Inst]
  successors : Array[Edge]
}

///|
priv struct VCodeBlock[Inst] {
  id : BlockId
  params : Array[VReg]
  body : Array[InstNode[Inst]]
  terminator : Terminator[Inst]
}

///|
priv struct VCodeFunction[Inst] {
  name : String
  blocks : Array[VCodeBlock[Inst]]
}

///|
priv struct RegallocInst {
  block : BlockId
  inst : InstId
  role : InstRole
  operands : Array[Operand]
}

///|
priv struct RegallocView {
  function_name : String
  blocks : Array[BlockId]
  instructions : Array[RegallocInst]
}

///|
fn[Inst : AllocatableInst] project_regalloc(
  function : VCodeFunction[Inst],
) -> RegallocView {
  let blocks : Array[BlockId] = []
  let instructions : Array[RegallocInst] = []
  for block in function.blocks {
    blocks.push(block.id)
    for node in block.body {
      instructions.push({
        block: block.id,
        inst: node.id,
        role: Body,
        operands: AllocatableInst::operands(node.inst),
      })
    }
    let node = block.terminator.node
    instructions.push({
      block: block.id,
      inst: node.id,
      role: Terminator,
      operands: AllocatableInst::operands(node.inst),
    })
  }
  { function_name: function.name, blocks, instructions }
}

///|
priv enum AArch64Inst {
  Add64(VReg, VReg, VReg)
  AddShifted64(VReg, VReg, VReg, Int)
  BranchNonZero(VReg)
}

///|
impl RenderInst for AArch64Inst with fn mnemonic(self) {
  match self {
    Add64(_, _, _) => "add xD, xN, xM"
    AddShifted64(_, _, _, amount) => "add xD, xN, xM, lsl #\{amount}"
    BranchNonZero(_) => "cbnz xN, block"
  }
}

///|
impl AllocatableInst for AArch64Inst with fn operands(self) {
  match self {
    Add64(dst, lhs, rhs) | AddShifted64(dst, lhs, rhs, _) =>
      [
        { reg: lhs, kind: Use, constraint: Any },
        { reg: rhs, kind: Use, constraint: Any },
        { reg: dst, kind: Def, constraint: Any },
      ]
    BranchNonZero(value) => [{ reg: value, kind: Use, constraint: Any }]
  }
}

///|
priv enum AMD64Inst {
  Add64(VReg, VReg, VReg)
  SetParity(VReg)
  BranchNonZero(VReg)
}

///|
impl RenderInst for AMD64Inst with fn mnemonic(self) {
  match self {
    Add64(_, _, _) => "lea rD, [rN + rM]"
    SetParity(_) => "setp r8b"
    BranchNonZero(_) => "test rN, rN; jnz block"
  }
}

///|
impl AllocatableInst for AMD64Inst with fn operands(self) {
  match self {
    Add64(dst, lhs, rhs) =>
      [
        { reg: lhs, kind: Use, constraint: Any },
        { reg: rhs, kind: Use, constraint: Any },
        { reg: dst, kind: Def, constraint: Any },
      ]
    SetParity(dst) => [{ reg: dst, kind: Def, constraint: Fixed(0) }]
    BranchNonZero(value) => [{ reg: value, kind: Use, constraint: TiedTo(0) }]
  }
}

///|
fn aarch64_demo() -> VCodeFunction[AArch64Inst] {
  let v0 = VReg(0)
  let v1 = VReg(1)
  let v2 = VReg(2)
  {
    name: "aarch64_demo",
    blocks: [
      {
        id: BlockId(0),
        params: [v0, v1],
        body: [
          { id: InstId(0), inst: Add64(v2, v0, v1) },
          { id: InstId(1), inst: AddShifted64(v2, v0, v1, 3) },
        ],
        terminator: {
          node: { id: InstId(2), inst: BranchNonZero(v2) },
          successors: [
            { target: BlockId(1), arguments: [v2] },
            { target: BlockId(2), arguments: [] },
          ],
        },
      },
    ],
  }
}

///|
fn amd64_demo() -> VCodeFunction[AMD64Inst] {
  let v0 = VReg(0)
  let v1 = VReg(1)
  let v2 = VReg(2)
  let v3 = VReg(3)
  {
    name: "amd64_demo",
    blocks: [
      {
        id: BlockId(0),
        params: [v0, v1],
        body: [
          { id: InstId(0), inst: Add64(v2, v0, v1) },
          { id: InstId(1), inst: SetParity(v3) },
        ],
        terminator: {
          node: { id: InstId(2), inst: BranchNonZero(v2) },
          successors: [
            { target: BlockId(1), arguments: [v2, v3] },
            { target: BlockId(2), arguments: [] },
          ],
        },
      },
    ],
  }
}

///|
fn operand_text(operand : Operand) -> String {
  let kind = match operand.kind {
    Use => "use"
    Def => "def"
  }
  let constraint = match operand.constraint {
    Any => "any"
    Fixed(reg) => "fixed(p\{reg})"
    TiedTo(index) => "tied-to(\{index})"
  }
  "\{kind} v\{operand.reg.0} \{constraint}"
}

///|
fn[Inst : RenderInst] render_function(function : VCodeFunction[Inst]) -> String {
  let mut out = "function \{function.name}\n"
  for block in function.blocks {
    out = out + "  block\{block.id.0}("
    for i, param in block.params {
      if i > 0 {
        out = out + ", "
      }
      out = out + "v\{param.0}"
    }
    out = out + ")\n"
    for node in block.body {
      out = out + "    i\{node.id.0}: \{RenderInst::mnemonic(node.inst)}\n"
    }
    let term = block.terminator
    out = out +
      "    i\{term.node.id.0}: \{RenderInst::mnemonic(term.node.inst)}"
    for edge in term.successors {
      out = out + " -> block\{edge.target.0}("
      for i, argument in edge.arguments {
        if i > 0 {
          out = out + ", "
        }
        out = out + "v\{argument.0}"
      }
      out = out + ")"
    }
    out = out + "\n"
  }
  out
}

///|
fn render_regalloc_view(target : String, view : RegallocView) -> String {
  let mut out = "\{target} regalloc view for \{view.function_name}"
  out = out + " (\{view.blocks.length()} blocks)\n"
  for item in view.instructions {
    let role = match item.role {
      Body => "body"
      Terminator => "term"
    }
    out = out + "  block\{item.block.0}/i\{item.inst.0} [\{role}]\n"
    for operand in item.operands {
      out = out + "    - \{operand_text(operand)}\n"
    }
  }
  out
}
