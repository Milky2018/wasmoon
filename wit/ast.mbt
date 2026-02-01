///|
pub(all) struct Package {
  name : String?
  version : String?
  items : Array[TopItem]
  nested : Array[Package]
}

///|
pub(all) enum TopItem {
  Interface(Interface)
  World(World)
  ToplevelUse(ToplevelUse)
}

///|
pub(all) struct ToplevelUse {
  path : UsePath
  as_name : String?
}

///|
pub(all) struct Interface {
  name : String
  items : Array[InterfaceItem]
}

///|
pub(all) enum InterfaceItem {
  Func(FuncDecl)
  TypeAlias(TypeAlias)
  Record(RecordDecl)
  Use(UseItem)
  Resource(ResourceDecl)
  Variant(VariantDecl)
  Flags(FlagsDecl)
  Enum(EnumDecl)
}

///|
pub(all) struct UsePath {
  raw : String
}

///|
pub(all) struct UseItem {
  path : UsePath
  names : Array[(String, String?)]
}

///|
pub(all) struct ResourceDecl {
  name : String
  methods : Array[FuncDecl]
}

///|
pub(all) struct World {
  name : String
  items : Array[WorldItem]
}

///|
pub(all) enum WorldItem {
  Import(UsePath)
  Export(UsePath)
  ImportFunc(FuncDecl) // `import name: func(...);`
  ExportFunc(FuncDecl) // `export name: func(...);`
  ImportInlineInterface(String, InlineInterface) // `import name: interface { ... }`
  ExportInlineInterface(String, InlineInterface) // `export name: interface { ... }`
  Include(IncludeItem)
  Use(UseItem)
  TypeAlias(TypeAlias)
  Record(RecordDecl)
  Resource(ResourceDecl)
  Variant(VariantDecl)
  Flags(FlagsDecl)
  Enum(EnumDecl)
}

///|
pub(all) struct IncludeItem {
  path : UsePath
  renames : Array[(String, String)]?
}

///|
pub(all) struct FuncDecl {
  name : String
  is_async : Bool
  params : Array[(String, TypeExpr)]
  results : Array[(String?, TypeExpr)]
}

///|
pub(all) struct InlineInterface {
  items : Array[InterfaceItem]
}

///|
pub(all) struct TypeAlias {
  name : String
  ty : TypeExpr
}

///|
pub(all) struct RecordDecl {
  name : String
  fields : Array[(String, TypeExpr)]
}

///|
pub(all) struct VariantDecl {
  name : String
  cases : Array[VariantCase]
}

///|
pub(all) struct VariantCase {
  name : String
  payload : TypeExpr?
}

///|
pub(all) struct FlagsDecl {
  name : String
  flags : Array[String]
}

///|
pub(all) struct EnumDecl {
  name : String
  cases : Array[String]
}

///|
pub(all) enum TypeExpr {
  Id(String)
  Apply(String, Array[TypeExpr]) // e.g. list<u8>, option<t>, result<ok, err>
  Record(Array[(String, TypeExpr)]) // inline record { a: u32, ... }
}

///|
