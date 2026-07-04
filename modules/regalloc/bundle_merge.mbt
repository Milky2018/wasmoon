///|
pub(all) struct BundleMergeRange {
  id : Int
  class : RegClass
  ranges : Array[ProgramRange]
  fixed_reg : PhysicalReg?
  has_fixed_conflict : Bool
  has_fixed_def : Bool
} derive(Debug)

///|
pub(all) struct BundleMergeEdge {
  target : Int
  source : Int
} derive(Eq, Debug)

///|
pub(all) struct BundleMergePlan {
  range_to_bundle : Array[Int]
  bundle_roots : Array[Int]
  bundle_classes : Array[RegClass]
  bundle_ranges : Array[Array[ProgramRange]]
} derive(Debug)

///|
priv struct BundleMergeSpan {
  span : ProgramRange
  start_ord : Int
  start_before_ord : Int
  end_ord : Int
}

///|
fn bundle_merge_point_order(
  point : ProgramPoint,
  block_order : Array[Int],
  block_point_base : Array[Int],
) -> Int {
  let block_ord = if point.block >= 0 && point.block < block_order.length() {
    block_order[point.block]
  } else {
    point.block
  }
  let base = if block_ord >= 0 && block_ord < block_point_base.length() {
    block_point_base[block_ord]
  } else {
    block_ord * 1_000_000
  }
  base + point.inst
}

///|
fn bundle_merge_same_fixed_reg(a : PhysicalReg, b : PhysicalReg) -> Bool {
  a.id == b.id && a.class == b.class
}

///|
fn bundle_merge_span(
  span : ProgramRange,
  block_order : Array[Int],
  block_point_base : Array[Int],
) -> BundleMergeSpan {
  let start_ord = bundle_merge_point_order(
    span.start,
    block_order,
    block_point_base,
  )
  {
    span,
    start_ord,
    start_before_ord: start_ord - 1,
    end_ord: bundle_merge_point_order(span.end, block_order, block_point_base),
  }
}

///|
fn bundle_merge_clone_spans(
  spans : Array[BundleMergeSpan],
) -> Array[BundleMergeSpan] {
  let out : Array[BundleMergeSpan] = []
  for span in spans {
    out.push(span)
  }
  out
}

