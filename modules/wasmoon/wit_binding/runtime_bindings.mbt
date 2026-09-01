///|
/// Checked dynamic bindings from resolved WIT worlds to component instances.
///
/// This is the stable foundation for generated bindings: WIT names and type
/// declarations are resolved once, every exported function is checked against
/// the instantiated component, and callers receive the component facade's
/// typed functions and WIT-semantic values.

///|
pub(all) suberror WitBindingError {
  UnknownWorld(String)
  UnknownInterface(String)
  UnknownType(String)
  RecursiveType(String)
  InvalidType(String)
  DuplicateFunction(String)
  MissingFunction(String)
  RuntimeBindingFailed(String)
} derive(Debug, Eq)

///|
pub impl Show for WitBindingError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
priv enum WitBindingTypeDecl {
  Alias(@wit.TypeExpr)
  RecordType(@wit.RecordDecl)
  VariantType(@wit.VariantDecl)
  FlagsType(@wit.FlagsDecl)
  EnumType(@wit.EnumDecl)
  ResourceType
  ResolvedType(@component.ComponentValueType)
}

///|
priv struct WitBindingScope {
  declarations : Map[String, WitBindingTypeDecl]
}

///|
struct WitBindings {
  functions : Map[String, @component.ComponentFunction]
  ordered_paths : Array[String]
}

///|
pub fn WitBindings::paths(self : WitBindings) -> Array[String] {
  self.ordered_paths.copy()
}

///|
pub fn WitBindings::function(
  self : WitBindings,
  path : String,
) -> @component.ComponentFunction raise WitBindingError {
  self.functions.get(path).unwrap_or_else(() => raise MissingFunction(path))
}

///|
fn wit_binding_packages(result : @wit.ResolveResult) -> Array[@wit.Package] {
  [result.root] + result.deps
}

///|
fn wit_package_interface_path(
  pkg : @wit.Package,
  interface_name : String,
) -> String? {
  guard pkg.name is Some(package_name) else { return None }
  let base = "\{package_name}/\{interface_name}"
  match pkg.version {
    Some(version) => Some("\{base}@\{version}")
    None => Some(base)
  }
}

///|
fn wit_interface_matches_path(
  pkg : @wit.Package,
  interface : @wit.Interface,
  path : String,
) -> Bool {
  if path == interface.name {
    return true
  }
  match wit_package_interface_path(pkg, interface.name) {
    Some(full_path) =>
      path == full_path ||
      path == full_path.split("@").next().unwrap_or("").to_owned()
    None => false
  }
}

///|
fn wit_find_interface(
  result : @wit.ResolveResult,
  path : String,
) -> @wit.Interface raise WitBindingError {
  for pkg in wit_binding_packages(result) {
    for item in pkg.items {
      if item is Interface(interface) &&
        wit_interface_matches_path(pkg, interface, path) {
        return interface
      }
    }
  }
  raise UnknownInterface(path)
}

///|
fn wit_scope_add_interface_declarations(
  scope : WitBindingScope,
  interface : @wit.Interface,
) -> Unit {
  for item in interface.items {
    match item {
      TypeAlias(declaration) =>
        scope.declarations.set(declaration.name, Alias(declaration.ty))
      Record(declaration) =>
        scope.declarations.set(declaration.name, RecordType(declaration))
      Variant(declaration) =>
        scope.declarations.set(declaration.name, VariantType(declaration))
      Flags(declaration) =>
        scope.declarations.set(declaration.name, FlagsType(declaration))
      Enum(declaration) =>
        scope.declarations.set(declaration.name, EnumType(declaration))
      Resource(declaration) =>
        scope.declarations.set(declaration.name, ResourceType)
      Func(_) | Use(_) => ()
    }
  }
}

