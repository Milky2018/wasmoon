///|
/// Minimal WIT (WebAssembly Interface Types) text parser/printer used by `wasmoon-tools`.
///
/// This is intentionally an MVP: it targets the subset needed for basic inspection
/// and will be expanded incrementally towards wasm-tools parity.

///|
pub(all) suberror WitError {
  Error(String)
}

///|
fn WitError::to_string(self : WitError) -> String {
  match self {
    Error(msg) => msg
  }
}

///|
pub impl Show for WitError with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) enum TokenKind {
  Ident(String)
  IntLit(Int)
  StrLit(String)
  KwPackage
  KwInterface
  KwWorld
  KwUse
  KwAs
  KwWith
  KwInclude
  KwType
  KwFunc
  KwImport
  KwExport
  KwRecord
  KwResource
  KwEnum
  KwFlags
  KwVariant
  KwTuple
  KwList
  KwOption
  KwResult
  KwBorrow
  KwFuture
  KwStream
  KwAsync
  LBrace
  RBrace
  LParen
  RParen
  LAngle
  RAngle
  Colon
  Semi
  Comma
  Dot
  Slash
  At
  Dash
  Plus
  Eq
  Arrow
}

///|
priv struct Token {
  kind : TokenKind
  line : Int
  col : Int
}

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
pub fn parse_package(src : String) -> Package raise WitError {
  let lx = Lexer::new(src)
  let toks = lx.lex_all()
  let p = Parser::new(toks)
  p.parse_package()
}

///|
pub fn format_package(pkg : Package) -> String {
  let sb = StringBuilder::new()
  match pkg.name {
    Some(n) => {
      sb.write_string("package ")
      sb.write_string(n)
      match pkg.version {
        Some(v) => {
          sb.write_char('@')
          sb.write_string(v)
        }
        None => ()
      }
      sb.write_string(";\n\n")
    }
    None => ()
  }
  let mut first = true
  let mut prev_world = false
  for it in pkg.items {
    if !first {
      // wasm-tools does not insert an extra blank line between consecutive `world` items.
      let cur_world = match it {
        World(_) => true
        _ => false
      }
      if !(prev_world && cur_world) {
        sb.write_char('\n')
      }
      prev_world = cur_world
    } else {
      prev_world = match it {
        World(_) => true
        _ => false
      }
    }
    first = false
    match it {
      Interface(i) => format_interface(sb, i)
      World(w) => format_world(sb, w)
      ToplevelUse(u) => {
        sb.write_string("use ")
        sb.write_string(u.path.raw)
        match u.as_name {
          Some(n) => {
            sb.write_string(" as ")
            sb.write_string(n)
          }
          None => ()
        }
        sb.write_string(";\n")
      }
    }
  }
  if pkg.nested.length() > 0 {
    if pkg.items.length() > 0 {
      sb.write_char('\n')
    }
    for i in 0..<pkg.nested.length() {
      if i > 0 {
        sb.write_char('\n')
      }
      format_nested_package(sb, pkg.nested[i])
    }
  }
  sb.to_string()
}

///|
fn format_nested_package(sb : StringBuilder, pkg : Package) -> Unit {
  // Nested package notation: `package name@ver { ... }`
  let name = pkg.name.unwrap_or_else(fn() { "<unknown>" })
  sb.write_string("package ")
  sb.write_string(name)
  match pkg.version {
    Some(v) => {
      sb.write_char('@')
      sb.write_string(v)
    }
    None => ()
  }
  sb.write_string(" {\n")
  for it in pkg.items {
    let tmp = StringBuilder::new()
    match it {
      Interface(i) => format_interface(tmp, i)
      World(w) => format_world(tmp, w)
      ToplevelUse(u) => {
        tmp.write_string("use ")
        tmp.write_string(u.path.raw)
        match u.as_name {
          Some(n) => {
            tmp.write_string(" as ")
            tmp.write_string(n)
          }
          None => ()
        }
        tmp.write_string(";\n")
      }
    }
    sb.write_string(indent_lines(tmp.to_string(), "  "))
  }
  for np in pkg.nested {
    sb.write_char('\n')
    let tmp = StringBuilder::new()
    format_nested_package(tmp, np)
    sb.write_string(indent_lines(tmp.to_string(), "  "))
  }
  sb.write_string("}\n")
}

///|
fn indent_lines(s : String, prefix : String) -> String {
  let sb = StringBuilder::new()
  let mut at_line_start = true
  for c in s {
    if at_line_start {
      sb.write_string(prefix)
      at_line_start = false
    }
    sb.write_char(c)
    if c == '\n' {
      at_line_start = true
    }
  }
  sb.to_string()
}

