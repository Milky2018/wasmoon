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
      .unwrap_or_else(() => {
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
    .unwrap_or_else(() => {
      raise WitError::Error("internal: missing resolved root package")
    })
  let out_deps : Array[Package] = []
  for k in order {
    if k != root_key {
      out_deps.push(
        resolved_pkgs
        .get(k)
        .unwrap_or_else(() => {
          raise WitError::Error(
            "internal: missing resolved package `" + k + "`",
          )
        }),
      )
    }
  }
  { root: root_pkg, deps: out_deps }
}

// ============================================================
// wasm-tools Parity Helpers (Partial)
// ============================================================

///|
/// "Importize" a world: drop all original imports and convert exports into imports.
///
/// This mirrors the `wasm-tools component wit --importize-world` behavior:
/// the resulting world describes the interface needed to *import* a component
/// that implements the original world's exports.
pub fn importize_world(world : World, out_name : String) -> World {
  let items : Array[WorldItem] = []
  for wi in world.items {
    match wi {
      Import(_) | ImportFunc(_) | ImportInlineInterface(_, _) =>
        // Drop original imports.
        ()
      Export(p) => items.push(Import(p))
      ExportFunc(f) => items.push(ImportFunc(f))
      ExportInlineInterface(n, iface) =>
        items.push(ImportInlineInterface(n, iface))
      // Keep non import/export items (types, includes, use, etc.) so any
      // exported signatures that reference them remain valid.
      _ => items.push(wi)
    }
  }
  { name: out_name, items }
}

///|
/// Build a "printable" resolved package that contains only non-world top items
/// plus a single importized world (and inlined `deps` as `nested`).
pub fn importize_resolved_package(
  res : ResolveResult,
  world_name : String,
  out_world_name? : String? = None,
) -> Package raise WitError {
  let mut target : World? = None
  let non_world_items : Array[TopItem] = []
  for it in res.root.items {
    match it {
      World(w) => if w.name == world_name { target = Some(w) } else { () }
      _ => non_world_items.push(it)
    }
  }
  let w = target.unwrap_or_else(() => {
    raise WitError::Error("unknown world `" + world_name + "`")
  })
  let out_name = out_world_name.unwrap_or(world_name + "-importized")
  let out_world = importize_world(w, out_name)
  let items : Array[TopItem] = []
  for it in non_world_items {
    items.push(it)
  }
  items.push(World(out_world))
  { name: res.root.name, version: res.root.version, items, nested: res.deps }
}

///|
/// Importize the first world found in a decoded/parsed package.
///
/// This is primarily used for `--importize` with a component binary input.
pub fn importize_first_world_in_package(
  pkg : Package,
  out_world_name? : String? = None,
) -> Package raise WitError {
  let mut target : World? = None
  let non_world_items : Array[TopItem] = []
  for it in pkg.items {
    match it {
      World(w) => if target is None { target = Some(w) } else { () }
      _ => non_world_items.push(it)
    }
  }
  let w = target.unwrap_or_else(() => {
    raise WitError::Error("no world found in input")
  })
  let out_name = out_world_name.unwrap_or(w.name + "-importized")
  let out_world = importize_world(w, out_name)
  let items : Array[TopItem] = []
  for it in non_world_items {
    items.push(it)
  }
  items.push(World(out_world))
  { name: pkg.name, version: pkg.version, items, nested: pkg.nested }
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
      .unwrap_or_else(() => {
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
      .unwrap_or_else(() => raise WitError::Error("internal: missing interface"))
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
      .unwrap_or_else(() => raise WitError::Error("internal: missing interface"))
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
      .unwrap_or_else(() => raise WitError::Error("internal: missing world"))
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
      .unwrap_or_else(() => raise WitError::Error("internal: missing world"))
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
        .unwrap_or_else(() => {
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
        .unwrap_or_else(() => {
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
    .unwrap_or_else(() => {
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
      .unwrap_or_else(() => {
        raise WitError::Error("unknown package `" + pkg_key + "`")
      })
      |> ignore
      let k = pkg_key + "/" + name
      resolved_worlds
      .get(k)
      .unwrap_or_else(() => {
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
    .unwrap_or_else(() => {
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
      .unwrap_or_else(() => raise WitError::Error("internal: missing iface ref")),
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
