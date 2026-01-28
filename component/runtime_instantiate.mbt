///|
fn instantiate_component(
  linker : ComponentLinker,
  name : String,
  component : Component,
  overrides : Map[String, ComponentExtern],
  outer_stack : Array[ComponentInstance],
) -> ComponentInstance raise ComponentRuntimeError {
  let stream_table = if outer_stack.length() > 0 {
    outer_stack[outer_stack.length() - 1].stream_table
  } else {
    StreamTable::new()
  }
  let async_state = if outer_stack.length() > 0 {
    outer_stack[outer_stack.length() - 1].async_state
  } else {
    AsyncState::new(stream_table)
  }
  let state = BuildState::new(stream_table, async_state)
  // Reserve handle index 1 for nested component instances so tests that
  // assume a pre-existing handle slot (e.g. resources.wast) see the expected
  // numbering. If we end up running core start code, drop the reservation so
  // start-time allocations can still begin at 1.
  let mut reserved_resource_handle : Int? = Some(
    state.resource_table.alloc({
      type_id: -1,
      rep: 0,
      dtor: None,
      kind: ResourceKind::GuestDefined,
    }),
  )
  let may_enter_self : Array[Bool] = [false]
  let store = linker.get_store()
  for section in component.binary.sections {
    match section.id {
      1 => {
        let core_module = @parser.parse_module(section.payload) catch {
          e => raise CoreModuleParseError(e.to_string())
        }
        state.core_modules.push(core_module)
      }
      2 => {
        let core_instances = parse_core_instance_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for inst in core_instances {
          match inst.expr {
            CoreInstanceExpr::Instantiate(module_idx, args) => {
              if module_idx < 0 || module_idx >= state.core_modules.length() {
                raise InvalidCoreModuleIndex(module_idx)
              }
              let imports = core_imports_from_args(args, state)
              let mod_ = state.core_modules[module_idx]
              // If this module has a start function, don't hold the reserved
              // handle: start code expects fresh resource tables.
              if mod_.start is Some(_) {
                match reserved_resource_handle {
                  Some(h) => {
                    state.resource_table.free(h) |> ignore
                    reserved_resource_handle = None
                  }
                  None => ()
                }
              }
              let module_name = "\{name}::coreinst\{state.core_instances.length()}"
              clear_canon_trap_message()
              let instance = @executor.instantiate_module_with_imports(
                store, mod_, imports,
              ) catch {
                e =>
                  match canon_trap_message[0] {
                    Some(msg) => raise CoreModuleInstantiateError(msg)
                    None => raise CoreModuleInstantiateError(e.to_string())
                  }
              }
              linker.core_linker.register(module_name, instance)
              state.core_instances.push(core_instance_from_module(instance))
            }
            CoreInstanceExpr::InlineExports(exports) =>
              state.core_instances.push(
                build_inline_core_instance(exports, state),
              )
          }
        }
      }
      3 => {
        // Core type section payload is a vec of core typedefs; store each
        // typedef's raw bytes so core:typeidx references work correctly.
        let reader = Reader::new(section.payload)
        let n = reader.read_leb_u32() catch {
          e => raise ComponentParseError(e.to_string())
        }
        for _i in 0..<n {
          let start = reader.pos
          skip_core_typedef(reader) catch {
            e => raise ComponentParseError(e.to_string())
          }
          let end = reader.pos
          state.core_types.push(bytes_sub(section.payload, start, end))
        }
        if !reader.is_eof() {
          raise ComponentParseError("invalid core type section")
        }
      }
      4 => {
        let nested = parse_component(section.payload) catch {
          e => raise ComponentParseError(e.to_string())
        }
        let env = env_instance_from_state("\{name}::env", state, store)
        state.components.push({
          component: nested,
          outer_stack: extend_outer_stack(outer_stack, env),
        })
      }
      5 => {
        let instances = parse_instance_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for inst in instances {
          match inst.expr {
            InstanceExpr::Instantiate(component_idx, args) => {
              if component_idx < 0 || component_idx >= state.components.length() {
                raise InvalidComponentIndex(component_idx)
              }
              let closure = state.components[component_idx]
              let overrides_for_child : Map[String, ComponentExtern] = {}
              for arg in args {
                let ext = resolve_sortidx(arg.sortidx, state)
                overrides_for_child.set(arg.name, ext)
              }
              let nested = instantiate_component(
                linker,
                "\{name}::component\{component_idx}",
                closure.component,
                overrides_for_child,
                closure.outer_stack,
              )
              state.instances.push(nested)
            }
            InstanceExpr::InlineExports(exports) => {
              let export_map : Map[String, ComponentExtern] = {}
              for ex in exports {
                let ext = resolve_sortidx(ex.sortidx, state)
                export_map.set(ex.name, ext)
              }
              let inline_inst : ComponentInstance = {
                name: "\{name}::inline\{state.instances.length()}",
                types: state.types,
                funcs: state.funcs,
                values: state.values,
                components: state.components,
                instances: [],
                resource_table: state.resource_table,
                stream_table: state.stream_table,
                async_state: state.async_state,
                core_modules: state.core_modules,
                core_instances: state.core_instances,
                core_funcs: state.core_funcs,
                core_types: state.core_types,
                core_tables: state.core_tables,
                core_mems: state.core_mems,
                core_globals: state.core_globals,
                core_tags: state.core_tags,
                exports: export_map,
                store,
              }
              state.instances.push(inline_inst)
            }
          }
        }
      }
      6 => {
        let aliases = parse_alias_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for alias_decl in aliases {
          let ext = match alias_decl.target {
            AliasTarget::Export(instance_idx, name) => {
              if instance_idx < 0 || instance_idx >= state.instances.length() {
                raise InvalidInstanceIndex(instance_idx)
              }
              match state.instances[instance_idx].exports.get(name) {
                Some(v) => v
                None => raise UnknownExport(name)
              }
            }
            AliasTarget::CoreExport(core_inst_idx, name) => {
              if core_inst_idx < 0 ||
                core_inst_idx >= state.core_instances.length() {
                raise InvalidCoreInstanceIndex(core_inst_idx)
              }
              let core_inst = state.core_instances[core_inst_idx]
              match alias_decl.sort {
                Sort::Core(0x00) =>
                  match core_inst.funcs.get(name) {
                    Some(v) => ComponentExtern::CoreFunc(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x01) =>
                  match core_inst.tables.get(name) {
                    Some(v) => ComponentExtern::CoreTable(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x02) =>
                  match core_inst.memories.get(name) {
                    Some(v) => ComponentExtern::CoreMemory(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x03) =>
                  match core_inst.globals.get(name) {
                    Some(v) => ComponentExtern::CoreGlobal(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x04) =>
                  match core_inst.tags.get(name) {
                    Some(v) => ComponentExtern::CoreTag(v)
                    None => raise UnknownExport(name)
                  }
                _ => raise AliasTargetMismatch("core export sort")
              }
            }
            AliasTarget::Outer(ct, idx) =>
              resolve_outer_alias(
                extend_outer_stack(
                  outer_stack,
                  env_instance_from_state("\{name}::env", state, store),
                ),
                ct,
                alias_decl.sort,
                idx,
              )
          }
          append_alias(alias_decl.sort, ext, state)
        }
      }
      7 => {
        let types = parse_type_section(section.payload) catch {
          e => raise ComponentParseError(e.to_string())
        }
        for t in types {
          let t2 = match t {
            TypeDef::ResourceType(id, rep, dtor, kind) =>
              if id < 0 {
                TypeDef::ResourceType(
                  linker.alloc_resource_id(),
                  rep,
                  dtor,
                  kind,
                )
              } else {
                t
              }
            _ => t
          }
          state.types.push(Some(t2))
        }
      }
      8 => process_canon_section(section.payload, state, store, may_enter_self)
      9 => {
        let start = parse_start_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        if start.func_idx < 0 || start.func_idx >= state.funcs.length() {
          raise InvalidFuncIndex(start.func_idx)
        }
        let args : Array[ComponentValue] = []
        for idx in start.args {
          if idx < 0 || idx >= state.values.length() {
            raise InvalidValueIndex(idx)
          }
          args.push(state.values[idx])
        }
        let results = call_component_func(
          state.funcs[start.func_idx],
          args,
          store,
          state.resource_table,
          state.async_state,
        )
        if results.length() != start.results {
          raise InvalidStartResultCount(results.length())
        }
        for r in results {
          state.values.push(r)
        }
      }
      10 => {
        let imports = parse_import_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        let import_outer_stack = extend_outer_stack(
          outer_stack,
          env_instance_from_state("\{name}::env", state, store),
        )
        for imp in imports {
          let ext = resolve_import(
            linker,
            overrides,
            import_outer_stack,
            imp.name,
            imp.desc,
            state.types,
            state.core_types,
            store,
          )
          match imp.desc {
            ExternDesc::CoreModuleType(_) =>
              match ext {
                ComponentExtern::CoreModule(m) => state.core_modules.push(m)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::FuncType(_) =>
              match ext {
                ComponentExtern::Func(f) => state.funcs.push(f)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::Value(_) =>
              match ext {
                ComponentExtern::Value(v) => state.values.push(v)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::Type(_) =>
              match ext {
                ComponentExtern::Type(t) => state.types.push(t)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::ComponentType(_) =>
              match ext {
                ComponentExtern::Component(c) => state.components.push(c)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::InstanceType(_) =>
              match ext {
                ComponentExtern::Instance(i) => state.instances.push(i)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
          }
        }
      }
      11 => {
        let exports = parse_export_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for exp in exports {
          let name = decode_export_name(exp.name)
          let ext = resolve_sortidx(exp.sortidx, state)
          state.exports.set(name, ext)
          append_alias(exp.sortidx.sort, ext, state)
        }
      }
      _ => ()
    }
  }
  may_enter_self[0] = true
  let instance : ComponentInstance = {
    name,
    types: state.types,
    funcs: state.funcs,
    values: state.values,
    components: state.components,
    instances: state.instances,
    resource_table: state.resource_table,
    stream_table: state.stream_table,
    async_state: state.async_state,
    core_modules: state.core_modules,
    core_instances: state.core_instances,
    core_funcs: state.core_funcs,
    core_types: state.core_types,
    core_tables: state.core_tables,
    core_mems: state.core_mems,
    core_globals: state.core_globals,
    core_tags: state.core_tags,
    exports: state.exports,
    store,
  }
  linker.register(name, instance)
  instance
}
