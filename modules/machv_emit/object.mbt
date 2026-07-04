///|
pub(all) enum RelocationKind {
  ExternalSymbol(String)
  BlockTarget(Int)
} derive(Eq, Debug)

///|
pub(all) struct Relocation {
  offset : Int
  kind : RelocationKind
} derive(Eq, Debug)

///|
pub(all) struct Fixup {
  offset : Int
  block_id : Int
} derive(Eq, Debug)

///|
pub(all) struct StackMap {
  offset : Int
  effect : @machv.StackEffect
} derive(Eq, Debug)

///|
pub(all) struct DebugEntry {
  offset : Int
  block_id : Int
  inst_id : Int
  opcode : String
} derive(Eq, Debug)

///|
pub(all) struct CodeObject {
  code : Array[Int]
  relocations : Array[Relocation]
  fixups : Array[Fixup]
  stack_maps : Array[StackMap]
  debug_entries : Array[DebugEntry]
} derive(Debug)

///|
pub fn CodeObject::new() -> CodeObject {
  { code: [], relocations: [], fixups: [], stack_maps: [], debug_entries: [] }
}

///|
pub fn CodeObject::current_offset(self : CodeObject) -> Int {
  self.code.length()
}