///|
pub fn package_to_json(pkg : Package) -> String {
  // Small JSON emitter for CLI output; stable ordering.
  let sb = StringBuilder::new()
  sb.write_char('{')
  sb.write_string("\"name\":")
  match pkg.name {
    Some(n) => json_string(sb, n)
    None => sb.write_string("null")
  }
  sb.write_string(",\"version\":")
  match pkg.version {
    Some(v) => json_string(sb, v)
    None => sb.write_string("null")
  }
  sb.write_string(",\"nested\":[")
  for i in 0..<pkg.nested.length() {
    if i > 0 {
      sb.write_char(',')
    }
    sb.write_string(package_to_json(pkg.nested[i]))
  }
  sb.write_char(']')
  sb.write_string(",\"items\":[")
  for i in 0..<pkg.items.length() {
    if i > 0 {
      sb.write_char(',')
    }
    match pkg.items[i] {
      Interface(it) => {
        sb.write_string("{\"kind\":\"interface\",\"name\":")
        json_string(sb, it.name)
        sb.write_string(",\"items\":[")
        for j in 0..<it.items.length() {
          if j > 0 {
            sb.write_char(',')
          }
          match it.items[j] {
            Func(fd) => {
              sb.write_string("{\"kind\":\"func\",\"name\":")
              json_string(sb, fd.name)
              sb.write_string("}")
            }
            TypeAlias(td) => {
              sb.write_string("{\"kind\":\"type\",\"name\":")
              json_string(sb, td.name)
              sb.write_string("}")
            }
            Record(rd) => {
              sb.write_string("{\"kind\":\"record\",\"name\":")
              json_string(sb, rd.name)
              sb.write_string("}")
            }
            Use(u) => {
              sb.write_string("{\"kind\":\"use\",\"path\":")
              json_string(sb, u.path.raw)
              sb.write_string("}")
            }
            Resource(r) => {
              sb.write_string("{\"kind\":\"resource\",\"name\":")
              json_string(sb, r.name)
              sb.write_string("}")
            }
            Variant(v) => {
              sb.write_string("{\"kind\":\"variant\",\"name\":")
              json_string(sb, v.name)
              sb.write_string("}")
            }
            Flags(f) => {
              sb.write_string("{\"kind\":\"flags\",\"name\":")
              json_string(sb, f.name)
              sb.write_string("}")
            }
            Enum(e) => {
              sb.write_string("{\"kind\":\"enum\",\"name\":")
              json_string(sb, e.name)
              sb.write_string("}")
            }
          }
        }
        sb.write_string("]}")
      }
      World(w) => {
        sb.write_string("{\"kind\":\"world\",\"name\":")
        json_string(sb, w.name)
        sb.write_string(",\"items\":[")
        for j in 0..<w.items.length() {
          if j > 0 {
            sb.write_char(',')
          }
          match w.items[j] {
            Import(p) => {
              sb.write_string("{\"kind\":\"import\",\"path\":")
              json_string(sb, p.raw)
              sb.write_string("}")
            }
            Export(p) => {
              sb.write_string("{\"kind\":\"export\",\"path\":")
              json_string(sb, p.raw)
              sb.write_string("}")
            }
            ImportFunc(f) => {
              sb.write_string("{\"kind\":\"import-func\",\"name\":")
              json_string(sb, f.name)
              sb.write_string("}")
            }
            ExportFunc(f) => {
              sb.write_string("{\"kind\":\"export-func\",\"name\":")
              json_string(sb, f.name)
              sb.write_string("}")
            }
            ImportInlineInterface(nm, _) => {
              sb.write_string("{\"kind\":\"import-interface\",\"name\":")
              json_string(sb, nm)
              sb.write_string("}")
            }
            ExportInlineInterface(nm, _) => {
              sb.write_string("{\"kind\":\"export-interface\",\"name\":")
              json_string(sb, nm)
              sb.write_string("}")
            }
            Include(inc) => {
              sb.write_string("{\"kind\":\"include\",\"path\":")
              json_string(sb, inc.path.raw)
              sb.write_string("}")
            }
            Use(u) => {
              sb.write_string("{\"kind\":\"use\",\"path\":")
              json_string(sb, u.path.raw)
              sb.write_string("}")
            }
            TypeAlias(td) => {
              sb.write_string("{\"kind\":\"type\",\"name\":")
              json_string(sb, td.name)
              sb.write_string("}")
            }
            Record(rd) => {
              sb.write_string("{\"kind\":\"record\",\"name\":")
              json_string(sb, rd.name)
              sb.write_string("}")
            }
            Resource(r) => {
              sb.write_string("{\"kind\":\"resource\",\"name\":")
              json_string(sb, r.name)
              sb.write_string("}")
            }
            Variant(v) => {
              sb.write_string("{\"kind\":\"variant\",\"name\":")
              json_string(sb, v.name)
              sb.write_string("}")
            }
            Flags(f) => {
              sb.write_string("{\"kind\":\"flags\",\"name\":")
              json_string(sb, f.name)
              sb.write_string("}")
            }
            Enum(e) => {
              sb.write_string("{\"kind\":\"enum\",\"name\":")
              json_string(sb, e.name)
              sb.write_string("}")
            }
          }
        }
        sb.write_string("]}")
      }
      ToplevelUse(u) => {
        sb.write_string("{\"kind\":\"use\",\"path\":")
        json_string(sb, u.path.raw)
        sb.write_string(",\"as\":")
        match u.as_name {
          Some(n) => json_string(sb, n)
          None => sb.write_string("null")
        }
        sb.write_string("}")
      }
    }
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
pub(all) struct ResolveResult {
  root : Package
  deps : Array[Package]
}

///|
/// Apply file-scoped `toplevel-use` aliases to all paths within this document and
/// remove all `toplevel-use` items. This matches wasm-tools behavior where the
/// resolved output does not contain `toplevel-use` directives.
pub fn desugar_toplevel_use(doc : Package) -> Package raise WitError {
  let aliases = collect_toplevel_aliases(doc)
  let items : Array[TopItem] = []
  for it in doc.items {
    match it {
      ToplevelUse(_) => ()
      Interface(i) =>
        items.push(Interface(desugar_interface_aliases(i, aliases)))
      World(w) => items.push(World(desugar_world_aliases(w, aliases)))
    }
  }
  let nested : Array[Package] = []
  for p in doc.nested {
    nested.push(desugar_toplevel_use(p))
  }
  { name: doc.name, version: doc.version, items, nested }
}

///|
/// Merge multiple WIT documents (e.g. all `*.wit` files in a directory) into one package.
/// Note: for correct `toplevel-use` scoping, each document is desugared individually first.
pub fn merge_package_files(docs : Array[Package]) -> Package raise WitError {
  let mut merged : Package? = None
  for d in docs {
    let dd = desugar_toplevel_use(d)
    merged = Some(merge_packages(merged, dd))
  }
  merged.unwrap_or({ name: None, version: None, items: [], nested: [] })
}

///|
/// Parse+resolve a root package against a flat list of dependency packages, producing:
/// - `root`: the resolved root package (no nested packages)
/// - `deps`: all other resolved packages (no nested packages), in topological order.
///
/// The default CLI output can inline `deps` into `root.nested`.
pub fn resolve_package(
  root : Package,
  deps : Array[Package],
) -> ResolveResult raise WitError {
  let root_doc = desugar_toplevel_use(root)
  if root_doc.name is None {
    raise WitError::Error(
      "no `package` header was found in any WIT file for this package",
    )
  }
  let pkgs : Map[String, Package] = {}
  add_pkg_recursive_strict(pkgs, root_doc)
  for d in deps {
    add_pkg_recursive_strict(pkgs, desugar_toplevel_use(d))
  }
  let order = topo_sort_packages(pkgs)

  // Global interface dependency information for world transitive-import computation.
  let iface_type_exports : Map[String, Map[String, Bool]] = {} // iface_key -> exported type/resource names
  let iface_deps : Map[String, Array[IfaceRef]] = {} // iface_key -> direct interface deps
  let resolved_pkgs : Map[String, Package] = {}
  let resolved_worlds : Map[String, World] = {} // world_key -> resolved world
  for key in order {
    let pkg = pkgs
      .get(key)
      .unwrap_or_else(fn() {
        raise WitError::Error("internal: missing package `" + key + "`")
      })
    let (pkg_out, worlds_out) = resolve_one_package(
      key, pkg, pkgs, iface_type_exports, iface_deps, resolved_worlds,
    )
    resolved_pkgs.set(key, pkg_out)
    for pair in worlds_out {
      let (wk, wv) = pair
      resolved_worlds.set(wk, wv)
    }
  }
  let root_key = package_key(root_doc)
  let root_pkg = resolved_pkgs
    .get(root_key)
    .unwrap_or_else(fn() {
      raise WitError::Error("internal: missing resolved root package")
    })
  let out_deps : Array[Package] = []
  for k in order {
    if k != root_key {
      out_deps.push(
        resolved_pkgs
        .get(k)
        .unwrap_or_else(fn() {
          raise WitError::Error(
            "internal: missing resolved package `" + k + "`",
          )
        }),
      )
    }
  }
  { root: root_pkg, deps: out_deps }
}

///|
priv struct IfaceRef {
  pkg_key : String
  name : String
}

///|
fn iface_key(r : IfaceRef) -> String {
  r.pkg_key + "/" + r.name
}

///|
fn add_pkg_recursive_strict(
  pkgs : Map[String, Package],
  pkg : Package,
) -> Unit raise WitError {
  if pkg.name is None {
    raise WitError::Error(
      "dependency package missing `package ...;` declaration",
    )
  }
  let key = package_key(pkg)
  match pkgs.get(key) {
    Some(_) => ()
    None => pkgs.set(key, pkg)
  }
  for n in pkg.nested {
    add_pkg_recursive_strict(pkgs, n)
  }
}

///|
fn package_key(pkg : Package) -> String raise WitError {
  match pkg.name {
    Some(n) =>
      match pkg.version {
        Some(v) => n + "@" + v
        None => n
      }
    None => raise WitError::Error("package missing name")
  }
}

///|
fn topo_sort_packages(
  pkgs : Map[String, Package],
) -> Array[String] raise WitError {
  let keys : Array[String] = []
  for kv in pkgs {
    let (k, _) = kv
    keys.push(k)
  }
  keys.sort()
  let deps_map : Map[String, Array[String]] = {}
  for k in keys {
    let pkg = pkgs
      .get(k)
      .unwrap_or_else(fn() {
        raise WitError::Error("internal: missing package `" + k + "`")
      })
    deps_map.set(k, collect_package_deps(k, pkg))
  }
  topo_sort_graph(keys, deps_map, fn(k) {
    "cycle in package deps involving `" + k + "`"
  })
}

///|
fn collect_package_deps(pkg_key : String, pkg : Package) -> Array[String] {
  let set : Map[String, Bool] = {}
  for it in pkg.items {
    match it {
      Interface(i) =>
        for item in i.items {
          collect_pkg_deps_from_interface_item(pkg_key, item, set)
        }
      World(w) =>
        for item in w.items {
          collect_pkg_deps_from_world_item(pkg_key, item, set)
        }
      ToplevelUse(u) =>
        match split_use_path(u.path) {
          (Some(k), _, _) => if k != pkg_key { set.set(k, true) }
          _ => ()
        }
    }
  }
  let out : Array[String] = []
  for kv in set {
    let (k, _) = kv
    out.push(k)
  }
  out.sort()
  out
}

///|
fn collect_pkg_deps_from_interface_item(
  pkg_key : String,
  item : InterfaceItem,
  out : Map[String, Bool],
) -> Unit {
  match item {
    Use(u) =>
      match split_use_path(u.path) {
        (Some(k), _, _) => if k != pkg_key { out.set(k, true) }
        _ => ()
      }
    _ => ()
  }
}

///|
fn collect_pkg_deps_from_world_item(
  pkg_key : String,
  item : WorldItem,
  out : Map[String, Bool],
) -> Unit {
  match item {
    Import(p) | Export(p) =>
      match split_use_path(p) {
        (Some(k), _, _) => if k != pkg_key { out.set(k, true) }
        _ => ()
      }
    Include(inc) =>
      match split_use_path(inc.path) {
        (Some(k), _, _) => if k != pkg_key { out.set(k, true) }
        _ => ()
      }
    Use(u) =>
      match split_use_path(u.path) {
        (Some(k), _, _) => if k != pkg_key { out.set(k, true) }
        _ => ()
      }
    ImportInlineInterface(_, iface) | ExportInlineInterface(_, iface) =>
      for ii in iface.items {
        collect_pkg_deps_from_interface_item(pkg_key, ii, out)
      }
    _ => ()
  }
}

///|
fn topo_sort_graph(
  keys : Array[String],
  deps_map : Map[String, Array[String]],
  cycle_msg : (String) -> String,
) -> Array[String] raise WitError {
  let state : Map[String, Int] = {} // 0=unseen,1=visiting,2=done
  let out : Array[String] = []
  fn dfs(k : String) -> Unit raise WitError {
    let st = state.get(k).unwrap_or(0)
    if st == 2 {
      return
    }
    if st == 1 {
      raise WitError::Error(cycle_msg(k))
    }
    state.set(k, 1)
    let ds = deps_map.get(k).unwrap_or([])
    for dep in ds {
      if deps_map.get(dep) is Some(_) {
        dfs(dep)
      }
    }
    state.set(k, 2)
    out.push(k)
  }

  for k in keys {
    if state.get(k).unwrap_or(0) == 0 {
      dfs(k)
    }
  }
  out
}

///|
fn resolve_one_package(
  pkg_key : String,
  pkg : Package,
  pkgs : Map[String, Package],
  iface_type_exports : Map[String, Map[String, Bool]],
  iface_deps : Map[String, Array[IfaceRef]],
  resolved_worlds : Map[String, World],
) -> (Package, Array[(String, World)]) raise WitError {
  // Collect local interface/world definitions and check duplicates.
  let ifaces : Map[String, Interface] = {}
  let worlds : Map[String, World] = {}
  for it in pkg.items {
    match it {
      Interface(i) =>
        if ifaces.get(i.name) is Some(_) {
          raise WitError::Error(
            "duplicate interface `" + i.name + "` in package `" + pkg_key + "`",
          )
        } else {
          ifaces.set(i.name, i)
        }
      World(w) =>
        if worlds.get(w.name) is Some(_) {
          raise WitError::Error(
            "duplicate world `" + w.name + "` in package `" + pkg_key + "`",
          )
        } else {
          worlds.set(w.name, w)
        }
      ToplevelUse(_) => () // removed by desugaring
    }
  }

  // Topo-sort interfaces based on local `use` edges.
  let iface_names : Array[String] = []
  for kv in ifaces {
    let (n, _) = kv
    iface_names.push(n)
  }
  iface_names.sort()
  let iface_edges : Map[String, Array[String]] = {}
  let iface_direct_deps : Map[String, Array[IfaceRef]] = {}
  for n in iface_names {
    let iface = ifaces
      .get(n)
      .unwrap_or_else(fn() {
        raise WitError::Error("internal: missing interface")
      })
    let local_edges : Array[String] = []
    let deps_arr : Array[IfaceRef] = []
    for item in iface.items {
      match item {
        Use(u) => {
          let dep = use_path_to_iface_ref(pkg_key, u.path)
          deps_arr.push(dep)
          if dep.pkg_key == pkg_key {
            local_edges.push(dep.name)
          }
        }
        _ => ()
      }
    }
    local_edges.sort()
    iface_edges.set(n, local_edges)
    iface_direct_deps.set(n, deps_arr)
  }
  let iface_order = topo_sort_graph(iface_names, iface_edges, fn(k) {
    "cycle in interface `use` involving `" + k + "`"
  })

  // Resolve interfaces in topo order.
  let resolved_ifaces : Map[String, Interface] = {}
  for name in iface_order {
    let iface = ifaces
      .get(name)
      .unwrap_or_else(fn() {
        raise WitError::Error("internal: missing interface")
      })
    let (type_exports, deps_arr) = resolve_interface_in_package(
      pkg_key, iface, pkgs, iface_type_exports,
    )
    iface_type_exports.set(iface_key({ pkg_key, name }), type_exports)
    iface_deps.set(iface_key({ pkg_key, name }), deps_arr)
    resolved_ifaces.set(name, iface)
  }

  // Topo-sort worlds based on local `include` edges.
  let world_names : Array[String] = []
  for kv in worlds {
    let (n, _) = kv
    world_names.push(n)
  }
  world_names.sort()
  let world_edges : Map[String, Array[String]] = {}
  for n in world_names {
    let w = worlds
      .get(n)
      .unwrap_or_else(fn() { raise WitError::Error("internal: missing world") })
    let edges : Array[String] = []
    for wi in w.items {
      match wi {
        Include(inc) =>
          match split_use_path(inc.path) {
            (None, wn, _) => edges.push(wn)
            _ => ()
          }
        _ => ()
      }
    }
    edges.sort()
    world_edges.set(n, edges)
  }
  let world_order = topo_sort_graph(world_names, world_edges, fn(k) {
    "cycle in world `include` involving `" + k + "`"
  })

  // Resolve worlds in topo order so local `include` targets are already resolved.
  let local_resolved_worlds : Map[String, World] = {}
  let worlds_out : Array[(String, World)] = []
  for wn in world_order {
    let w = worlds
      .get(wn)
      .unwrap_or_else(fn() { raise WitError::Error("internal: missing world") })
    let rw = resolve_world_in_package(
      pkg_key, w, pkgs, worlds, iface_type_exports, iface_deps, resolved_worlds,
      local_resolved_worlds,
    )
    local_resolved_worlds.set(wn, rw)
    worlds_out.push((pkg_key + "/" + wn, rw))
  }
  let out_items : Array[TopItem] = []
  for n in iface_order {
    out_items.push(
      Interface(
        resolved_ifaces
        .get(n)
        .unwrap_or_else(fn() {
          raise WitError::Error("internal: missing resolved interface")
        }),
      ),
    )
  }
  for n in world_order {
    out_items.push(
      World(
        local_resolved_worlds
        .get(n)
        .unwrap_or_else(fn() {
          raise WitError::Error("internal: missing resolved world")
        }),
      ),
    )
  }
  let out_pkg : Package = {
    name: pkg.name,
    version: pkg.version,
    items: out_items,
    nested: [],
  }
  (out_pkg, worlds_out)
}

///|
fn resolve_interface_in_package(
  pkg_key : String,
  iface : Interface,
  pkgs : Map[String, Package],
  iface_type_exports : Map[String, Map[String, Bool]],
) -> (Map[String, Bool], Array[IfaceRef]) raise WitError {
  let names : Map[String, Bool] = {}
  let type_exports : Map[String, Bool] = {}

  // First pass: local defs + funcs occupy the interface namespace.
  for item in iface.items {
    match item {
      Func(f) =>
        if names.get(f.name) is Some(_) {
          raise WitError::Error(
            "duplicate name `" + f.name + "` in interface `" + iface.name + "`",
          )
        } else {
          names.set(f.name, true)
        }
      TypeAlias(t) => add_type_name(names, type_exports, t.name, iface.name)
      Record(r) => add_type_name(names, type_exports, r.name, iface.name)
      Resource(r) => add_type_name(names, type_exports, r.name, iface.name)
      Variant(v) => add_type_name(names, type_exports, v.name, iface.name)
      Flags(f) => add_type_name(names, type_exports, f.name, iface.name)
      Enum(e) => add_type_name(names, type_exports, e.name, iface.name)
      _ => ()
    }
  }

  // Second pass: `use` imports types/resources into the interface namespace.
  let deps_arr : Array[IfaceRef] = []
  for item in iface.items {
    match item {
      Use(u) => {
        let target = use_path_to_iface_ref(pkg_key, u.path)
        deps_arr.push(target)
        let exports = get_iface_type_exports(target, pkgs, iface_type_exports)
        for pair in u.names {
          let (n, asn) = pair
          if exports.get(n) is None {
            raise WitError::Error(
              "unknown name `" + n + "` in use " + u.path.raw,
            )
          }
          let local_name = match asn {
            Some(x) => x
            None => n
          }
          if names.get(local_name) is Some(_) {
            raise WitError::Error(
              "duplicate name `" +
              local_name +
              "` in interface `" +
              iface.name +
              "`",
            )
          }
          names.set(local_name, true)
          type_exports.set(local_name, true)
        }
      }
      _ => ()
    }
  }

  // Validate type references.
  for item in iface.items {
    match item {
      TypeAlias(t) => validate_type_expr(type_exports, t.ty)
      Record(r) =>
        for field in r.fields {
          validate_type_expr(type_exports, field.1)
        }
      Variant(v) =>
        for c in v.cases {
          if c.payload is Some(t) {
            validate_type_expr(type_exports, t)
          }
        }
      Resource(r) =>
        for m in r.methods {
          validate_func_sig(type_exports, m)
        }
      Func(f) => validate_func_sig(type_exports, f)
      _ => ()
    }
  }

  // Validate non-recursive local type definitions.
  check_interface_type_cycles(type_exports, iface)
  (type_exports, deps_arr)
}

///|
fn add_type_name(
  ns : Map[String, Bool],
  types : Map[String, Bool],
  name : String,
  iface_name : String,
) -> Unit raise WitError {
  if ns.get(name) is Some(_) {
    raise WitError::Error(
      "duplicate name `" + name + "` in interface `" + iface_name + "`",
    )
  }
  ns.set(name, true)
  types.set(name, true)
}

///|
fn get_iface_type_exports(
  target : IfaceRef,
  pkgs : Map[String, Package],
  iface_type_exports : Map[String, Map[String, Bool]],
) -> Map[String, Bool] raise WitError {
  // Validate that the target interface exists and is resolved.
  let pkg = pkgs
    .get(target.pkg_key)
    .unwrap_or_else(fn() {
      raise WitError::Error("unknown package `" + target.pkg_key + "`")
    })
  let mut found = false
  for it in pkg.items {
    match it {
      Interface(i) => if i.name == target.name { found = true }
      _ => ()
    }
  }
  if !found {
    raise WitError::Error(
      "unknown interface `" +
      target.name +
      "` in package `" +
      target.pkg_key +
      "`",
    )
  }
  let key = iface_key(target)
  match iface_type_exports.get(key) {
    Some(m) => m
    None =>
      raise WitError::Error(
        "internal: interface `" + target.name + "` not resolved yet",
      )
  }
}

///|
fn use_path_to_iface_ref(cur_pkg_key : String, path : UsePath) -> IfaceRef {
  match split_use_path(path) {
    (None, name, _) => { pkg_key: cur_pkg_key, name }
    (Some(k), name, _) => { pkg_key: k, name }
  }
}

///|
fn validate_func_sig(
  visible_types : Map[String, Bool],
  f : FuncDecl,
) -> Unit raise WitError {
  for p in f.params {
    validate_type_expr(visible_types, p.1)
  }
  for r in f.results {
    validate_type_expr(visible_types, r.1)
  }
}

///|
fn validate_type_expr(
  visible_types : Map[String, Bool],
  t : TypeExpr,
) -> Unit raise WitError {
  match t {
    Id(n) =>
      if is_builtin_type(n) || visible_types.get(n) is Some(_) {
        ()
      } else {
        raise WitError::Error("unknown type `" + n + "`")
      }
    Apply(name, args) => {
      if !is_builtin_ctor(name) {
        raise WitError::Error("unknown type constructor `" + name + "`")
      }
      for a in args {
        validate_type_expr(visible_types, a)
      }
    }
    Record(fields) =>
      for field in fields {
        validate_type_expr(visible_types, field.1)
      }
  }
}

///|
fn is_builtin_type(n : String) -> Bool {
  n == "_" ||
  n == "u8" ||
  n == "u16" ||
  n == "u32" ||
  n == "u64" ||
  n == "s8" ||
  n == "s16" ||
  n == "s32" ||
  n == "s64" ||
  n == "f32" ||
  n == "f64" ||
  n == "char" ||
  n == "bool" ||
  n == "string"
}

///|
fn is_builtin_ctor(n : String) -> Bool {
  n == "tuple" ||
  n == "list" ||
  n == "option" ||
  n == "result" ||
  n == "borrow" ||
  n == "future" ||
  n == "stream"
}

///|
fn check_interface_type_cycles(
  visible_types : Map[String, Bool],
  iface : Interface,
) -> Unit raise WitError {
  // Only consider locally-defined names for cycle detection.
  let locals : Map[String, Bool] = {}
  for item in iface.items {
    match item {
      TypeAlias(t) => locals.set(t.name, true)
      Record(r) => locals.set(r.name, true)
      Variant(v) => locals.set(v.name, true)
      Flags(f) => locals.set(f.name, true)
      Enum(e) => locals.set(e.name, true)
      Resource(r) => locals.set(r.name, true)
      _ => ()
    }
  }
  let edges : Map[String, Array[String]] = {}
  for kv in locals {
    let (n, _) = kv
    edges.set(n, [])
  }
  for item in iface.items {
    match item {
      TypeAlias(t) => edges.set(t.name, type_deps_in_expr(locals, t.ty))
      Record(r) => {
        let ds : Map[String, Bool] = {}
        for f in r.fields {
          for dep in type_deps_in_expr(locals, f.1) {
            ds.set(dep, true)
          }
        }
        edges.set(r.name, map_keys(ds))
      }
      Variant(v) => {
        let ds : Map[String, Bool] = {}
        for c in v.cases {
          if c.payload is Some(t) {
            for dep in type_deps_in_expr(locals, t) {
              ds.set(dep, true)
            }
          }
        }
        edges.set(v.name, map_keys(ds))
      }
      _ => ()
    }
  }
  let names = map_keys(locals)
  topo_sort_graph(names, edges, fn(k) {
    "recursive type definition involving `" +
    k +
    "` in interface `" +
    iface.name +
    "`"
  })
  |> ignore
  visible_types |> ignore
}

///|
fn type_deps_in_expr(locals : Map[String, Bool], t : TypeExpr) -> Array[String] {
  let ds : Map[String, Bool] = {}
  fn walk(tt : TypeExpr) -> Unit {
    match tt {
      Id(n) => if locals.get(n) is Some(_) { ds.set(n, true) }
      Apply(_, args) =>
        for a in args {
          walk(a)
        }
      Record(fields) =>
        for f in fields {
          walk(f.1)
        }
    }
  }

  walk(t)
  map_keys(ds)
}

///|
fn map_keys(m : Map[String, Bool]) -> Array[String] {
  let out : Array[String] = []
  for kv in m {
    let (k, _) = kv
    out.push(k)
  }
  out.sort()
  out
}

///|
fn resolve_world_in_package(
  pkg_key : String,
  world : World,
  pkgs : Map[String, Package],
  local_worlds : Map[String, World],
  iface_type_exports : Map[String, Map[String, Bool]],
  iface_deps : Map[String, Array[IfaceRef]],
  resolved_worlds : Map[String, World],
  local_resolved_worlds : Map[String, World],
) -> World raise WitError {
  // 1) Expand includes.
  let mut items : Array[WorldItem] = []
  for wi in world.items {
    match wi {
      Include(inc) => {
        let included = resolve_world_ref(
          pkg_key,
          inc.path,
          local_worlds,
          pkgs,
          resolved_worlds,
          local_resolved_worlds,
        )
        let mut inc_items = included.items
        match inc.renames {
          Some(rs) => inc_items = apply_include_renames(inc_items, rs)
          None => ()
        }
        items = merge_world_items(items, inc_items)
      }
      _ => items.push(wi)
    }
  }

  // 2) Validate world-level `use` against target interface exports.
  // Also track required interfaces for transitive imports.
  let required : Map[String, IfaceRef] = {}
  for wi in items {
    match wi {
      Import(p) => {
        let r = use_path_to_iface_ref(pkg_key, p)
        validate_iface_exists(r, pkgs, iface_type_exports)
        required.set(iface_key(r), r)
      }
      Export(p) => {
        let r = use_path_to_iface_ref(pkg_key, p)
        validate_iface_exists(r, pkgs, iface_type_exports)
        required.set(iface_key(r), r)
      }
      Use(u) => {
        let r = use_path_to_iface_ref(pkg_key, u.path)
        let exports = get_iface_type_exports(r, pkgs, iface_type_exports)
        for pair in u.names {
          let (n, _) = pair
          if exports.get(n) is None {
            raise WitError::Error(
              "unknown name `" + n + "` in use " + u.path.raw,
            )
          }
        }
        required.set(iface_key(r), r)
      }
      ImportInlineInterface(_, iface) | ExportInlineInterface(_, iface) => {
        for ii in iface.items {
          match ii {
            Use(u) => {
              let r = use_path_to_iface_ref(pkg_key, u.path)
              let exports = get_iface_type_exports(r, pkgs, iface_type_exports)
              for pair in u.names {
                let (n, _) = pair
                if exports.get(n) is None {
                  raise WitError::Error(
                    "unknown name `" + n + "` in use " + u.path.raw,
                  )
                }
              }
              required.set(iface_key(r), r)
            }
            _ => ()
          }
        }
        validate_inline_interface_types(
          iface, iface_type_exports, pkgs, pkg_key,
        )
      }
      ImportFunc(f) | ExportFunc(f) =>
        // World-level function signatures can refer to world-defined types; validate later.
        f |> ignore
      _ => ()
    }
  }

  // 3) Add transitive interface imports implied by `use`.
  let existing_imports : Map[String, IfaceRef] = {}
  let existing_exports : Map[String, IfaceRef] = {}
  for wi in items {
    match wi {
      Import(p) => {
        let r = use_path_to_iface_ref(pkg_key, p)
        existing_imports.set(iface_key(r), r)
      }
      Export(p) => {
        let r = use_path_to_iface_ref(pkg_key, p)
        existing_exports.set(iface_key(r), r)
      }
      _ => ()
    }
  }
  let closure = compute_iface_closure(required, iface_deps)
  for kv in closure {
    let (k, r) = kv
    if existing_imports.get(k) is None && existing_exports.get(k) is None {
      existing_imports.set(k, r)
    }
  }

  // Sort interface imports so dependencies appear first.
  let import_list = topo_sort_ifaces(existing_imports, iface_deps)

  // Rebuild world items with new interface imports at the front.
  let rebuilt : Array[WorldItem] = []
  for r in import_list {
    rebuilt.push(Import({ raw: iface_ref_to_use_path(pkg_key, r) }))
  }
  // Keep non-interface-import items in original order, skipping old interface imports.
  for wi in items {
    match wi {
      Import(_) => () // replaced
      _ => rebuilt.push(wi)
    }
  }
  // Validate world-local type definitions and world-level function signatures.
  validate_world_types(world.name, rebuilt, pkg_key, iface_type_exports, pkgs)
  |> ignore
  { name: world.name, items: rebuilt }
}

///|
fn resolve_world_ref(
  cur_pkg_key : String,
  path : UsePath,
  local_worlds : Map[String, World],
  pkgs : Map[String, Package],
  resolved_worlds : Map[String, World],
  local_resolved_worlds : Map[String, World],
) -> World raise WitError {
  cur_pkg_key |> ignore
  match split_use_path(path) {
    (None, name, _) =>
      match local_resolved_worlds.get(name) {
        Some(w) => w
        None =>
          match local_worlds.get(name) {
            Some(_) =>
              raise WitError::Error(
                "internal: world `" + name + "` not resolved yet",
              )
            None =>
              raise WitError::Error("unknown world `" + name + "` in include")
          }
      }
    (Some(pkg_key), name, _) => {
      pkgs
      .get(pkg_key)
      .unwrap_or_else(fn() {
        raise WitError::Error("unknown package `" + pkg_key + "`")
      })
      |> ignore
      let k = pkg_key + "/" + name
      resolved_worlds
      .get(k)
      .unwrap_or_else(fn() {
        raise WitError::Error(
          "unknown world `" + name + "` in package `" + pkg_key + "`",
        )
      })
    }
  }
}

///|
fn apply_include_renames(
  items : Array[WorldItem],
  renames : Array[(String, String)],
) -> Array[WorldItem] raise WitError {
  let map : Map[String, String] = {}
  for pair in renames {
    let (from, to) = pair
    map.set(from, to)
  }
  // Ensure all renames match a renamable item.
  for pair in renames {
    let (from, _) = pair
    let mut found = false
    for wi in items {
      match wi {
        ImportFunc(f) => if f.name == from { found = true }
        ExportFunc(f) => if f.name == from { found = true }
        ImportInlineInterface(nm, _) => if nm == from { found = true }
        ExportInlineInterface(nm, _) => if nm == from { found = true }
        _ => ()
      }
    }
    if !found {
      raise WitError::Error("no import or export kebab-name `" + from + "`")
    }
  }
  let out : Array[WorldItem] = []
  for wi in items {
    match wi {
      ImportFunc(f) =>
        match map.get(f.name) {
          Some(nm) =>
            out.push(
              ImportFunc({
                name: nm,
                is_async: f.is_async,
                params: f.params,
                results: f.results,
              }),
            )
          None => out.push(wi)
        }
      ExportFunc(f) =>
        match map.get(f.name) {
          Some(nm) =>
            out.push(
              ExportFunc({
                name: nm,
                is_async: f.is_async,
                params: f.params,
                results: f.results,
              }),
            )
          None => out.push(wi)
        }
      ImportInlineInterface(nm, iface) =>
        match map.get(nm) {
          Some(nn) => out.push(ImportInlineInterface(nn, iface))
          None => out.push(wi)
        }
      ExportInlineInterface(nm, iface) =>
        match map.get(nm) {
          Some(nn) => out.push(ExportInlineInterface(nn, iface))
          None => out.push(wi)
        }
      _ => out.push(wi)
    }
  }
  out
}

///|
fn merge_world_items(
  a : Array[WorldItem],
  b : Array[WorldItem],
) -> Array[WorldItem] {
  let seen : Map[String, Bool] = {}
  let out : Array[WorldItem] = []
  for wi in a {
    let k = world_item_key(wi)
    if k != "" {
      seen.set(k, true)
    }
    out.push(wi)
  }
  for wi in b {
    let k = world_item_key(wi)
    if k == "" || seen.get(k) is None {
      if k != "" {
        seen.set(k, true)
      }
      out.push(wi)
    }
  }
  out
}

///|
fn world_item_key(wi : WorldItem) -> String {
  match wi {
    Import(p) => "import:" + p.raw
    Export(p) => "export:" + p.raw
    ImportFunc(f) => "import-func:" + f.name
    ExportFunc(f) => "export-func:" + f.name
    ImportInlineInterface(nm, _) => "import-iface:" + nm
    ExportInlineInterface(nm, _) => "export-iface:" + nm
    TypeAlias(t) => "type:" + t.name
    Record(r) => "record:" + r.name
    Resource(r) => "resource:" + r.name
    Variant(v) => "variant:" + v.name
    Flags(f) => "flags:" + f.name
    Enum(e) => "enum:" + e.name
    _ => ""
  }
}

///|
fn validate_iface_exists(
  r : IfaceRef,
  pkgs : Map[String, Package],
  iface_type_exports : Map[String, Map[String, Bool]],
) -> Unit raise WitError {
  let pkg = pkgs
    .get(r.pkg_key)
    .unwrap_or_else(fn() {
      raise WitError::Error("unknown package `" + r.pkg_key + "`")
    })
  // Ensure the interface name exists in the parsed package even if it has no exports.
  let mut found = false
  for it in pkg.items {
    match it {
      Interface(i) => if i.name == r.name { found = true }
      _ => ()
    }
  }
  if !found {
    raise WitError::Error(
      "unknown interface `" + r.name + "` in package `" + r.pkg_key + "`",
    )
  }
  // Ensure export info exists.
  if iface_type_exports.get(iface_key(r)) is None {
    raise WitError::Error(
      "unknown interface `" + r.name + "` in package `" + r.pkg_key + "`",
    )
  }
}

///|
fn compute_iface_closure(
  roots : Map[String, IfaceRef],
  iface_deps : Map[String, Array[IfaceRef]],
) -> Map[String, IfaceRef] raise WitError {
  let out : Map[String, IfaceRef] = {}
  let state : Map[String, Int] = {} // 0=unseen,1=visiting,2=done
  fn dfs(k : String, r : IfaceRef) -> Unit raise WitError {
    let st = state.get(k).unwrap_or(0)
    if st == 2 {
      return
    }
    if st == 1 {
      raise WitError::Error(
        "cycle in transitive interface dependencies involving `" + k + "`",
      )
    }
    state.set(k, 1)
    out.set(k, r)
    let deps = iface_deps.get(k).unwrap_or([])
    for d in deps {
      let dk = iface_key(d)
      dfs(dk, d)
    }
    state.set(k, 2)
  }

  for kv in roots {
    let (k, r) = kv
    dfs(k, r)
  }
  out
}

///|
fn topo_sort_ifaces(
  ifaces : Map[String, IfaceRef],
  iface_deps : Map[String, Array[IfaceRef]],
) -> Array[IfaceRef] raise WitError {
  let keys : Array[String] = []
  for kv in ifaces {
    let (k, _) = kv
    keys.push(k)
  }
  keys.sort()
  let deps_map : Map[String, Array[String]] = {}
  for k in keys {
    let ds : Array[String] = []
    for d in iface_deps.get(k).unwrap_or([]) {
      let dk = iface_key(d)
      if ifaces.get(dk) is Some(_) {
        ds.push(dk)
      }
    }
    deps_map.set(k, ds)
  }
  let sorted_keys = topo_sort_graph(keys, deps_map, fn(k) {
    "cycle in world interface imports involving `" + k + "`"
  })
  let out : Array[IfaceRef] = []
  for k in sorted_keys {
    out.push(
      ifaces
      .get(k)
      .unwrap_or_else(fn() {
        raise WitError::Error("internal: missing iface ref")
      }),
    )
  }
  out
}

///|
fn iface_ref_to_use_path(cur_pkg_key : String, r : IfaceRef) -> String {
  if r.pkg_key == cur_pkg_key {
    return r.name
  }
  // Convert `pkg_key` back to `pkg_name@ver` split.
  match find_last_code_unit(r.pkg_key, 64) {
    Some(i) => {
      let pkg_name = slice_ascii(r.pkg_key, 0, i)
      let ver = slice_ascii(r.pkg_key, i + 1, r.pkg_key.length())
      pkg_name + "/" + r.name + "@" + ver
    }
    None => r.pkg_key + "/" + r.name
  }
}

///|
fn validate_inline_interface_types(
  iface : InlineInterface,
  iface_type_exports : Map[String, Map[String, Bool]],
  pkgs : Map[String, Package],
  pkg_key : String,
) -> Unit raise WitError {
  // Inline interfaces are validated like normal interfaces, but they don't participate in re-export.
  let ns : Map[String, Bool] = {}
  let visible : Map[String, Bool] = {}
  for item in iface.items {
    match item {
      Func(f) => ns.set(f.name, true)
      TypeAlias(t) => {
        ns.set(t.name, true)
        visible.set(t.name, true)
      }
      Record(r) => {
        ns.set(r.name, true)
        visible.set(r.name, true)
      }
      Resource(r) => {
        ns.set(r.name, true)
        visible.set(r.name, true)
      }
      Variant(v) => {
        ns.set(v.name, true)
        visible.set(v.name, true)
      }
      Flags(f) => {
        ns.set(f.name, true)
        visible.set(f.name, true)
      }
      Enum(e) => {
        ns.set(e.name, true)
        visible.set(e.name, true)
      }
      _ => ()
    }
  }
  for item in iface.items {
    match item {
      Use(u) => {
        let r = use_path_to_iface_ref(pkg_key, u.path)
        let exports = get_iface_type_exports(r, pkgs, iface_type_exports)
        for pair in u.names {
          let (n, asn) = pair
          if exports.get(n) is None {
            raise WitError::Error(
              "unknown name `" + n + "` in use " + u.path.raw,
            )
          }
          let local_name = match asn {
            Some(x) => x
            None => n
          }
          if ns.get(local_name) is Some(_) {
            raise WitError::Error(
              "duplicate name `" + local_name + "` in inline interface",
            )
          }
          ns.set(local_name, true)
          visible.set(local_name, true)
        }
      }
      _ => ()
    }
  }
  for item in iface.items {
    match item {
      TypeAlias(t) => validate_type_expr(visible, t.ty)
      Record(r) =>
        for field in r.fields {
          validate_type_expr(visible, field.1)
        }
      Variant(v) =>
        for c in v.cases {
          if c.payload is Some(t) {
            validate_type_expr(visible, t)
          }
        }
      Resource(r) =>
        for m in r.methods {
          validate_func_sig(visible, m)
        }
      Func(f) => validate_func_sig(visible, f)
      _ => ()
    }
  }
}

///|
fn validate_world_types(
  world_name : String,
  items : Array[WorldItem],
  pkg_key : String,
  iface_type_exports : Map[String, Map[String, Bool]],
  pkgs : Map[String, Package],
) -> Unit raise WitError {
  let ns : Map[String, Bool] = {}
  let visible : Map[String, Bool] = {}
  for wi in items {
    match wi {
      TypeAlias(t) => {
        ns.set(t.name, true)
        visible.set(t.name, true)
      }
      Record(r) => {
        ns.set(r.name, true)
        visible.set(r.name, true)
      }
      Resource(r) => {
        ns.set(r.name, true)
        visible.set(r.name, true)
      }
      Variant(v) => {
        ns.set(v.name, true)
        visible.set(v.name, true)
      }
      Flags(f) => {
        ns.set(f.name, true)
        visible.set(f.name, true)
      }
      Enum(e) => {
        ns.set(e.name, true)
        visible.set(e.name, true)
      }
      _ => ()
    }
  }
  for wi in items {
    match wi {
      Use(u) => {
        let r = use_path_to_iface_ref(pkg_key, u.path)
        let exports = get_iface_type_exports(r, pkgs, iface_type_exports)
        for pair in u.names {
          let (n, asn) = pair
          if exports.get(n) is None {
            raise WitError::Error(
              "unknown name `" + n + "` in use " + u.path.raw,
            )
          }
          let local_name = match asn {
            Some(x) => x
            None => n
          }
          if ns.get(local_name) is Some(_) {
            raise WitError::Error(
              "duplicate name `" +
              local_name +
              "` in world `" +
              world_name +
              "`",
            )
          }
          ns.set(local_name, true)
          visible.set(local_name, true)
        }
      }
      _ => ()
    }
  }
  for wi in items {
    match wi {
      TypeAlias(t) => validate_type_expr(visible, t.ty)
      Record(r) =>
        for field in r.fields {
          validate_type_expr(visible, field.1)
        }
      Variant(v) =>
        for c in v.cases {
          if c.payload is Some(t) {
            validate_type_expr(visible, t)
          }
        }
      Resource(r) =>
        for m in r.methods {
          validate_func_sig(visible, m)
        }
      ImportFunc(f) | ExportFunc(f) => validate_func_sig(visible, f)
      _ => ()
    }
  }
}

///|
fn collect_toplevel_aliases(pkg : Package) -> Map[String, UsePath] {
  let m : Map[String, UsePath] = {}
  for it in pkg.items {
    match it {
      ToplevelUse(u) => {
        let name = match u.as_name {
          Some(n) => n
          None => infer_toplevel_use_name(u.path)
        }
        m.set(name, u.path)
      }
      _ => ()
    }
  }
  m
}

///|
fn infer_toplevel_use_name(p : UsePath) -> String {
  // Inferred name is the last path segment before any `@version`.
  let raw = p.raw
  let mut base = raw
  match find_last_code_unit(raw, 64) {
    Some(i) => if i > 0 { base = slice_ascii(raw, 0, i) }
    None => ()
  }
  match find_last_code_unit(base, 47) {
    Some(i) => slice_ascii(base, i + 1, base.length())
    None => base
  }
}

///|
fn resolve_toplevel_alias(
  aliases : Map[String, UsePath],
  path : UsePath,
) -> UsePath {
  if find_last_code_unit(path.raw, 47) is Some(_) {
    return path
  }
  match aliases.get(path.raw) {
    Some(p) => p
    None => path
  }
}

///|
fn desugar_interface_aliases(
  iface : Interface,
  aliases : Map[String, UsePath],
) -> Interface {
  let items : Array[InterfaceItem] = []
  for it in iface.items {
    match it {
      Use(u) =>
        items.push(
          Use({ path: resolve_toplevel_alias(aliases, u.path), names: u.names }),
        )
      _ => items.push(it)
    }
  }
  { name: iface.name, items }
}

///|
fn desugar_world_aliases(w : World, aliases : Map[String, UsePath]) -> World {
  let items : Array[WorldItem] = []
  for it in w.items {
    match it {
      Import(p) => items.push(Import(resolve_toplevel_alias(aliases, p)))
      Export(p) => items.push(Export(resolve_toplevel_alias(aliases, p)))
      Include(inc) =>
        items.push(
          Include({
            path: resolve_toplevel_alias(aliases, inc.path),
            renames: inc.renames,
          }),
        )
      Use(u) =>
        items.push(
          Use({ path: resolve_toplevel_alias(aliases, u.path), names: u.names }),
        )
      ImportInlineInterface(nm, iface) =>
        items.push(
          ImportInlineInterface(
            nm,
            desugar_inline_iface_aliases(iface, aliases),
          ),
        )
      ExportInlineInterface(nm, iface) =>
        items.push(
          ExportInlineInterface(
            nm,
            desugar_inline_iface_aliases(iface, aliases),
          ),
        )
      _ => items.push(it)
    }
  }
  { name: w.name, items }
}

///|
fn desugar_inline_iface_aliases(
  iface : InlineInterface,
  aliases : Map[String, UsePath],
) -> InlineInterface {
  let items : Array[InterfaceItem] = []
  for it in iface.items {
    match it {
      Use(u) =>
        items.push(
          Use({ path: resolve_toplevel_alias(aliases, u.path), names: u.names }),
        )
      _ => items.push(it)
    }
  }
  { items, }
}

///|
fn merge_packages(acc : Package?, pkg : Package) -> Package raise WitError {
  match acc {
    None => pkg
    Some(a) => {
      let name = match (a.name, pkg.name) {
        (Some(x), Some(y)) =>
          if x == y {
            Some(x)
          } else {
            raise WitError::Error("conflicting package names")
          }
        (Some(x), None) => Some(x)
        (None, Some(y)) => Some(y)
        (None, None) => None
      }
      let version = match (a.version, pkg.version) {
        (Some(x), Some(y)) =>
          if x == y {
            Some(x)
          } else {
            raise WitError::Error("conflicting package versions")
          }
        (Some(x), None) => Some(x)
        (None, Some(y)) => Some(y)
        (None, None) => None
      }
      let items = a.items + pkg.items
      let nested = a.nested + pkg.nested
      { name, version, items, nested }
    }
  }
}

///|
/// Split a `use-path` into (package_key?, name, version?).
/// - Unqualified paths like `poll` => (None, "poll", None)
/// - Qualified paths like `wasi:io/poll@0.2.9` => (Some("wasi:io@0.2.9"), "poll", Some("0.2.9"))
fn split_use_path(path : UsePath) -> (String?, String, String?) {
  let raw = path.raw
  let mut base = raw
  let mut ver : String? = None
  // Version is a trailing `@...` with no further `/`.
  // '@' (64)
  match find_last_code_unit(raw, 64) {
    Some(i) =>
      if i > 0 && i + 1 < raw.length() {
        ver = Some(slice_ascii(raw, i + 1, raw.length()))
        base = slice_ascii(raw, 0, i)
      }
    None => ()
  }
  // '/' (47)
  match find_last_code_unit(base, 47) {
    Some(i) => {
      let pkg_name = slice_ascii(base, 0, i)
      let name = slice_ascii(base, i + 1, base.length())
      let pkg_key = match ver {
        Some(v) => pkg_name + "@" + v
        None => pkg_name
      }
      (Some(pkg_key), name, ver)
    }
    None => (None, base, ver)
  }
}

///|
fn find_last_code_unit(s : String, cu : Int) -> Int? {
  let mut found : Int? = None
  for i in 0..<s.length() {
    if s.code_unit_at(i).to_int() == cu {
      found = Some(i)
    }
  }
  found
}

///|
fn slice_ascii(s : String, start : Int, end : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = start
  while i < end && i < s.length() {
    sb.write_char(s.code_unit_at(i).to_int().unsafe_to_char())
    i = i + 1
  }
  sb.to_string()
}

///|
fn json_string(sb : StringBuilder, s : String) -> Unit {
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
}

///|
fn format_interface(sb : StringBuilder, it : Interface) -> Unit {
  sb.write_string("interface ")
  sb.write_string(it.name)
  sb.write_string(" {\n")
  let mut has_use = false
  let mut has_other = false
  for item in it.items {
    match item {
      Use(_) => has_use = true
      _ => has_other = true
    }
  }
  if has_use {
    for item in it.items {
      match item {
        Use(u) => {
          sb.write_string("  use ")
          sb.write_string(u.path.raw)
          sb.write_string(".{")
          for i in 0..<u.names.length() {
            if i > 0 {
              sb.write_string(", ")
            }
            let (n, asn) = u.names[i]
            sb.write_string(n)
            match asn {
              Some(nn) => {
                sb.write_string(" as ")
                sb.write_string(nn)
              }
              None => ()
            }
          }
          sb.write_string("};\n")
        }
        _ => ()
      }
    }
    if has_other {
      sb.write_char('\n')
    }
  }
  for item in it.items {
    match item {
      Use(_) => ()
      Func(f) => {
        sb.write_string("  ")
        sb.write_string(f.name)
        sb.write_string(": ")
        if f.is_async {
          sb.write_string("async ")
        }
        sb.write_string("func(")
        for i in 0..<f.params.length() {
          if i > 0 {
            sb.write_string(", ")
          }
          let (n, t) = f.params[i]
          sb.write_string(n)
          sb.write_string(": ")
          format_type(sb, t)
        }
        sb.write_char(')')
        if f.results.length() > 0 {
          sb.write_string(" -> ")
          if f.results.length() == 1 && f.results[0].0 is None {
            format_type(sb, f.results[0].1)
          } else {
            sb.write_char('(')
            for i in 0..<f.results.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (rn, rt) = f.results[i]
              match rn {
                Some(n) => {
                  sb.write_string(n)
                  sb.write_string(": ")
                }
                None => ()
              }
              format_type(sb, rt)
            }
            sb.write_char(')')
          }
        }
        sb.write_string(";\n")
      }
      TypeAlias(t) => {
        sb.write_string("  type ")
        sb.write_string(t.name)
        sb.write_string(" = ")
        format_type(sb, t.ty)
        sb.write_string(";\n")
      }
      Record(r) => {
        sb.write_string("  record ")
        sb.write_string(r.name)
        sb.write_string(" {\n")
        for field in r.fields {
          let (n, t) = field
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(": ")
          format_type(sb, t)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Resource(r) => {
        sb.write_string("  resource ")
        sb.write_string(r.name)
        if r.methods.length() == 0 {
          sb.write_string(";\n")
        } else {
          sb.write_string(" {\n")
          for m in r.methods {
            sb.write_string("    ")
            sb.write_string(m.name)
            sb.write_string(": ")
            if m.is_async {
              sb.write_string("async ")
            }
            sb.write_string("func(")
            for i in 0..<m.params.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (pn, pt) = m.params[i]
              sb.write_string(pn)
              sb.write_string(": ")
              format_type(sb, pt)
            }
            sb.write_char(')')
            if m.results.length() > 0 {
              sb.write_string(" -> ")
              if m.results.length() == 1 && m.results[0].0 is None {
                format_type(sb, m.results[0].1)
              } else {
                sb.write_char('(')
                for i in 0..<m.results.length() {
                  if i > 0 {
                    sb.write_string(", ")
                  }
                  let (rn, rt) = m.results[i]
                  match rn {
                    Some(n) => {
                      sb.write_string(n)
                      sb.write_string(": ")
                    }
                    None => ()
                  }
                  format_type(sb, rt)
                }
                sb.write_char(')')
              }
            }
            sb.write_string(";\n")
          }
          sb.write_string("  }\n")
        }
      }
      Variant(v) => {
        sb.write_string("  variant ")
        sb.write_string(v.name)
        sb.write_string(" {\n")
        for c in v.cases {
          sb.write_string("    ")
          sb.write_string(c.name)
          match c.payload {
            Some(t) => {
              sb.write_char('(')
              format_type(sb, t)
              sb.write_char(')')
            }
            None => ()
          }
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Flags(f) => {
        sb.write_string("  flags ")
        sb.write_string(f.name)
        sb.write_string(" {\n")
        for n in f.flags {
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Enum(e) => {
        sb.write_string("  enum ")
        sb.write_string(e.name)
        sb.write_string(" {\n")
        for n in e.cases {
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
    }
  }
  sb.write_string("}\n")
}

///|
fn format_world(sb : StringBuilder, w : World) -> Unit {
  sb.write_string("world ")
  sb.write_string(w.name)
  sb.write_string(" {\n")
  fn is_export_item(it : WorldItem) -> Bool {
    match it {
      Export(_) | ExportFunc(_) | ExportInlineInterface(_, _) => true
      _ => false
    }
  }

  let mut has_export = false
  let mut has_nonexport = false
  for it in w.items {
    if is_export_item(it) {
      has_export = true
    } else {
      has_nonexport = true
    }
  }
  fn emit(it : WorldItem) -> Unit {
    match it {
      Import(p) => {
        sb.write_string("  import ")
        sb.write_string(p.raw)
        sb.write_string(";\n")
      }
      Export(p) => {
        sb.write_string("  export ")
        sb.write_string(p.raw)
        sb.write_string(";\n")
      }
      ImportFunc(f) => {
        sb.write_string("  import ")
        sb.write_string(f.name)
        sb.write_string(": ")
        if f.is_async {
          sb.write_string("async ")
        }
        sb.write_string("func(")
        for i in 0..<f.params.length() {
          if i > 0 {
            sb.write_string(", ")
          }
          let (n, t) = f.params[i]
          sb.write_string(n)
          sb.write_string(": ")
          format_type(sb, t)
        }
        sb.write_char(')')
        if f.results.length() > 0 {
          sb.write_string(" -> ")
          // WIT MVP supports a single result; this code prints the existing AST shape.
          if f.results.length() == 1 && f.results[0].0 is None {
            format_type(sb, f.results[0].1)
          } else {
            sb.write_char('(')
            for i in 0..<f.results.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (rn, rt) = f.results[i]
              match rn {
                Some(n) => {
                  sb.write_string(n)
                  sb.write_string(": ")
                }
                None => ()
              }
              format_type(sb, rt)
            }
            sb.write_char(')')
          }
        }
        sb.write_string(";\n")
      }
      ExportFunc(f) => {
        sb.write_string("  export ")
        sb.write_string(f.name)
        sb.write_string(": ")
        if f.is_async {
          sb.write_string("async ")
        }
        sb.write_string("func(")
        for i in 0..<f.params.length() {
          if i > 0 {
            sb.write_string(", ")
          }
          let (n, t) = f.params[i]
          sb.write_string(n)
          sb.write_string(": ")
          format_type(sb, t)
        }
        sb.write_char(')')
        if f.results.length() > 0 {
          sb.write_string(" -> ")
          if f.results.length() == 1 && f.results[0].0 is None {
            format_type(sb, f.results[0].1)
          } else {
            sb.write_char('(')
            for i in 0..<f.results.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (rn, rt) = f.results[i]
              match rn {
                Some(n) => {
                  sb.write_string(n)
                  sb.write_string(": ")
                }
                None => ()
              }
              format_type(sb, rt)
            }
            sb.write_char(')')
          }
        }
        sb.write_string(";\n")
      }
      ImportInlineInterface(nm, iface) => {
        sb.write_string("  import ")
        sb.write_string(nm)
        sb.write_string(": interface {\n")
        for item in iface.items {
          match item {
            Func(f) => {
              sb.write_string("    ")
              sb.write_string(f.name)
              sb.write_string(": ")
              if f.is_async {
                sb.write_string("async ")
              }
              sb.write_string("func(")
              for i in 0..<f.params.length() {
                if i > 0 {
                  sb.write_string(", ")
                }
                let (pn, pt) = f.params[i]
                sb.write_string(pn)
                sb.write_string(": ")
                format_type(sb, pt)
              }
              sb.write_char(')')
              if f.results.length() > 0 {
                sb.write_string(" -> ")
                format_type(sb, f.results[0].1)
              }
              sb.write_string(";\n")
            }
            TypeAlias(t) => {
              sb.write_string("    type ")
              sb.write_string(t.name)
              sb.write_string(" = ")
              format_type(sb, t.ty)
              sb.write_string(";\n")
            }
            Record(r) => {
              sb.write_string("    record ")
              sb.write_string(r.name)
              sb.write_string(" {\n")
              for field in r.fields {
                let (n, t) = field
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(": ")
                format_type(sb, t)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Use(u) => {
              sb.write_string("    use ")
              sb.write_string(u.path.raw)
              sb.write_string(".{")
              for i in 0..<u.names.length() {
                if i > 0 {
                  sb.write_string(", ")
                }
                let (n, asn) = u.names[i]
                sb.write_string(n)
                match asn {
                  Some(nn) => {
                    sb.write_string(" as ")
                    sb.write_string(nn)
                  }
                  None => ()
                }
              }
              sb.write_string("};\n")
            }
            Resource(r) => {
              sb.write_string("    resource ")
              sb.write_string(r.name)
              if r.methods.length() == 0 {
                sb.write_string(";\n")
              } else {
                sb.write_string(" {\n")
                for m in r.methods {
                  sb.write_string("      ")
                  sb.write_string(m.name)
                  sb.write_string(": ")
                  if m.is_async {
                    sb.write_string("async ")
                  }
                  sb.write_string("func(")
                  for i in 0..<m.params.length() {
                    if i > 0 {
                      sb.write_string(", ")
                    }
                    let (pn, pt) = m.params[i]
                    sb.write_string(pn)
                    sb.write_string(": ")
                    format_type(sb, pt)
                  }
                  sb.write_char(')')
                  if m.results.length() > 0 {
                    sb.write_string(" -> ")
                    format_type(sb, m.results[0].1)
                  }
                  sb.write_string(";\n")
                }
                sb.write_string("    }\n")
              }
            }
            Variant(v) => {
              sb.write_string("    variant ")
              sb.write_string(v.name)
              sb.write_string(" {\n")
              for c in v.cases {
                sb.write_string("      ")
                sb.write_string(c.name)
                match c.payload {
                  Some(t) => {
                    sb.write_char('(')
                    format_type(sb, t)
                    sb.write_char(')')
                  }
                  None => ()
                }
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Flags(f) => {
              sb.write_string("    flags ")
              sb.write_string(f.name)
              sb.write_string(" {\n")
              for n in f.flags {
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Enum(e) => {
              sb.write_string("    enum ")
              sb.write_string(e.name)
              sb.write_string(" {\n")
              for n in e.cases {
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
          }
        }
        sb.write_string("  }\n")
      }
      ExportInlineInterface(nm, iface) => {
        // Same formatting as `import name: interface { ... }`
        sb.write_string("  export ")
        sb.write_string(nm)
        sb.write_string(": interface {\n")
        for item in iface.items {
          match item {
            Func(f) => {
              sb.write_string("    ")
              sb.write_string(f.name)
              sb.write_string(": ")
              if f.is_async {
                sb.write_string("async ")
              }
              sb.write_string("func(")
              for i in 0..<f.params.length() {
                if i > 0 {
                  sb.write_string(", ")
                }
                let (pn, pt) = f.params[i]
                sb.write_string(pn)
                sb.write_string(": ")
                format_type(sb, pt)
              }
              sb.write_char(')')
              if f.results.length() > 0 {
                sb.write_string(" -> ")
                format_type(sb, f.results[0].1)
              }
              sb.write_string(";\n")
            }
            TypeAlias(t) => {
              sb.write_string("    type ")
              sb.write_string(t.name)
              sb.write_string(" = ")
              format_type(sb, t.ty)
              sb.write_string(";\n")
            }
            Record(r) => {
              sb.write_string("    record ")
              sb.write_string(r.name)
              sb.write_string(" {\n")
              for field in r.fields {
                let (n, t) = field
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(": ")
                format_type(sb, t)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Use(u) => {
              sb.write_string("    use ")
              sb.write_string(u.path.raw)
              sb.write_string(".{")
              for i in 0..<u.names.length() {
                if i > 0 {
                  sb.write_string(", ")
                }
                let (n, asn) = u.names[i]
                sb.write_string(n)
                match asn {
                  Some(nn) => {
                    sb.write_string(" as ")
                    sb.write_string(nn)
                  }
                  None => ()
                }
              }
              sb.write_string("};\n")
            }
            Resource(r) => {
              sb.write_string("    resource ")
              sb.write_string(r.name)
              if r.methods.length() == 0 {
                sb.write_string(";\n")
              } else {
                sb.write_string(" {\n")
                for m in r.methods {
                  sb.write_string("      ")
                  sb.write_string(m.name)
                  sb.write_string(": ")
                  if m.is_async {
                    sb.write_string("async ")
                  }
                  sb.write_string("func(")
                  for i in 0..<m.params.length() {
                    if i > 0 {
                      sb.write_string(", ")
                    }
                    let (pn, pt) = m.params[i]
                    sb.write_string(pn)
                    sb.write_string(": ")
                    format_type(sb, pt)
                  }
                  sb.write_char(')')
                  if m.results.length() > 0 {
                    sb.write_string(" -> ")
                    format_type(sb, m.results[0].1)
                  }
                  sb.write_string(";\n")
                }
                sb.write_string("    }\n")
              }
            }
            Variant(v) => {
              sb.write_string("    variant ")
              sb.write_string(v.name)
              sb.write_string(" {\n")
              for c in v.cases {
                sb.write_string("      ")
                sb.write_string(c.name)
                match c.payload {
                  Some(t) => {
                    sb.write_char('(')
                    format_type(sb, t)
                    sb.write_char(')')
                  }
                  None => ()
                }
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Flags(f) => {
              sb.write_string("    flags ")
              sb.write_string(f.name)
              sb.write_string(" {\n")
              for n in f.flags {
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Enum(e) => {
              sb.write_string("    enum ")
              sb.write_string(e.name)
              sb.write_string(" {\n")
              for n in e.cases {
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
          }
        }
        sb.write_string("  }\n")
      }
      Include(inc) => {
        sb.write_string("  include ")
        sb.write_string(inc.path.raw)
        match inc.renames {
          Some(rs) => {
            sb.write_string(" with { ")
            for i in 0..<rs.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (from, to) = rs[i]
              sb.write_string(from)
              sb.write_string(" as ")
              sb.write_string(to)
            }
            sb.write_string(" }")
          }
          None => ()
        }
        match inc.renames {
          Some(_) => sb.write_string("\n")
          None => sb.write_string(";\n")
        }
      }
      Use(u) => {
        sb.write_string("  use ")
        sb.write_string(u.path.raw)
        sb.write_string(".{")
        for i in 0..<u.names.length() {
          if i > 0 {
            sb.write_string(", ")
          }
          let (n, asn) = u.names[i]
          sb.write_string(n)
          match asn {
            Some(nn) => {
              sb.write_string(" as ")
              sb.write_string(nn)
            }
            None => ()
          }
        }
        sb.write_string("};\n")
      }
      TypeAlias(t) => {
        sb.write_string("  type ")
        sb.write_string(t.name)
        sb.write_string(" = ")
        format_type(sb, t.ty)
        sb.write_string(";\n")
      }
      Record(r) => {
        sb.write_string("  record ")
        sb.write_string(r.name)
        sb.write_string(" {\n")
        for field in r.fields {
          let (n, t) = field
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(": ")
          format_type(sb, t)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Resource(r) => {
        sb.write_string("  resource ")
        sb.write_string(r.name)
        if r.methods.length() == 0 {
          sb.write_string(";\n")
        } else {
          sb.write_string(" {\n")
          for m in r.methods {
            sb.write_string("    ")
            sb.write_string(m.name)
            sb.write_string(": ")
            if m.is_async {
              sb.write_string("async ")
            }
            sb.write_string("func(")
            for i in 0..<m.params.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (pn, pt) = m.params[i]
              sb.write_string(pn)
              sb.write_string(": ")
              format_type(sb, pt)
            }
            sb.write_char(')')
            if m.results.length() > 0 {
              sb.write_string(" -> ")
              format_type(sb, m.results[0].1)
            }
            sb.write_string(";\n")
          }
          sb.write_string("  }\n")
        }
      }
      Variant(v) => {
        sb.write_string("  variant ")
        sb.write_string(v.name)
        sb.write_string(" {\n")
        for c in v.cases {
          sb.write_string("    ")
          sb.write_string(c.name)
          match c.payload {
            Some(t) => {
              sb.write_char('(')
              format_type(sb, t)
              sb.write_char(')')
            }
            None => ()
          }
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Flags(f) => {
        sb.write_string("  flags ")
        sb.write_string(f.name)
        sb.write_string(" {\n")
        for n in f.flags {
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Enum(e) => {
        sb.write_string("  enum ")
        sb.write_string(e.name)
        sb.write_string(" {\n")
        for n in e.cases {
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
    }
  }

  for it in w.items {
    if !is_export_item(it) {
      emit(it)
    }
  }
  if has_export && has_nonexport {
    sb.write_char('\n')
  }
  for it in w.items {
    if is_export_item(it) {
      emit(it)
    }
  }
  sb.write_string("}\n")
}

///|
fn format_type(sb : StringBuilder, t : TypeExpr) -> Unit {
  match t {
    Id(n) => sb.write_string(n)
    Apply(n, args) => {
      sb.write_string(n)
      sb.write_char('<')
      for i in 0..<args.length() {
        if i > 0 {
          sb.write_string(", ")
        }
        format_type(sb, args[i])
      }
      sb.write_char('>')
    }
    Record(fields) => {
      sb.write_string("record { ")
      for i in 0..<fields.length() {
        if i > 0 {
          sb.write_string(", ")
        }
        let (field_name, ft) = fields[i]
        sb.write_string(field_name)
        sb.write_string(": ")
        format_type(sb, ft)
      }
      sb.write_string(" }")
    }
  }
}

///|
priv struct Lexer {
  src : String
  mut i : Int
  mut line : Int
  mut col : Int
}

///|
fn Lexer::new(src : String) -> Lexer {
  { src, i: 0, line: 1, col: 1 }
}

///|
fn Lexer::lex_all(self : Lexer) -> Array[Token] raise WitError {
  let out : Array[Token] = []
  while true {
    self.skip_ws_and_comments()
    if self.i >= self.src.length() {
      break
    }
    let (kind, line, col) = self.lex_one()
    out.push({ kind, line, col })
  }
  out
}

///|
fn Lexer::peek(self : Lexer, off : Int) -> Int? {
  let j = self.i + off
  if j >= self.src.length() {
    None
  } else {
    Some(self.src.code_unit_at(j).to_int())
  }
}

///|
fn Lexer::bump(self : Lexer) -> Int? {
  if self.i >= self.src.length() {
    return None
  }
  let cu = self.src.code_unit_at(self.i).to_int()
  self.i = self.i + 1
  if cu == 10 { // \n
    self.line = self.line + 1
    self.col = 1
  } else {
    self.col = self.col + 1
  }
  Some(cu)
}

///|
fn Lexer::skip_ws_and_comments(self : Lexer) -> Unit raise WitError {
  while self.i < self.src.length() {
    let cu = self.src.code_unit_at(self.i).to_int()
    // whitespace
    if cu == 32 || cu == 9 || cu == 10 || cu == 13 {
      self.bump() |> ignore
      continue
    }
    // line comment: //
    if cu == 47 {
      match self.peek(1) {
        Some(47) => {
          while self.i < self.src.length() {
            let b = self.bump().unwrap_or(0)
            if b == 10 {
              break
            }
          }
          continue
        }
        Some(42) => {
          // block comment: /* ... */
          self.bump() |> ignore
          self.bump() |> ignore
          while true {
            if self.i >= self.src.length() {
              raise WitError::Error("unterminated block comment")
            }
            let b = self.bump().unwrap_or(0)
            if b == 42 && self.peek(0) is Some(47) {
              self.bump() |> ignore
              break
            }
          }
          continue
        }
        _ => ()
      }
    }
    break
  }
}

///|
fn Lexer::lex_one(self : Lexer) -> (TokenKind, Int, Int) raise WitError {
  let line = self.line
  let col = self.col
  let cu = self.src.code_unit_at(self.i).to_int()
  // punctuation / operators
  match cu {
    123 => {
      self.bump() |> ignore
      (LBrace, line, col)
    } // {
    125 => {
      self.bump() |> ignore
      (RBrace, line, col)
    } // }
    40 => {
      self.bump() |> ignore
      (LParen, line, col)
    } // (
    41 => {
      self.bump() |> ignore
      (RParen, line, col)
    } // )
    60 => {
      self.bump() |> ignore
      (LAngle, line, col)
    } // <
    62 =>
      match self.peek(1) {
        Some(_) => {
          self.bump() |> ignore
          (RAngle, line, col)
        }
        None => {
          self.bump() |> ignore
          (RAngle, line, col)
        }
      }
    58 => {
      self.bump() |> ignore
      (Colon, line, col)
    } // :
    59 => {
      self.bump() |> ignore
      (Semi, line, col)
    } // ;
    44 => {
      self.bump() |> ignore
      (Comma, line, col)
    } // ,
    46 => {
      self.bump() |> ignore
      (Dot, line, col)
    } // .
    47 => {
      self.bump() |> ignore
      (Slash, line, col)
    } // /
    64 => {
      self.bump() |> ignore
      (At, line, col)
    } // @
    61 => {
      self.bump() |> ignore
      (Eq, line, col)
    } // =
    43 => {
      self.bump() |> ignore
      (Plus, line, col)
    } // +
    45 =>
      match self.peek(1) {
        Some(62) => { // ->
          self.bump() |> ignore
          self.bump() |> ignore
          (Arrow, line, col)
        }
        _ => {
          self.bump() |> ignore
          (Dash, line, col)
        }
      }
    34 => // "
      (StrLit(self.lex_string()), line, col)
    _ =>
      if is_digit(cu) {
        let n = self.lex_int()
        (IntLit(n), line, col)
      } else if is_ident_start(cu) {
        let s = self.lex_ident()
        let k = match s {
          "package" => KwPackage
          "interface" => KwInterface
          "world" => KwWorld
          "use" => KwUse
          "as" => KwAs
          "with" => KwWith
          "include" => KwInclude
          "type" => KwType
          "resource" => KwResource
          "enum" => KwEnum
          "flags" => KwFlags
          "variant" => KwVariant
          "func" => KwFunc
          "import" => KwImport
          "export" => KwExport
          "record" => KwRecord
          "tuple" => KwTuple
          "list" => KwList
          "option" => KwOption
          "result" => KwResult
          "borrow" => KwBorrow
          "future" => KwFuture
          "stream" => KwStream
          "async" => KwAsync
          _ => Ident(s)
        }
        (k, line, col)
      } else {
        raise WitError::Error("unexpected character")
      }
  }
}

///|
fn Lexer::lex_ident(self : Lexer) -> String {
  let sb = StringBuilder::new()
  // First char is known to be a valid ident start.
  let first = self.bump().unwrap_or(0)
  sb.write_char(first.unsafe_to_char())
  while self.i < self.src.length() {
    let cu = self.src.code_unit_at(self.i).to_int()
    if is_ident_continue(cu) {
      let b = self.bump().unwrap_or(0)
      sb.write_char(b.unsafe_to_char())
    } else {
      break
    }
  }
  sb.to_string()
}

///|
fn Lexer::lex_int(self : Lexer) -> Int {
  let mut n = 0
  while self.i < self.src.length() {
    let cu = self.src.code_unit_at(self.i).to_int()
    if !is_digit(cu) {
      break
    }
    n = n * 10 + (cu - 48)
    self.bump() |> ignore
  }
  n
}

///|
fn Lexer::lex_string(self : Lexer) -> String raise WitError {
  // Consume opening quote.
  self.bump() |> ignore
  let sb = StringBuilder::new()
  while true {
    if self.i >= self.src.length() {
      raise WitError::Error("unterminated string literal")
    }
    let cu = self.bump().unwrap_or(0)
    if cu == 34 {
      break
    }
    if cu == 92 { // backslash
      let esc = self.bump().unwrap_or(0)
      match esc {
        34 => sb.write_char('"')
        92 => sb.write_char('\\')
        110 => sb.write_char('\n')
        114 => sb.write_char('\r')
        116 => sb.write_char('\t')
        _ => raise WitError::Error("unsupported string escape")
      }
    } else {
      sb.write_char(cu.unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
fn is_digit(cu : Int) -> Bool {
  cu >= 48 && cu <= 57
}

///|
fn is_ident_start(cu : Int) -> Bool {
  (cu >= 65 && cu <= 90) || (cu >= 97 && cu <= 122) || cu == 95 // _
}

///|
fn is_ident_continue(cu : Int) -> Bool {
  is_ident_start(cu) || is_digit(cu) || cu == 45 // -
}

///|
priv struct Parser {
  toks : Array[Token]
  mut i : Int
}

///|
fn Parser::new(toks : Array[Token]) -> Parser {
  { toks, i: 0 }
}

///|
fn Parser::parse_package(self : Parser) -> Package raise WitError {
  let mut name : String? = None
  let mut version : String? = None
  if self.peek_kw(KwPackage) {
    self.bump_kw(KwPackage)
    name = Some(self.parse_package_name())
    if self.peek_kw(At) {
      self.bump_kw(At)
      version = Some(self.parse_version())
    }
    self.bump_kw(Semi)
  }
  let items : Array[TopItem] = []
  let nested : Array[Package] = []
  while self.i < self.toks.length() {
    self.skip_gates()
    if self.i >= self.toks.length() {
      break
    }
    if self.peek_kw(KwUse) {
      items.push(ToplevelUse(self.parse_toplevel_use()))
    } else if self.peek_kw(KwInterface) {
      items.push(Interface(self.parse_interface()))
    } else if self.peek_kw(KwWorld) {
      items.push(World(self.parse_world()))
    } else if self.peek_kw(KwPackage) {
      nested.push(self.parse_nested_package())
    } else {
      raise self.err_here(
        "expected `use`, `interface`, `world`, or nested `package`",
      )
    }
  }
  { name, version, items, nested }
}

///|
fn Parser::skip_gates(self : Parser) -> Unit raise WitError {
  while self.peek_kw(At) {
    self.bump_kw(At)
    // Eat the gate name token (e.g. since/unstable/deprecated).
    if self.i >= self.toks.length() {
      raise self.err_here("unexpected EOF after '@'")
    }
    self.i = self.i + 1
    // If followed by parentheses, skip balanced parens.
    if self.peek_kw(LParen) {
      self.bump_kw(LParen)
      let mut depth = 1
      while depth > 0 {
        if self.i >= self.toks.length() {
          raise self.err_here("unterminated gate annotation")
        }
        match self.toks[self.i].kind {
          LParen => depth = depth + 1
          RParen => depth = depth - 1
          _ => ()
        }
        self.i = self.i + 1
      }
    }
  }
}

///|
fn Parser::parse_toplevel_use(self : Parser) -> ToplevelUse raise WitError {
  self.bump_kw(KwUse)
  let path = self.parse_use_path_until([KwAs, Semi])
  let mut as_name : String? = None
  if self.peek_kw(KwAs) {
    self.bump_kw(KwAs)
    as_name = Some(self.parse_ident())
  }
  self.bump_kw(Semi)
  { path, as_name }
}

///|
fn Parser::parse_nested_package(self : Parser) -> Package raise WitError {
  self.bump_kw(KwPackage)
  let name = Some(self.parse_package_name())
  let mut version : String? = None
  if self.peek_kw(At) {
    self.bump_kw(At)
    version = Some(self.parse_version())
  }
  self.bump_kw(LBrace)
  let items : Array[TopItem] = []
  let nested : Array[Package] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(KwUse) {
      items.push(ToplevelUse(self.parse_toplevel_use()))
    } else if self.peek_kw(KwInterface) {
      items.push(Interface(self.parse_interface()))
    } else if self.peek_kw(KwWorld) {
      items.push(World(self.parse_world()))
    } else if self.peek_kw(KwPackage) {
      nested.push(self.parse_nested_package())
    } else {
      raise self.err_here("expected item within nested package")
    }
  }
  self.bump_kw(RBrace)
  { name, version, items, nested }
}

///|
fn Parser::parse_package_name(self : Parser) -> String raise WitError {
  // Capture tokens up to '@', ';' or '{' (namespace:path[/path]*).
  let sb = StringBuilder::new()
  while self.i < self.toks.length() {
    match self.toks[self.i].kind {
      At | Semi | LBrace => break
      Ident(s) => {
        sb.write_string(s)
        self.i = self.i + 1
      }
      Colon => {
        sb.write_char(':')
        self.i = self.i + 1
      }
      Slash => {
        sb.write_char('/')
        self.i = self.i + 1
      }
      Dot => {
        sb.write_char('.')
        self.i = self.i + 1
      }
      _ => raise self.err_here("invalid token in package name")
    }
  }
  sb.to_string()
}

///|
fn Parser::parse_version(self : Parser) -> String raise WitError {
  // Simple semver-ish capture until ';' or '{' (supports pre-release/build).
  let sb = StringBuilder::new()
  while self.i < self.toks.length() {
    match self.toks[self.i].kind {
      Semi | LBrace => break
      IntLit(n) => {
        sb.write_string(n.to_string())
        self.i = self.i + 1
      }
      Dot => {
        sb.write_char('.')
        self.i = self.i + 1
      }
      Dash => {
        sb.write_char('-')
        self.i = self.i + 1
      }
      Plus => {
        sb.write_char('+')
        self.i = self.i + 1
      }
      Ident(s) => {
        sb.write_string(s)
        self.i = self.i + 1
      }
      _ => raise self.err_here("invalid token in version")
    }
  }
  sb.to_string()
}

///|
fn Parser::parse_use_path_until(
  self : Parser,
  stops : Array[TokenKind],
) -> UsePath raise WitError {
  let sb = StringBuilder::new()
  while self.i < self.toks.length() && !self.peek_any(stops) {
    match self.toks[self.i].kind {
      Ident(s) => sb.write_string(s)
      IntLit(n) => sb.write_string(n.to_string())
      Colon => sb.write_char(':')
      Slash => sb.write_char('/')
      Dot => sb.write_char('.')
      At => sb.write_char('@')
      Dash => sb.write_char('-')
      Plus => sb.write_char('+')
      _ => raise self.err_here("invalid token in use-path")
    }
    self.i = self.i + 1
  }
  { raw: sb.to_string() }
}

///|
fn Parser::peek_any(self : Parser, stops : Array[TokenKind]) -> Bool {
  for s in stops {
    if self.peek_kw(s) {
      return true
    }
  }
  false
}

///|
fn Parser::parse_use_item(self : Parser) -> UseItem raise WitError {
  self.bump_kw(KwUse)
  let path = self.parse_use_path_before_dot_lbrace()
  self.bump_kw(Dot)
  self.bump_kw(LBrace)
  let names : Array[(String, String?)] = []
  if !self.peek_kw(RBrace) {
    while true {
      let n = self.parse_ident()
      let mut asn : String? = None
      if self.peek_kw(KwAs) {
        self.bump_kw(KwAs)
        asn = Some(self.parse_ident())
      }
      names.push((n, asn))
      if self.peek_kw(Comma) {
        self.bump_kw(Comma)
        // Trailing comma allowed.
        if self.peek_kw(RBrace) {
          break
        }
        continue
      }
      break
    }
  }
  self.bump_kw(RBrace)
  self.bump_kw(Semi)
  { path, names }
}

///|
fn Parser::parse_use_path_before_dot_lbrace(
  self : Parser,
) -> UsePath raise WitError {
  let sb = StringBuilder::new()
  while self.i < self.toks.length() {
    if self.peek_kw(Dot) && self.peek_next_is(LBrace) {
      break
    }
    match self.toks[self.i].kind {
      Ident(s) => sb.write_string(s)
      IntLit(n) => sb.write_string(n.to_string())
      Colon => sb.write_char(':')
      Slash => sb.write_char('/')
      Dot => sb.write_char('.')
      At => sb.write_char('@')
      Dash => sb.write_char('-')
      Plus => sb.write_char('+')
      _ => raise self.err_here("invalid token in use-path")
    }
    self.i = self.i + 1
  }
  { raw: sb.to_string() }
}

///|
fn Parser::peek_next_is(self : Parser, k : TokenKind) -> Bool {
  if self.i + 1 >= self.toks.length() {
    return false
  }
  token_kind_is(self.toks[self.i + 1].kind, k)
}

///|
fn Parser::parse_include_item(self : Parser) -> IncludeItem raise WitError {
  self.bump_kw(KwInclude)
  let path = self.parse_use_path_until([KwWith, Semi])
  let mut renames : Array[(String, String)]? = None
  if self.peek_kw(KwWith) {
    self.bump_kw(KwWith)
    self.bump_kw(LBrace)
    let rs : Array[(String, String)] = []
    if !self.peek_kw(RBrace) {
      while true {
        let from = self.parse_ident()
        self.bump_kw(KwAs)
        let to = self.parse_ident()
        rs.push((from, to))
        if self.peek_kw(Comma) {
          self.bump_kw(Comma)
          if self.peek_kw(RBrace) {
            break
          }
          continue
        }
        break
      }
    }
    self.bump_kw(RBrace)
    renames = Some(rs)
    // wasm-tools accepts `include X with { ... }` without a trailing `;`.
    self.eat_kw(Semi)
  } else {
    self.bump_kw(Semi)
  }
  { path, renames }
}

///|
fn Parser::parse_resource_decl(self : Parser) -> ResourceDecl raise WitError {
  self.bump_kw(KwResource)
  let name = self.parse_ident()
  let methods : Array[FuncDecl] = []
  if self.peek_kw(LBrace) {
    self.bump_kw(LBrace)
    while !self.peek_kw(RBrace) {
      self.skip_gates()
      if self.peek_kw(RBrace) {
        break
      }
      // Methods use the same syntax as interface functions: `id: func ...;`
      methods.push(self.parse_func_decl())
      self.bump_kw(Semi)
    }
    self.bump_kw(RBrace)
  }
  { name, methods }
}

///|
fn Parser::parse_variant_decl(self : Parser) -> VariantDecl raise WitError {
  self.bump_kw(KwVariant)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let cases : Array[VariantCase] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    let case_name = self.parse_ident()
    let mut payload : TypeExpr? = None
    if self.peek_kw(LParen) {
      self.bump_kw(LParen)
      payload = Some(self.parse_type())
      self.bump_kw(RParen)
    }
    cases.push({ name: case_name, payload })
    self.eat_kw(Comma)
  }
  self.bump_kw(RBrace)
  { name, cases }
}

///|
fn Parser::parse_flags_decl(self : Parser) -> FlagsDecl raise WitError {
  self.bump_kw(KwFlags)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let flags : Array[String] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    flags.push(self.parse_ident())
    self.eat_kw(Comma)
  }
  self.bump_kw(RBrace)
  { name, flags }
}

///|
fn Parser::parse_enum_decl(self : Parser) -> EnumDecl raise WitError {
  self.bump_kw(KwEnum)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let cases : Array[String] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    cases.push(self.parse_ident())
    self.eat_kw(Comma)
  }
  self.bump_kw(RBrace)
  { name, cases }
}

///|
fn Parser::parse_interface(self : Parser) -> Interface raise WitError {
  self.bump_kw(KwInterface)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let items : Array[InterfaceItem] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    if self.peek_kw(KwUse) {
      items.push(Use(self.parse_use_item()))
    } else if self.peek_kw(KwType) {
      items.push(TypeAlias(self.parse_type_alias()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwRecord) {
      items.push(Record(self.parse_record_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwResource) {
      items.push(Resource(self.parse_resource_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwVariant) {
      items.push(Variant(self.parse_variant_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwFlags) {
      items.push(Flags(self.parse_flags_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwEnum) {
      items.push(Enum(self.parse_enum_decl()))
      self.eat_kw(Semi)
    } else {
      items.push(Func(self.parse_func_decl()))
      self.bump_kw(Semi)
    }
  }
  self.bump_kw(RBrace)
  { name, items }
}

///|
fn Parser::parse_world(self : Parser) -> World raise WitError {
  self.bump_kw(KwWorld)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let items : Array[WorldItem] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    if self.peek_kw(KwImport) || self.peek_kw(KwExport) {
      let is_import = self.peek_kw(KwImport)
      self.i = self.i + 1
      // `import name: ...` vs `import use-path;`
      //
      // Disambiguation:
      // - named form: `id ':' ('interface' | 'async'? 'func')`
      // - use-path form: includes ':' but next token is `Ident`, not `interface`/`func`.
      if self.peek_kw(Ident("")) && self.peek_next_is(Colon) {
        // Peek after ':' to see if this is a named extern-type.
        if self.i + 2 < self.toks.length() {
          match self.toks[self.i + 2].kind {
            KwInterface | KwFunc | KwAsync => {
              let nm = self.parse_ident()
              self.bump_kw(Colon)
              if self.peek_kw(KwInterface) {
                let iface = self.parse_inline_interface()
                if is_import {
                  items.push(ImportInlineInterface(nm, iface))
                } else {
                  items.push(ExportInlineInterface(nm, iface))
                }
              } else {
                // func-type ends with ';'
                let f = self.parse_func_type_after_colon(nm)
                if is_import {
                  items.push(ImportFunc(f))
                } else {
                  items.push(ExportFunc(f))
                }
                self.bump_kw(Semi)
              }
              continue
            }
            _ => ()
          }
        }
      }
      // Otherwise parse as `use-path;`
      let p = self.parse_use_path_until([Semi])
      self.bump_kw(Semi)
      if is_import {
        items.push(Import(p))
      } else {
        items.push(Export(p))
      }
    } else if self.peek_kw(KwInclude) {
      items.push(Include(self.parse_include_item()))
    } else if self.peek_kw(KwUse) {
      items.push(Use(self.parse_use_item()))
    } else if self.peek_kw(KwType) {
      items.push(TypeAlias(self.parse_type_alias()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwRecord) {
      items.push(Record(self.parse_record_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwResource) {
      items.push(Resource(self.parse_resource_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwVariant) {
      items.push(Variant(self.parse_variant_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwFlags) {
      items.push(Flags(self.parse_flags_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwEnum) {
      items.push(Enum(self.parse_enum_decl()))
      self.eat_kw(Semi)
    } else {
      raise self.err_here(
        "expected `import`, `export`, `include`, `use`, or type definition",
      )
    }
  }
  self.bump_kw(RBrace)
  { name, items }
}

///|
fn Parser::parse_inline_interface(
  self : Parser,
) -> InlineInterface raise WitError {
  self.bump_kw(KwInterface)
  self.bump_kw(LBrace)
  let items : Array[InterfaceItem] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    if self.peek_kw(KwUse) {
      items.push(Use(self.parse_use_item()))
    } else if self.peek_kw(KwType) {
      items.push(TypeAlias(self.parse_type_alias()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwRecord) {
      items.push(Record(self.parse_record_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwResource) {
      items.push(Resource(self.parse_resource_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwVariant) {
      items.push(Variant(self.parse_variant_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwFlags) {
      items.push(Flags(self.parse_flags_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwEnum) {
      items.push(Enum(self.parse_enum_decl()))
      self.eat_kw(Semi)
    } else {
      items.push(Func(self.parse_func_decl()))
      self.bump_kw(Semi)
    }
  }
  self.bump_kw(RBrace)
  { items, }
}

///|
fn Parser::parse_func_type_after_colon(
  self : Parser,
  name : String,
) -> FuncDecl raise WitError {
  let mut is_async = false
  if self.peek_kw(KwAsync) {
    self.bump_kw(KwAsync)
    is_async = true
  }
  self.bump_kw(KwFunc)
  self.bump_kw(LParen)
  let params = self.parse_named_type_list(RParen)
  self.bump_kw(RParen)
  let results : Array[(String?, TypeExpr)] = []
  if self.peek_kw(Arrow) {
    self.bump_kw(Arrow)
    results.push((None, self.parse_type()))
  }
  { name, is_async, params, results }
}

///|
fn Parser::parse_func_decl(self : Parser) -> FuncDecl raise WitError {
  let name = self.parse_ident()
  self.bump_kw(Colon)
  let mut is_async = false
  if self.peek_kw(KwAsync) {
    self.bump_kw(KwAsync)
    is_async = true
  }
  self.bump_kw(KwFunc)
  self.bump_kw(LParen)
  let params = self.parse_named_type_list(RParen)
  self.bump_kw(RParen)
  let results : Array[(String?, TypeExpr)] = []
  if self.peek_kw(Arrow) {
    self.bump_kw(Arrow)
    results.push((None, self.parse_type()))
  }
  { name, is_async, params, results }
}

///|
fn Parser::parse_type_alias(self : Parser) -> TypeAlias raise WitError {
  self.bump_kw(KwType)
  let name = self.parse_ident()
  self.bump_kw(Eq)
  let ty = self.parse_type()
  { name, ty }
}

///|
fn Parser::parse_record_decl(self : Parser) -> RecordDecl raise WitError {
  self.bump_kw(KwRecord)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let fields : Array[(String, TypeExpr)] = []
  while !self.peek_kw(RBrace) {
    let field_name = self.parse_ident()
    self.bump_kw(Colon)
    let ft = self.parse_type()
    fields.push((field_name, ft))
    self.eat_kw(Comma)
  }
  self.bump_kw(RBrace)
  { name, fields }
}

///|
fn Parser::parse_type(self : Parser) -> TypeExpr raise WitError {
  if self.peek_kw(KwRecord) {
    self.bump_kw(KwRecord)
    self.bump_kw(LBrace)
    let fields : Array[(String, TypeExpr)] = []
    while !self.peek_kw(RBrace) {
      let n = self.parse_ident()
      self.bump_kw(Colon)
      let t = self.parse_type()
      fields.push((n, t))
      self.eat_kw(Comma)
    }
    self.bump_kw(RBrace)
    return Record(fields)
  }
  // Builtin type constructors which take angle-bracketed parameters.
  let mut ctor : String? = None
  if self.peek_kw(KwTuple) {
    self.bump_kw(KwTuple)
    ctor = Some("tuple")
  } else if self.peek_kw(KwList) {
    self.bump_kw(KwList)
    ctor = Some("list")
  } else if self.peek_kw(KwOption) {
    self.bump_kw(KwOption)
    ctor = Some("option")
  } else if self.peek_kw(KwResult) {
    self.bump_kw(KwResult)
    ctor = Some("result")
  } else if self.peek_kw(KwBorrow) {
    self.bump_kw(KwBorrow)
    ctor = Some("borrow")
  } else if self.peek_kw(KwFuture) {
    self.bump_kw(KwFuture)
    ctor = Some("future")
  } else if self.peek_kw(KwStream) {
    self.bump_kw(KwStream)
    ctor = Some("stream")
  }
  match ctor {
    Some(name) =>
      if self.peek_kw(LAngle) {
        self.bump_kw(LAngle)
        let args : Array[TypeExpr] = []
        if !self.peek_kw(RAngle) {
          while true {
            args.push(self.parse_type())
            if self.peek_kw(Comma) {
              self.bump_kw(Comma)
              if self.peek_kw(RAngle) {
                break
              }
              // If this is list<T, N>, consume N and exit.
              if name == "list" {
                match self.toks[self.i].kind {
                  IntLit(_) => {
                    self.i = self.i + 1
                    // Optional trailing comma before '>'.
                    self.eat_kw(Comma)
                    break
                  }
                  _ => ()
                }
              }
              continue
            }
            break
          }
        }
        self.bump_kw(RAngle)
        Apply(name, args)
      } else {
        // `result`, `future`, `stream` may omit their parameters.
        Apply(name, [])
      }
    None => {
      let name = self.parse_ident()
      if self.peek_kw(LAngle) {
        self.bump_kw(LAngle)
        let args : Array[TypeExpr] = []
        if !self.peek_kw(RAngle) {
          while true {
            args.push(self.parse_type())
            if self.peek_kw(Comma) {
              self.bump_kw(Comma)
              if self.peek_kw(RAngle) {
                break
              }
              continue
            }
            break
          }
        }
        self.bump_kw(RAngle)
        Apply(name, args)
      } else {
        Id(name)
      }
    }
  }
}

///|
fn Parser::parse_named_type_list(
  self : Parser,
  end : TokenKind,
) -> Array[(String, TypeExpr)] raise WitError {
  let out : Array[(String, TypeExpr)] = []
  if self.peek_kw(end) {
    return out
  }
  while true {
    let n = self.parse_ident()
    self.bump_kw(Colon)
    let t = self.parse_type()
    out.push((n, t))
    if self.peek_kw(Comma) {
      self.bump_kw(Comma)
      // Allow trailing comma.
      if self.peek_kw(end) {
        break
      }
      continue
    }
    break
  }
  out
}

///|
fn Parser::parse_ident(self : Parser) -> String raise WitError {
  if self.i >= self.toks.length() {
    raise WitError::Error("unexpected EOF")
  }
  match self.toks[self.i].kind {
    Ident(s) => {
      self.i = self.i + 1
      s
    }
    _ => raise self.err_here("expected identifier")
  }
}

///|
fn Parser::peek_kw(self : Parser, k : TokenKind) -> Bool {
  if self.i >= self.toks.length() {
    return false
  }
  token_kind_is(self.toks[self.i].kind, k)
}

///|
fn Parser::bump_kw(self : Parser, k : TokenKind) -> Unit raise WitError {
  if !self.peek_kw(k) {
    raise self.err_here("unexpected token")
  }
  self.i = self.i + 1
}

///|
fn Parser::eat_kw(self : Parser, k : TokenKind) -> Unit {
  if self.peek_kw(k) {
    self.i = self.i + 1
  }
}

///|
fn Parser::err_here(self : Parser, msg : String) -> WitError {
  if self.i >= self.toks.length() {
    WitError::Error(msg + " at EOF")
  } else {
    let t = self.toks[self.i]
    WitError::Error(msg + " at " + t.line.to_string() + ":" + t.col.to_string())
  }
}

///|
fn token_kind_is(a : TokenKind, b : TokenKind) -> Bool {
  match (a, b) {
    (Ident(_), Ident(_))
    | (IntLit(_), IntLit(_))
    | (StrLit(_), StrLit(_))
    | (KwPackage, KwPackage)
    | (KwInterface, KwInterface)
    | (KwWorld, KwWorld)
    | (KwUse, KwUse)
    | (KwAs, KwAs)
    | (KwWith, KwWith)
    | (KwInclude, KwInclude)
    | (KwType, KwType)
    | (KwResource, KwResource)
    | (KwEnum, KwEnum)
    | (KwFlags, KwFlags)
    | (KwVariant, KwVariant)
    | (KwFunc, KwFunc)
    | (KwImport, KwImport)
    | (KwExport, KwExport)
    | (KwRecord, KwRecord)
    | (KwTuple, KwTuple)
    | (KwList, KwList)
    | (KwOption, KwOption)
    | (KwResult, KwResult)
    | (KwBorrow, KwBorrow)
    | (KwFuture, KwFuture)
    | (KwStream, KwStream)
    | (KwAsync, KwAsync)
    | (LBrace, LBrace)
    | (RBrace, RBrace)
    | (LParen, LParen)
    | (RParen, RParen)
    | (LAngle, LAngle)
    | (RAngle, RAngle)
    | (Colon, Colon)
    | (Semi, Semi)
    | (Comma, Comma)
    | (Dot, Dot)
    | (Slash, Slash)
    | (At, At)
    | (Dash, Dash)
    | (Plus, Plus)
    | (Eq, Eq)
    | (Arrow, Arrow) => true
    _ => false
  }
}
