///|
/// Resolves one structural signature in its index space. Nested component
/// declarations shadow enclosing definitions at the same index.
priv struct TypeSigResolver {
  locals : (Array[@component.TypeDef], Array[Int32?])?
  global_types : Array[@component.TypeDef?]
  global_resource_ids : Array[Int32?]
  known_sigs : Map[Int32, TypeSig]?
  visiting : Map[Int32, Int32]
}

///|
fn TypeSigResolver::resolve(
  self : TypeSigResolver,
  ty : @component.ValType,
) -> TypeSig {
  match ty {
    Prim(p) => Prim(p)
    TypeIdx(idx) => {
      if self.known_sigs is Some(known) && known.get(idx) is Some(signature) {
        return signature
      }
      if idx < 0 || self.visiting.get(idx) is Some(_) {
        return Other
      }
      let definition = match self.locals {
        Some((types, _)) if idx < types.length() => Some(types[idx])
        _ => self.global_types.get(idx).bind(value => value)
      }
      guard definition is Some(definition) else { return Other }
      self.visiting.set(idx, 1)
      let signature = if definition is ResourceType(_, _, _, _) {
        let resource_id = match self.locals {
          Some((_, ids)) if idx < ids.length() => ids[idx]
          _ => self.global_resource_ids.get(idx).bind(value => value)
        }
        TypeSig::Resource(resource_id.unwrap_or(-1))
      } else {
        self.resolve_definition(definition)
      }
      ignore(self.visiting.remove(idx))
      signature
    }
  }
}

///|
fn TypeSigResolver::resolve_definition(
  self : TypeSigResolver,
  td : @component.TypeDef,
) -> TypeSig {
  match td {
    DefValType(p) => Prim(p)
    Tuple(types) => Tuple(types.map(ty => self.resolve(ty)))
    Record(fields) =>
      Record(
        fields.map(field => { name: field.label, ty: self.resolve(field.ty), }),
      )
    Variant(cases) =>
      Variant(
        cases.map(case_ => {
          name: case_.label,
          ty: case_.ty.map(ty => self.resolve(ty)),
        }),
      )
    Option(v) => Option(self.resolve(v))
    Result(ok, err) =>
      Result(ok.map(ty => self.resolve(ty)), err.map(ty => self.resolve(ty)))
    List(v) => List(self.resolve(v))
    Flags(labels) => Flags(labels)
    Enum(labels) => Enum(labels)
    Own(idx) => {
      let resource = self.resolve(TypeIdx(idx))
      match resource {
        Resource(rid) => Own(rid)
        _ => Other
      }
    }
    Borrow(idx) => {
      let resource = self.resolve(TypeIdx(idx))
      match resource {
        Resource(rid) => Borrow(rid)
        _ => Other
      }
    }
    _ => Other
  }
}

///|
fn TypeSigResolver::resolve_function(
  self : TypeSigResolver,
  ft : @component.FuncType,
) -> FuncSigShape {
  let params : Array[ParamShape] = []
  for p in ft.params {
    params.push({ name: p.label, ty: self.resolve(p.ty), })
  }
  { params, result: ft.result.map(ty => self.resolve(ty)), }
}

///|
fn funcsig_of_functype(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int32?],
  known_sigs~ : Map[Int32, TypeSig] = Map([]),
) -> FuncSigShape {
  let resolver : TypeSigResolver = {
    locals: None,
    global_types: type_table,
    global_resource_ids: resource_ids,
    known_sigs: Some(known_sigs),
    visiting: Map([]),
  }
  resolver.resolve_function(ft)
}

///|
fn funcsig_of_functype_lg(
  ft : @component.FuncType,
  local_types : Array[@component.TypeDef],
  local_resource_ids : Array[Int32?],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int32?],
) -> FuncSigShape {
  let resolver : TypeSigResolver = {
    locals: Some((local_types, local_resource_ids)),
    global_types,
    global_resource_ids,
    known_sigs: None,
    visiting: Map([]),
  }
  resolver.resolve_function(ft)
}

///|
fn type_sig_of_valtype_lg(
  ty : @component.ValType,
  local_types : Array[@component.TypeDef],
  local_resource_ids : Array[Int32?],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int32?],
  visiting : Map[Int32, Int32],
) -> TypeSig {
  let resolver : TypeSigResolver = {
    locals: Some((local_types, local_resource_ids)),
    global_types,
    global_resource_ids,
    known_sigs: None,
    visiting,
  }
  resolver.resolve(ty)
}

///|
fn type_sig_of_valtype(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int32?],
  visiting : Map[Int32, Int32],
  known_sigs~ : Map[Int32, TypeSig] = Map([]),
) -> TypeSig {
  let resolver : TypeSigResolver = {
    locals: None,
    global_types: type_table,
    global_resource_ids: resource_ids,
    known_sigs: Some(known_sigs),
    visiting,
  }
  resolver.resolve(ty)
}

///|
fn type_sig_of_typeidx(
  idx : Int32,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int32?],
  known_sigs~ : Map[Int32, TypeSig] = Map([]),
) -> TypeSig {
  type_sig_of_valtype(
    TypeIdx(idx),
    type_table,
    resource_ids,
    Map([]),
    known_sigs~,
  )
}
