///|
/// Runtime implementation aliases for component model parser/types.

///|
type Component = @component.Component

///|
type TypeDef = @component.TypeDef

///|
type FuncType = @component.FuncType

///|
type ValType = @component.ValType

///|
type Canon = @component.Canon

///|
type CanonOpt = @component.CanonOpt

///|
type Start = @component.Start

///|
type StringEncoding = @component.StringEncoding

///|
type ResourceKind = @component.ResourceKind

///|
type ImportName = @component.ImportName

///|
type ExportName = @component.ExportName

///|
type ExternDesc = @component.ExternDesc

///|
type Sort = @component.Sort

///|
type SortIdx = @component.SortIdx

///|
type TypeBound = @component.TypeBound

///|
type Import = @component.Import

///|
type Export = @component.Export

///|
type Instance = @component.Instance

///|
type InstanceDecl = @component.InstanceDecl

///|
type InstanceExpr = @component.InstanceExpr

///|
type Alias = @component.Alias

///|
type AliasTarget = @component.AliasTarget

///|
type CoreInstanceDecl = @component.CoreInstanceDecl

///|
type CoreInstantiateArg = @component.CoreInstantiateArg

///|
type CoreInlineExport = @component.CoreInlineExport

///|
type CoreInstanceExpr = @component.CoreInstanceExpr

///|
type ComponentParseError = @component.ComponentParseError

///|
fn parse_component(bytes : Bytes) -> Component raise ComponentParseError {
  @component.parse_component(bytes)
}

///|
fn parse_core_instance_section(
  payload : Bytes,
) -> Array[CoreInstanceDecl] raise ComponentParseError {
  @component.parse_core_instance_section(payload)
}

///|
fn parse_type_section(
  payload : Bytes,
) -> Array[TypeDef] raise ComponentParseError {
  @component.parse_type_section(payload)
}

///|
fn parse_instance_section(
  payload : Bytes,
) -> Array[Instance] raise ComponentParseError {
  @component.parse_instance_section(payload)
}

///|
fn parse_import_section(
  payload : Bytes,
) -> Array[Import] raise ComponentParseError {
  @component.parse_import_section(payload)
}

///|
fn parse_alias_section(
  payload : Bytes,
) -> Array[Alias] raise ComponentParseError {
  @component.parse_alias_section(payload)
}

///|
fn parse_export_section(
  payload : Bytes,
) -> Array[Export] raise ComponentParseError {
  @component.parse_export_section(payload)
}

///|
fn parse_canon_section(
  payload : Bytes,
) -> Array[Canon] raise ComponentParseError {
  @component.parse_canon_section(payload)
}

///|
fn parse_start_section(payload : Bytes) -> Start raise ComponentParseError {
  @component.parse_start_section(payload)
}