///|
fn wit_scope_add_world_declarations(
  scope : WitBindingScope,
  world : @wit.World,
) -> Unit {
  for item in world.items {
    match item {
      TypeAlias(declaration) =>
        scope.declarations.set(declaration.name, Alias(declaration.ty))
      Record(declaration) =>
        scope.declarations.set(declaration.name, RecordType(declaration))
      Variant(declaration) =>
        scope.declarations.set(declaration.name, VariantType(declaration))
      Flags(declaration) =>
        scope.declarations.set(declaration.name, FlagsType(declaration))
      Enum(declaration) =>
        scope.declarations.set(declaration.name, EnumType(declaration))
      Resource(declaration) =>
        scope.declarations.set(declaration.name, ResourceType)
      _ => ()
    }
  }
}

///|
fn wit_primitive_type(name : String) -> @component.ComponentValueType? {
  match name {
    "bool" => Some(Bool)
    "s8" => Some(S8)
    "u8" => Some(U8)
    "s16" => Some(S16)
    "u16" => Some(U16)
    "s32" => Some(S32)
    "u32" => Some(U32)
    "s64" => Some(S64)
    "u64" => Some(U64)
    "f32" => Some(F32)
    "f64" => Some(F64)
    "char" => Some(Char)
    "string" => Some(String)
    "error-context" => Some(ErrorContext)
    _ => None
  }
}

///|
fn wit_resolve_named_type(
  name : String,
  scope : WitBindingScope,
  resolving : Map[String, Bool],
) -> @component.ComponentValueType raise WitBindingError {
  if wit_primitive_type(name) is Some(primitive) {
    return primitive
  }
  if resolving.get(name) is Some(true) {
    raise RecursiveType(name)
  }
  guard scope.declarations.get(name) is Some(declaration) else {
    raise UnknownType(name)
  }
  resolving.set(name, true)
  let resolved = match declaration {
    Alias(expression) => wit_resolve_type(expression, scope, resolving)
    RecordType(record) => {
      let fields = []
      for field in record.fields {
        fields.push(
          @component.ComponentField(
            field.0,
            wit_resolve_type(field.1, scope, resolving),
          ),
        )
      }
      Record(fields)
    }
    VariantType(variant) => {
      let cases = []
      for case in variant.cases {
        cases.push(
          @component.ComponentCase(
            case.name,
            match case.payload {
              Some(payload) => Some(wit_resolve_type(payload, scope, resolving))
              None => None
            },
          ),
        )
      }
      Variant(cases)
    }
    FlagsType(flags) => Flags(flags.flags)
    EnumType(enum_) => Enum(enum_.cases)
    ResourceType => Own(@component.ComponentResourceType::named(name))
    ResolvedType(type_) => type_
  }
  resolving.set(name, false)
  resolved
}

///|
fn wit_resource_identity(
  expression : @wit.TypeExpr,
  scope : WitBindingScope,
  resolving : Map[String, Bool],
) -> @component.ComponentResourceType raise WitBindingError {
  match expression {
    Id(name) =>
      match scope.declarations.get(name) {
        Some(ResourceType) => @component.ComponentResourceType::named(name)
        Some(Alias(alias_expr)) =>
          wit_resource_identity(alias_expr, scope, resolving)
        Some(ResolvedType(Own(identity)))
        | Some(ResolvedType(Borrow(identity))) => identity
        _ => raise InvalidType("'\{name}' is not a resource type")
      }
    _ => raise InvalidType("resource handle requires a named resource type")
  }
}

///|
fn wit_resolve_optional_type(
  expression : @wit.TypeExpr,
  scope : WitBindingScope,
  resolving : Map[String, Bool],
) -> @component.ComponentValueType? raise WitBindingError {
  if expression is Id("_") {
    None
  } else {
    Some(wit_resolve_type(expression, scope, resolving))
  }
}

