///|
/// Copy editable section containers. Syntax values inside sections are immutable.
/// Mutating either module's sections cannot change the other module.
pub fn Module::snapshot(self : Module) -> Module {
  {
    ..self,
    types: self.types.copy(),
    type_rec_groups: self.type_rec_groups.copy(),
    imports: self.imports.copy(),
    funcs: self.funcs.copy(),
    tables: self.tables.copy(),
    memories: self.memories.copy(),
    globals: self.globals.copy(),
    exports: self.exports.copy(),
    elems: self.elems.copy(),
    codes: self.codes.copy(),
    datas: self.datas.copy(),
    tags: self.tags.copy(),
    func_names: self.func_names.copy(),
  }
}
