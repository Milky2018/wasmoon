///|
/// Count function imports without allocating a filtered list.
pub fn count_func_imports(imports : Array[Import]) -> Int32 {
  let mut count = 0
  for imp in imports {
    if imp.desc is Func(_) {
      count = count + 1
    }
  }
  count
}

///|
/// Count global imports without allocating a filtered list.
pub fn count_global_imports(imports : Array[Import]) -> Int32 {
  let mut count = 0
  for imp in imports {
    if imp.desc is Global(_) {
      count = count + 1
    }
  }
  count
}

///|
/// Count tag imports without allocating a filtered list.
pub fn count_tag_imports(imports : Array[Import]) -> Int32 {
  let mut count = 0
  for imp in imports {
    if imp.desc is Tag(_) {
      count = count + 1
    }
  }
  count
}
