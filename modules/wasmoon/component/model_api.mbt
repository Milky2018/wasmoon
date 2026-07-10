///|
/// Public component-model parser API facade.
///
/// Implementation lives in `Milky2018/wasmoon/component/model`.

///|
pub type BinaryKind = @model.BinaryKind

///|
pub type Section = @model.Section

///|
pub type ComponentBinary = @model.ComponentBinary

///|
pub type ComponentParseError = @model.ComponentParseError

///|
pub type StringEncoding = @model.StringEncoding

///|
pub type CanonOpt = @model.CanonOpt

///|
pub type Canon = @model.Canon

///|
pub type Start = @model.Start

///|
pub type Component = @model.Component

///|
pub type CoreInstantiateArg = @model.CoreInstantiateArg

///|
pub type CoreInlineExport = @model.CoreInlineExport

///|
pub type CoreInstanceExpr = @model.CoreInstanceExpr

///|
pub type CoreInstanceDecl = @model.CoreInstanceDecl

///|
pub type Sort = @model.Sort

///|
pub type SortIdx = @model.SortIdx

///|
pub type TypeBound = @model.TypeBound

///|
pub type ValueBound = @model.ValueBound

///|
pub type ExternDesc = @model.ExternDesc

///|
pub type ImportName = @model.ImportName

///|
pub type ExportName = @model.ExportName

///|
pub type Import = @model.Import

///|
pub type Export = @model.Export

///|
pub type InstantiateArg = @model.InstantiateArg

///|
pub type InlineExport = @model.InlineExport

///|
pub type InstanceExpr = @model.InstanceExpr

///|
pub type Instance = @model.Instance

///|
pub type AliasTarget = @model.AliasTarget

///|
pub type Alias = @model.Alias

///|
pub type PrimValType = @model.PrimValType

///|
pub type ValType = @model.ValType

///|
pub type ResourceKind = @model.ResourceKind

///|
pub type Param = @model.Param

///|
pub type FuncType = @model.FuncType

///|
pub type InstanceDecl = @model.InstanceDecl

///|
pub type ComponentDecl = @model.ComponentDecl

///|
pub type TypeDef = @model.TypeDef

///|
pub type RecordField = @model.RecordField

///|
pub type VariantCase = @model.VariantCase

///|
pub fn sniff_binary_kind(bytes : Bytes) -> BinaryKind? {
  @model.sniff_binary_kind(bytes)
}

///|
pub fn parse_component_binary(
  bytes : Bytes,
) -> ComponentBinary raise ComponentParseError {
  @model.parse_component_binary(bytes)
}

///|
pub fn parse_canon_section(
  payload : Bytes,
) -> Array[Canon] raise ComponentParseError {
  @model.parse_canon_section(payload)
}

///|
pub fn parse_start_section(payload : Bytes) -> Start raise ComponentParseError {
  @model.parse_start_section(payload)
}

///|
pub fn parse_component(bytes : Bytes) -> Component raise ComponentParseError {
  @model.parse_component(bytes)
}

///|
pub fn parse_core_instance_section(
  payload : Bytes,
) -> Array[CoreInstanceDecl] raise ComponentParseError {
  @model.parse_core_instance_section(payload)
}

///|
pub fn parse_import_section(
  payload : Bytes,
) -> Array[Import] raise ComponentParseError {
  @model.parse_import_section(payload)
}

///|
pub fn parse_export_section(
  payload : Bytes,
) -> Array[Export] raise ComponentParseError {
  @model.parse_export_section(payload)
}

///|
pub fn parse_instance_section(
  payload : Bytes,
) -> Array[Instance] raise ComponentParseError {
  @model.parse_instance_section(payload)
}

///|
pub fn parse_alias_section(
  payload : Bytes,
) -> Array[Alias] raise ComponentParseError {
  @model.parse_alias_section(payload)
}

///|
pub fn parse_type_section(
  payload : Bytes,
) -> Array[TypeDef] raise ComponentParseError {
  @model.parse_type_section(payload)
}