///|
fn wit_resolve_type(
  expression : @wit.TypeExpr,
  scope : WitBindingScope,
  resolving : Map[String, Bool],
) -> @component.ComponentValueType raise WitBindingError {
  match expression {
    Id(name) => wit_resolve_named_type(name, scope, resolving)
    Record(fields) => {
      let resolved = []
      for field in fields {
        resolved.push(
          @component.ComponentField(
            field.0,
            wit_resolve_type(field.1, scope, resolving),
          ),
        )
      }
      Record(resolved)
    }
    Apply(type_constructor, arguments) =>
      match type_constructor {
        "list" =>
          match arguments {
            [element] => List(wit_resolve_type(element, scope, resolving))
            _ => raise InvalidType("list expects one type argument")
          }
        "tuple" => {
          let elements = []
          for element in arguments {
            elements.push(wit_resolve_type(element, scope, resolving))
          }
          Tuple(elements)
        }
        "option" =>
          match arguments {
            [payload] => Option(wit_resolve_type(payload, scope, resolving))
            _ => raise InvalidType("option expects one type argument")
          }
        "result" =>
          match arguments {
            [] => Result(None, None)
            [ok] =>
              Result(wit_resolve_optional_type(ok, scope, resolving), None)
            [ok, error] =>
              Result(
                wit_resolve_optional_type(ok, scope, resolving),
                wit_resolve_optional_type(error, scope, resolving),
              )
            _ => raise InvalidType("result expects at most two type arguments")
          }
        "own" =>
          match arguments {
            [resource] => Own(wit_resource_identity(resource, scope, resolving))
            _ => raise InvalidType("own expects one resource type")
          }
        "borrow" =>
          match arguments {
            [resource] =>
              Borrow(wit_resource_identity(resource, scope, resolving))
            _ => raise InvalidType("borrow expects one resource type")
          }
        "stream" =>
          match arguments {
            [] => Stream(None)
            [payload] =>
              Stream(Some(wit_resolve_type(payload, scope, resolving)))
            _ => raise InvalidType("stream expects zero or one type argument")
          }
        "future" =>
          match arguments {
            [] => Future(None)
            [payload] =>
              Future(Some(wit_resolve_type(payload, scope, resolving)))
            _ => raise InvalidType("future expects zero or one type argument")
          }
        _ => raise InvalidType("unknown type constructor '\{type_constructor}'")
      }
  }
}

///|
fn wit_func_type(
  declaration : @wit.FuncDecl,
  scope : WitBindingScope,
) -> @component.ComponentFuncType raise WitBindingError {
  let params = []
  for param in declaration.params {
    params.push(
      @component.ComponentParam(
        param.0,
        wit_resolve_type(param.1, scope, Map([])),
      ),
    )
  }
  let result = match declaration.results {
    [] => None
    [single] => Some(wit_resolve_type(single.1, scope, Map([])))
    _ =>
      raise InvalidType(
        "function '\{declaration.name}' has more than one result",
      )
  }
  ComponentFuncType(params, result, is_async=declaration.is_async)
}

///|
fn wit_resource_method_type(
  resource : @wit.ResourceDecl,
  declaration : @wit.FuncDecl,
  scope : WitBindingScope,
) -> @component.ComponentFuncType raise WitBindingError {
  let params = [
    @component.ComponentParam(
      "self",
      Borrow(@component.ComponentResourceType::named(resource.name)),
    ),
  ]
  for param in declaration.params {
    params.push(
      ComponentParam(param.0, wit_resolve_type(param.1, scope, Map([]))),
    )
  }
  let result = match declaration.results {
    [] => None
    [single] => Some(wit_resolve_type(single.1, scope, Map([])))
    _ =>
      raise InvalidType(
        "resource method '\{declaration.name}' has more than one result",
      )
  }
  ComponentFuncType(params, result, is_async=declaration.is_async)
}

///|
fn wit_import_used_types(
  result : @wit.ResolveResult,
  scope : WitBindingScope,
  use_item : @wit.UseItem,
) -> Unit raise WitBindingError {
  let source = wit_find_interface(result, use_item.path.raw)
  let source_scope = wit_interface_scope(result, source)
  for name in use_item.names {
    let source_name = name.0
    let local_name = name.1.unwrap_or(source_name)
    let resolved = wit_resolve_named_type(source_name, source_scope, Map([]))
    scope.declarations.set(local_name, ResolvedType(resolved))
  }
}