///|
fn bundle_merge_insert_sorted(
  spans : Array[BundleMergeSpan],
  insert : BundleMergeSpan,
) -> Unit {
  let insert_ord = insert.start_ord
  let mut lo = 0
  let mut hi = spans.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if spans[mid].start_ord <= insert_ord {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  spans.insert(lo, insert)
}

///|
fn bundle_merge_root_spans_owned(
  root_spans_cache : Array[Array[BundleMergeSpan]?],
  root : Int,
  fallback : Array[BundleMergeSpan],
) -> Array[BundleMergeSpan] {
  match root_spans_cache[root] {
    Some(spans) => spans
    None => {
      let owned = bundle_merge_clone_spans(fallback)
      root_spans_cache[root] = Some(owned)
      owned
    }
  }
}

///|
fn bundle_merge_into_root_spans(
  root_spans_cache : Array[Array[BundleMergeSpan]?],
  target_root : Int,
  target_fallback : Array[BundleMergeSpan],
  source_spans : Array[BundleMergeSpan],
) -> Array[BundleMergeSpan] {
  if source_spans.is_empty() {
    return bundle_merge_root_spans_owned(
      root_spans_cache, target_root, target_fallback,
    )
  }
  if target_fallback.is_empty() {
    root_spans_cache[target_root] = Some(source_spans)
    return source_spans
  }
  let target_spans = bundle_merge_root_spans_owned(
    root_spans_cache, target_root, target_fallback,
  )
  if source_spans.length() == 1 {
    bundle_merge_insert_sorted(target_spans, source_spans[0])
    return target_spans
  }
  let merged : Array[BundleMergeSpan] = []
  let mut i = 0
  let mut j = 0
  while i < target_spans.length() && j < source_spans.length() {
    if target_spans[i].start_ord <= source_spans[j].start_ord {
      merged.push(target_spans[i])
      i += 1
    } else {
      merged.push(source_spans[j])
      j += 1
    }
  }
  while i < target_spans.length() {
    merged.push(target_spans[i])
    i += 1
  }
  while j < source_spans.length() {
    merged.push(source_spans[j])
    j += 1
  }
  root_spans_cache[target_root] = Some(merged)
  merged
}

///|
fn bundle_merge_spans_for_root(
  ranges : Array[BundleMergeRange],
  root_spans_cache : Array[Array[BundleMergeSpan]?],
  root : Int,
  block_order : Array[Int],
  block_point_base : Array[Int],
) -> Array[BundleMergeSpan] {
  match root_spans_cache[root] {
    Some(spans) => spans
    None => {
      let spans : Array[BundleMergeSpan] = []
      for span in ranges[root].ranges {
        spans.push(bundle_merge_span(span, block_order, block_point_base))
      }
      root_spans_cache[root] = Some(spans)
      spans
    }
  }
}

///|
fn bundle_merge_ranges_compatible(
  lhs : BundleMergeRange,
  rhs : BundleMergeRange,
) -> Bool {
  if lhs.class != rhs.class {
    return false
  }
  if lhs.has_fixed_conflict || rhs.has_fixed_conflict {
    return false
  }
  match (lhs.fixed_reg, rhs.fixed_reg) {
    (Some(a), Some(b)) => bundle_merge_same_fixed_reg(a, b)
    _ => true
  }
}

///|
fn bundle_merge_try_edge(
  uf : @unionfind.UnionFind,
  ranges : Array[BundleMergeRange],
  edge : BundleMergeEdge,
  root_fixed_reg_cache : Array[PhysicalReg?],
  root_fixed_conflict_cache : Array[Bool],
  root_has_fixed_def_cache : Array[Bool],
  root_spans_cache : Array[Array[BundleMergeSpan]?],
  block_order : Array[Int],
  block_point_base : Array[Int],
) -> Unit {
  if edge.target < 0 ||
    edge.source < 0 ||
    edge.target >= ranges.length() ||
    edge.source >= ranges.length() {
    return
  }
  let root_a = uf.find(edge.target)
  let root_b = uf.find(edge.source)
  if root_a == root_b {
    return
  }
  let lhs = {
    id: ranges[edge.target].id,
    class: ranges[edge.target].class,
    ranges: ranges[edge.target].ranges,
    fixed_reg: root_fixed_reg_cache[root_a],
    has_fixed_conflict: root_fixed_conflict_cache[root_a],
    has_fixed_def: root_has_fixed_def_cache[root_a],
  }
  let rhs = {
    id: ranges[edge.source].id,
    class: ranges[edge.source].class,
    ranges: ranges[edge.source].ranges,
    fixed_reg: root_fixed_reg_cache[root_b],
    has_fixed_conflict: root_fixed_conflict_cache[root_b],
    has_fixed_def: root_has_fixed_def_cache[root_b],
  }
  if !bundle_merge_ranges_compatible(lhs, rhs) {
    return
  }
  let spans_a = bundle_merge_spans_for_root(
    ranges, root_spans_cache, root_a, block_order, block_point_base,
  )
  let spans_b = bundle_merge_spans_for_root(
    ranges, root_spans_cache, root_b, block_order, block_point_base,
  )
  let adjust_a = root_has_fixed_def_cache[root_a]
  let adjust_b = root_has_fixed_def_cache[root_b]
  if !spans_a.is_empty() && !spans_b.is_empty() {
    let start_a_ord = if adjust_a {
      spans_a[0].start_before_ord
    } else {
      spans_a[0].start_ord
    }
    let end_a_ord = spans_a[spans_a.length() - 1].end_ord
    let start_b_ord = if adjust_b {
      spans_b[0].start_before_ord
    } else {
      spans_b[0].start_ord
    }
    let end_b_ord = spans_b[spans_b.length() - 1].end_ord
    if !(start_a_ord >= end_b_ord || start_b_ord >= end_a_ord) {
      let mut ia = 0
      let mut ib = 0
      let mut range_checks = 0
      while ia < spans_a.length() && ib < spans_b.length() {
        range_checks += 1
        if range_checks > 200 {
          return
        }
        let span_a = spans_a[ia]
        let span_b = spans_b[ib]
        let start_a = if adjust_a {
          span_a.start_before_ord
        } else {
          span_a.start_ord
        }
        let start_b = if adjust_b {
          span_b.start_before_ord
        } else {
          span_b.start_ord
        }
        if start_a >= span_b.end_ord {
          ib += 1
        } else if start_b >= span_a.end_ord {
          ia += 1
        } else {
          return
        }
      }
    }
  }
  if !uf.union_into(root_b, root_a) {
    return
  }
  let new_root = uf.find(root_a)
  let old_root = if new_root == root_a { root_b } else { root_a }
  let merged_fixed_def = root_has_fixed_def_cache[root_a] ||
    root_has_fixed_def_cache[root_b]
  root_has_fixed_def_cache[new_root] = merged_fixed_def
  root_has_fixed_def_cache[old_root] = merged_fixed_def
  let merged_fixed = match
    (root_fixed_reg_cache[root_a], root_fixed_reg_cache[root_b]) {
    (Some(preg), _) => Some(preg)
    (_, Some(preg)) => Some(preg)
    _ => None
  }
  root_fixed_reg_cache[new_root] = merged_fixed
  root_fixed_reg_cache[old_root] = merged_fixed
  root_fixed_conflict_cache[new_root] = false
  root_fixed_conflict_cache[old_root] = false
  let (target_spans, source_spans) = if new_root == root_a {
    (spans_a, spans_b)
  } else {
    (spans_b, spans_a)
  }
  let merged_spans = bundle_merge_into_root_spans(
    root_spans_cache, new_root, target_spans, source_spans,
  )
  root_spans_cache[new_root] = Some(merged_spans)
  root_spans_cache[old_root] = None
}

///|
pub fn plan_bundle_merges(
  ranges : Array[BundleMergeRange],
  edges : Array[BundleMergeEdge],
  block_order : Array[Int],
  block_lengths : Array[Int],
) -> BundleMergePlan {
  let n = ranges.length()
  let uf = @unionfind.UnionFind::new(n)
  let block_point_base : Array[Int] = []
  let mut point_cursor = 0
  for block_ord in 0..<block_lengths.length() {
    block_point_base.push(point_cursor)
    point_cursor += block_lengths[block_ord]
  }
  let root_fixed_reg_cache : Array[PhysicalReg?] = []
  let root_fixed_conflict_cache : Array[Bool] = []
  let root_has_fixed_def_cache : Array[Bool] = []
  let root_spans_cache : Array[Array[BundleMergeSpan]?] = Array::make(n, None)
  for range in ranges {
    root_fixed_reg_cache.push(range.fixed_reg)
    root_fixed_conflict_cache.push(range.has_fixed_conflict)
    root_has_fixed_def_cache.push(range.has_fixed_def)
  }
  for edge in edges {
    bundle_merge_try_edge(
      uf, ranges, edge, root_fixed_reg_cache, root_fixed_conflict_cache, root_has_fixed_def_cache,
      root_spans_cache, block_order, block_point_base,
    )
  }
  let range_to_bundle = Array::make(n, -1)
  let root_to_bundle = Array::make(n, -1)
  let bundle_roots : Array[Int] = []
  let bundle_classes : Array[RegClass] = []
  for range_idx in 0..<n {
    let root = uf.find(range_idx)
    let bundle_id = if root_to_bundle[root] >= 0 {
      root_to_bundle[root]
    } else {
      let id = bundle_roots.length()
      root_to_bundle[root] = id
      bundle_roots.push(root)
      bundle_classes.push(ranges[range_idx].class)
      id
    }
    range_to_bundle[range_idx] = bundle_id
  }
  let bundle_ranges : Array[Array[ProgramRange]] = []
  for root in bundle_roots {
    let out : Array[ProgramRange] = []
    match root_spans_cache[root] {
      Some(spans) =>
        for span in spans {
          out.push(span.span)
        }
      None =>
        for span in ranges[root].ranges {
          out.push(span)
        }
    }
    bundle_ranges.push(out)
  }
  { range_to_bundle, bundle_roots, bundle_classes, bundle_ranges }
}
