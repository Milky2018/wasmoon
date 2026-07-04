///|
pub(all) struct RuntimeSymbol {
  name : String
  address : Int64
} derive(Eq, Debug)

///|
pub(all) struct RuntimeSymbolResolver {
  symbols : Array[RuntimeSymbol]
} derive(Debug)

///|
pub suberror LinkError {
  UnknownRuntimeSymbol(String)
} derive(Debug, Eq)

///|
pub impl Show for LinkError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn RuntimeSymbolResolver::new() -> RuntimeSymbolResolver {
  { symbols: [] }
}

///|
pub fn RuntimeSymbolResolver::add_symbol(
  self : RuntimeSymbolResolver,
  name : String,
  address : Int64,
) -> Unit {
  self.symbols.push({ name, address })
}

///|
pub fn RuntimeSymbolResolver::resolve(
  self : RuntimeSymbolResolver,
  name : String,
) -> Int64? {
  for symbol in self.symbols {
    if symbol.name == name {
      return Some(symbol.address)
    }
  }
  None
}

///|
pub(all) struct ResolvedRuntimeRelocation {
  offset : Int
  symbol : String
  address : Int64
} derive(Eq, Debug)

///|
pub(all) struct LinkedCode {
  code : Array[Int]
  runtime_relocations : Array[ResolvedRuntimeRelocation]
  block_fixups : Array[@machv_emit.Fixup]
  stack_maps : Array[@machv_emit.StackMap]
  debug_entries : Array[@machv_emit.DebugEntry]
} derive(Debug)

///|
pub fn link_code_object(
  object : @machv_emit.CodeObject,
  resolver : RuntimeSymbolResolver,
) -> LinkedCode raise LinkError {
  let runtime_relocations : Array[ResolvedRuntimeRelocation] = []
  for relocation in object.relocations {
    match relocation.kind {
      ExternalSymbol(symbol) =>
        if resolver.resolve(symbol) is Some(address) {
          runtime_relocations.push({
            offset: relocation.offset,
            symbol,
            address,
          })
        } else {
          raise UnknownRuntimeSymbol(symbol)
        }
      BlockTarget(_) => ()
    }
  }
  {
    code: object.code,
    runtime_relocations,
    block_fixups: object.fixups,
    stack_maps: object.stack_maps,
    debug_entries: object.debug_entries,
  }
}