///|
fn wit_interface_scope(
  result : @wit.ResolveResult,
  interface : @wit.Interface,
) -> WitBindingScope raise WitBindingError {
  let scope : WitBindingScope = { declarations: Map([]), }
  wit_scope_add_interface_declarations(scope, interface)
  for item in interface.items {
    if item is Use(use_item) {
      wit_import_used_types(result, scope, use_item)
    }
  }
  scope
}

///|
fn wit_world_scope(
  result : @wit.ResolveResult,
  world : @wit.World,
) -> WitBindingScope raise WitBindingError {
  let scope : WitBindingScope = { declarations: Map([]), }
  wit_scope_add_world_declarations(scope, world)
  for item in world.items {
    if item is Use(use_item) {
      wit_import_used_types(result, scope, use_item)
    }
  }
  scope
}

///|
fn wit_bind_function(
  bindings : WitBindings,
  instance : @component.ComponentInstance,
  path : String,
  declaration : @wit.FuncDecl,
  scope : WitBindingScope,
) -> Unit raise WitBindingError {
  wit_bind_function_type(
    bindings,
    instance,
    path,
    wit_func_type(declaration, scope),
  )
}

///|
fn wit_bind_function_type(
  bindings : WitBindings,
  instance : @component.ComponentInstance,
  path : String,
  expected : @component.ComponentFuncType,
) -> Unit raise WitBindingError {
  if bindings.functions.get(path) is Some(_) {
    raise DuplicateFunction(path)
  }
  let function = instance.bind_typed(path, expected) catch {
    error => raise RuntimeBindingFailed(error.to_string())
  }
  bindings.functions.set(path, function)
  bindings.ordered_paths.push(path)
}

///|
fn wit_bind_interface(
  result : @wit.ResolveResult,
  bindings : WitBindings,
  instance : @component.ComponentInstance,
  export_name : String,
  interface : @wit.Interface,
) -> Unit raise WitBindingError {
  let scope = wit_interface_scope(result, interface)
  for item in interface.items {
    match item {
      Func(declaration) =>
        wit_bind_function(
          bindings,
          instance,
          "\{export_name}#\{declaration.name}",
          declaration,
          scope,
        )
      Resource(resource) =>
        for resource_method in resource.methods {
          wit_bind_function_type(
            bindings,
            instance,
            "\{export_name}#\{resource_method.name}",
            wit_resource_method_type(resource, resource_method, scope),
          )
        }
      _ => ()
    }
  }
}

///|
fn wit_bind_inline_interface(
  result : @wit.ResolveResult,
  bindings : WitBindings,
  instance : @component.ComponentInstance,
  export_name : String,
  interface : @wit.InlineInterface,
) -> Unit raise WitBindingError {
  let materialized : @wit.Interface = {
    name: export_name,
    items: interface.items,
  }
  wit_bind_interface(result, bindings, instance, export_name, materialized)
}

///|
pub fn bind_world(
  result : @wit.ResolveResult,
  world_name : String,
  instance : @component.ComponentInstance,
) -> WitBindings raise WitBindingError {
  let mut selected : @wit.World? = None
  for item in result.root.items {
    if item is World(world) && world.name == world_name {
      selected = Some(world)
      break
    }
  }
  guard selected is Some(world) else { raise UnknownWorld(world_name) }
  let bindings : WitBindings = { functions: Map([]), ordered_paths: [], }
  let world_scope = wit_world_scope(result, world)
  for item in world.items {
    match item {
      ExportFunc(declaration) =>
        wit_bind_function(
          bindings,
          instance,
          declaration.name,
          declaration,
          world_scope,
        )
      ExportInlineInterface(name, interface) =>
        wit_bind_inline_interface(result, bindings, instance, name, interface)
      Export(path) =>
        wit_bind_interface(
          result,
          bindings,
          instance,
          path.raw,
          wit_find_interface(result, path.raw),
        )
      _ => ()
    }
  }
  bindings
}
