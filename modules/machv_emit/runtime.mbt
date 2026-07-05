// JIT Runtime Support
// Manages compiled code caching and execution
//
// This module provides:
// 1. Code cache for storing compiled functions
// 2. Executable memory management abstraction
// 3. Code unloading support

// ============ Compiled Function ============

///|
/// Information about a GC safepoint in generated code
pub struct GcSafepoint {
  /// Offset in generated machine code where this safepoint is
  code_offset : Int
  /// Which virtual registers contain live GC references at this point
  live_refs : Array[Int]
  /// Additional metadata (e.g., return address for stack unwinding)
  metadata : Int64
} derive(Debug)

///|
pub fn GcSafepoint::new(
  code_offset : Int,
  live_refs : Array[Int],
  metadata : Int64,
) -> GcSafepoint {
  { code_offset, live_refs, metadata }
}

///|
fn append_u32_le(buf : Array[Byte], value : Int) -> Unit {
  buf.push((value & 0xFF).to_byte())
  buf.push(((value >> 8) & 0xFF).to_byte())
  buf.push(((value >> 16) & 0xFF).to_byte())
  buf.push(((value >> 24) & 0xFF).to_byte())
}

///|
/// Build a compact stackmap blob for allocation safepoints.
/// Format v1:
///   u32 version (=1)
///   u32 safepoint_count
///   u32 root_count[safepoint_count]
fn build_gc_stackmap_blob(root_counts : Array[Int]) -> Bytes {
  if root_counts.length() == 0 {
    return b""
  }
  let bytes : Array[Byte] = []
  append_u32_le(bytes, 1)
  append_u32_le(bytes, root_counts.length())
  for count in root_counts {
    append_u32_le(bytes, count)
  }
  Bytes::from_array(bytes)
}

///|
fn safepoint_metadata_to_root_count(metadata : Int64) -> Int {
  if metadata <= 0L {
    return 0
  }
  if metadata > @types.I32_MAX.to_int64() {
    @types.I32_MAX
  } else {
    metadata.to_int()
  }
}

///|
fn encode_stackmap_root_count(root_count : Int) -> Int {
  if root_count <= 0 {
    0
  } else if root_count > @types.I32_MAX {
    @types.I32_MAX
  } else {
    root_count
  }
}

///|
fn has_stackmap_live_ref_indices(safepoints : Array[GcSafepoint]) -> Bool {
  for safepoint in safepoints {
    if safepoint.live_refs.length() > 0 {
      return true
    }
  }
  false
}

///|
/// Build stackmap blob v2 with optional per-safepoint root-index lists.
/// Format v2:
///   u32 version (=2)
///   u32 safepoint_count
///   repeated safepoint_count times:
///     u32 root_count
///     u32 root_index_count
///     u32 root_indices[root_index_count]
fn build_gc_stackmap_blob_v2(
  safepoints : Array[GcSafepoint],
  fallback_root_counts : Array[Int],
) -> Bytes {
  if safepoints.length() == 0 {
    return b""
  }
  let bytes : Array[Byte] = []
  append_u32_le(bytes, 2)
  append_u32_le(bytes, safepoints.length())
  for i, safepoint in safepoints {
    let fallback_root_count = if i < fallback_root_counts.length() {
      fallback_root_counts[i]
    } else {
      safepoint.live_refs.length()
    }
    let metadata_root_count = safepoint_metadata_to_root_count(
      safepoint.metadata,
    )
    let mut root_count = encode_stackmap_root_count(
      if metadata_root_count > 0 {
        metadata_root_count
      } else {
        fallback_root_count
      },
    )
    let valid_indices : Array[Int] = []
    for live_ref in safepoint.live_refs {
      if live_ref >= 0 && live_ref <= @types.I32_MAX {
        valid_indices.push(live_ref)
      }
    }
    if valid_indices.length() > 0 {
      if root_count <= 0 || root_count > valid_indices.length() {
        root_count = valid_indices.length()
      }
      append_u32_le(bytes, root_count)
      append_u32_le(bytes, root_count)
      for idx in 0..<root_count {
        append_u32_le(bytes, valid_indices[idx])
      }
    } else {
      append_u32_le(bytes, root_count)
      append_u32_le(bytes, 0)
    }
  }
  Bytes::from_array(bytes)
}

///|
/// A compiled function ready for execution
pub struct CompiledFunction {
  // Function name or identifier
  name : String
  // The compiled machine code bytes
  code : MachineCode
  // Entry point offset (usually 0)
  entry_offset : Int
  // Size of the code in bytes
  code_size : Int
  // Stack frame size needed
  frame_size : Int
  // GC safepoint metadata (per-function)
  gc_safepoints : Array[GcSafepoint]
  // Compact stack-map payload for GC roots
  gc_stackmap_blob : Bytes
  // Whether this function is currently valid
  mut valid : Bool
}

///|
pub fn CompiledFunction::new(
  name : String,
  code : MachineCode,
  frame_size : Int,
  gc_safepoints? : Array[GcSafepoint] = [],
  gc_stackmap_blob? : Bytes = b"",
) -> CompiledFunction {
  let derived_root_counts = code.get_gc_safepoint_root_counts()
  let derived_root_indices = code.get_gc_safepoint_root_indices()
  let resolved_gc_safepoints : Array[GcSafepoint] = if gc_safepoints.length() >
    0 {
    gc_safepoints
  } else {
    let derived : Array[GcSafepoint] = []
    let offsets = code.get_gc_safepoint_offsets()
    for i, offset in offsets {
      let metadata = if i < derived_root_counts.length() {
        derived_root_counts[i].to_int64()
      } else {
        0L
      }
      let live_refs = if i < derived_root_indices.length() {
        derived_root_indices[i]
      } else {
        []
      }
      derived.push(GcSafepoint::new(offset, live_refs, metadata))
    }
    derived
  }
  let stackmap_root_counts = if derived_root_counts.length() > 0 {
    derived_root_counts
  } else if resolved_gc_safepoints.length() > 0 {
    let counts : Array[Int] = []
    for safepoint in resolved_gc_safepoints {
      counts.push(safepoint_metadata_to_root_count(safepoint.metadata))
    }
    counts
  } else {
    []
  }
  let resolved_gc_stackmap_blob = if gc_stackmap_blob.length() > 0 {
    gc_stackmap_blob
  } else if has_stackmap_live_ref_indices(resolved_gc_safepoints) {
    build_gc_stackmap_blob_v2(resolved_gc_safepoints, stackmap_root_counts)
  } else {
    build_gc_stackmap_blob(stackmap_root_counts)
  }
  {
    name,
    code,
    entry_offset: 0,
    code_size: code.size(),
    frame_size,
    gc_safepoints: resolved_gc_safepoints,
    gc_stackmap_blob: resolved_gc_stackmap_blob,
    valid: true,
  }
}

///|
/// Invalidate this compiled function (mark for recompilation)
pub fn CompiledFunction::invalidate(self : CompiledFunction) -> Unit {
  self.valid = false
}

///|
/// Check if the function is still valid
pub fn CompiledFunction::is_valid(self : CompiledFunction) -> Bool {
  self.valid
}

///|
/// Get the machine code bytes
pub fn CompiledFunction::get_code(self : CompiledFunction) -> Array[Int] {
  self.code.get_bytes()
}

///|
/// Get direct function address fixups
pub fn CompiledFunction::get_func_addr_fixups(
  self : CompiledFunction,
) -> Array[FuncAddrFixup] {
  self.code.get_func_addr_fixups()
}

///|
/// Get direct function call fixups
pub fn CompiledFunction::get_call_fixups(
  self : CompiledFunction,
) -> Array[CallFixup] {
  self.code.get_call_fixups()
}

///|
/// Get GC safepoint metadata for this function.
pub fn CompiledFunction::get_gc_safepoints(
  self : CompiledFunction,
) -> Array[GcSafepoint] {
  self.gc_safepoints
}

///|
/// Get GC stack-map payload bytes for this function.
pub fn CompiledFunction::get_gc_stackmap_blob(self : CompiledFunction) -> Bytes {
  self.gc_stackmap_blob
}

///|
fn CompiledFunction::to_string(self : CompiledFunction) -> String {
  let status = if self.valid { "valid" } else { "invalid" }
  "CompiledFunction(\{self.name}, \{self.code_size} bytes, frame=\{self.frame_size}, safepoints=\{self.gc_safepoints.length()}, \{status})"
}

///|
pub impl Show for CompiledFunction with fn output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Code Cache ============

///|
/// Cache for storing compiled functions
struct CodeCache {
  // Function index -> compiled function
  functions : Map[Int, CompiledFunction]
  // Total size of all cached code
  mut total_size : Int
  // Maximum cache size (0 = unlimited)
  max_size : Int
  // Cache statistics
  mut hits : Int
  mut misses : Int
}

///|
pub fn CodeCache::new(max_size : Int) -> CodeCache {
  { functions: {}, total_size: 0, max_size, hits: 0, misses: 0 }
}

///|
/// Look up a compiled function by index
pub fn CodeCache::get(self : CodeCache, func_idx : Int) -> CompiledFunction? {
  match self.functions.get(func_idx) {
    Some(func) =>
      if func.valid {
        self.hits = self.hits + 1
        Some(func)
      } else {
        self.misses = self.misses + 1
        None
      }
    None => {
      self.misses = self.misses + 1
      None
    }
  }
}

///|
/// Check if a function is cached and valid
pub fn CodeCache::contains(self : CodeCache, func_idx : Int) -> Bool {
  match self.functions.get(func_idx) {
    Some(func) => func.valid
    None => false
  }
}

///|
/// Insert a compiled function into the cache
pub fn CodeCache::insert(
  self : CodeCache,
  func_idx : Int,
  func : CompiledFunction,
) -> Unit {
  // Check if we need to evict
  if self.max_size > 0 && self.total_size + func.code_size > self.max_size {
    self.evict_lru()
  }

  // Remove old version if exists
  if self.functions.get(func_idx) is Some(old) {
    self.total_size = self.total_size - old.code_size
  }
  self.total_size = self.total_size + func.code_size
  self.functions.set(func_idx, func)
}

///|
/// Invalidate a cached function
pub fn CodeCache::invalidate(self : CodeCache, func_idx : Int) -> Unit {
  if self.functions.get(func_idx) is Some(func) {
    func.invalidate()
  }
}

///|
/// Remove a function from the cache
pub fn CodeCache::remove(self : CodeCache, func_idx : Int) -> Unit {
  if self.functions.get(func_idx) is Some(func) {
    self.total_size = self.total_size - func.code_size
    self.functions.remove(func_idx)
  }
}

///|
/// Clear all cached functions
pub fn CodeCache::clear(self : CodeCache) -> Unit {
  self.functions.clear()
  self.total_size = 0
}

///|
/// Evict least recently used function (simple strategy: first invalid, then smallest)
fn CodeCache::evict_lru(self : CodeCache) -> Unit {
  // First try to evict invalid functions
  let mut to_remove : Int? = None
  for entry in self.functions {
    let (idx, func) = entry
    if !func.valid {
      to_remove = Some(idx)
      break
    }
  }
  if to_remove is Some(idx) {
    self.remove(idx)
    return
  }

  // If no invalid functions, evict smallest
  let mut smallest_idx : Int? = None
  let mut smallest_size = 0x7FFFFFFF // Max int
  for entry in self.functions {
    let (idx, func) = entry
    if func.code_size < smallest_size {
      smallest_size = func.code_size
      smallest_idx = Some(idx)
    }
  }
  if smallest_idx is Some(idx) {
    self.remove(idx)
  }
}

///|
/// Get cache statistics
pub fn CodeCache::stats(self : CodeCache) -> (Int, Int, Int, Int) {
  // (total_size, num_functions, hits, misses)
  let mut num_funcs = 0
  for _ in self.functions {
    num_funcs = num_funcs + 1
  }
  (self.total_size, num_funcs, self.hits, self.misses)
}

///|
fn CodeCache::to_string(self : CodeCache) -> String {
  let (size, count, hits, misses) = self.stats()
  let hit_rate = if hits + misses > 0 {
    hits * 100 / (hits + misses)
  } else {
    0
  }
  "CodeCache(\{count} functions, \{size} bytes, hit rate \{hit_rate}%)"
}

///|
pub impl Show for CodeCache with fn output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Executable Memory Region ============

///|
/// Represents a region of memory that can hold executable code
/// (Abstraction - actual executable memory requires platform-specific implementation)
struct ExecutableRegion {
  // Identifier for this region
  id : Int
  // Base address (simulated)
  base_addr : Int
  // Size of the region
  size : Int
  // Current write position
  mut write_pos : Int
  // The code bytes stored in this region
  code : Array[Int]
  // Whether the region is finalized (read-only)
  mut finalized : Bool
}

///|
pub fn ExecutableRegion::new(id : Int, size : Int) -> ExecutableRegion {
  {
    id,
    base_addr: id * 0x10000, // Simulated base address
    size,
    write_pos: 0,
    code: [],
    finalized: false,
  }
}

///|
/// Write code bytes to the region
pub fn ExecutableRegion::write(
  self : ExecutableRegion,
  bytes : Array[Int],
) -> Result[Int, String] {
  if self.finalized {
    return Err("Region is finalized, cannot write")
  }
  if self.write_pos + bytes.length() > self.size {
    return Err("Region overflow")
  }
  let offset = self.write_pos
  for b in bytes {
    self.code.push(b)
  }
  self.write_pos = self.write_pos + bytes.length()
  Ok(offset)
}

///|
/// Finalize the region (make it executable, no more writes)
pub fn ExecutableRegion::finalize(self : ExecutableRegion) -> Unit {
  self.finalized = true
}

///|
/// Get the effective address for a given offset
pub fn ExecutableRegion::address_at(
  self : ExecutableRegion,
  offset : Int,
) -> Int {
  self.base_addr + offset
}

///|
/// Get remaining space in the region
pub fn ExecutableRegion::remaining(self : ExecutableRegion) -> Int {
  self.size - self.write_pos
}

///|
/// Read code at a given offset
pub fn ExecutableRegion::read_at(
  self : ExecutableRegion,
  offset : Int,
  length : Int,
) -> Array[Int] {
  let result : Array[Int] = []
  let end = @cmp.minimum(offset + length, self.code.length())
  for i in offset..<end {
    result.push(self.code[i])
  }
  result
}

///|
fn ExecutableRegion::to_string(self : ExecutableRegion) -> String {
  let status = if self.finalized { "finalized" } else { "writable" }
  "ExecutableRegion(\{self.id}, base=0x\{self.base_addr.to_hex()}, \{self.write_pos}/\{self.size} bytes, \{status})"
}

///|
pub impl Show for ExecutableRegion with fn output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Memory Manager ============

///|
/// Manages executable memory regions
struct MemoryManager {
  // All allocated regions
  regions : Array[ExecutableRegion]
  // Default region size
  default_region_size : Int
  // Next region ID
  mut next_id : Int
  // Current region for writing
  mut current_region : Int?
}

///|
pub fn MemoryManager::new(default_region_size : Int) -> MemoryManager {
  { regions: [], default_region_size, next_id: 0, current_region: None }
}

///|
/// Allocate a new executable region
pub fn MemoryManager::alloc_region(
  self : MemoryManager,
  size : Int,
) -> ExecutableRegion {
  let region = ExecutableRegion::new(self.next_id, size)
  self.regions.push(region)
  self.next_id = self.next_id + 1
  self.current_region = Some(self.regions.length() - 1)
  region
}

///|
/// Get the current region, allocating if needed
pub fn MemoryManager::get_current_region(
  self : MemoryManager,
) -> ExecutableRegion {
  match self.current_region {
    Some(idx) => {
      let region = self.regions[idx]
      if region.finalized || region.remaining() < 256 {
        // Need a new region
        self.alloc_region(self.default_region_size)
      } else {
        region
      }
    }
    None => self.alloc_region(self.default_region_size)
  }
}

///|
/// Write code to the current region
pub fn MemoryManager::write_code(
  self : MemoryManager,
  code : MachineCode,
) -> Result[(ExecutableRegion, Int), String] {
  let bytes = code.get_bytes()
  let region = self.get_current_region()

  // Check if we need a larger region
  if bytes.length() > region.remaining() {
    // Allocate a new region large enough
    let new_size = if bytes.length() > self.default_region_size {
      bytes.length() * 2
    } else {
      self.default_region_size
    }
    let new_region = self.alloc_region(new_size)
    match new_region.write(bytes) {
      Ok(offset) => Ok((new_region, offset))
      Err(e) => Err(e)
    }
  } else {
    match region.write(bytes) {
      Ok(offset) => Ok((region, offset))
      Err(e) => Err(e)
    }
  }
}

///|
/// Finalize all regions
pub fn MemoryManager::finalize_all(self : MemoryManager) -> Unit {
  for region in self.regions {
    region.finalize()
  }
}

///|
/// Get total allocated memory
pub fn MemoryManager::total_allocated(self : MemoryManager) -> Int {
  let mut total = 0
  for region in self.regions {
    total = total + region.size
  }
  total
}

///|
/// Get total used memory
pub fn MemoryManager::total_used(self : MemoryManager) -> Int {
  let mut total = 0
  for region in self.regions {
    total = total + region.write_pos
  }
  total
}

///|
fn MemoryManager::to_string(self : MemoryManager) -> String {
  let used = self.total_used()
  let allocated = self.total_allocated()
  "MemoryManager(\{self.regions.length()} regions, \{used}/\{allocated} bytes used)"
}

///|
pub impl Show for MemoryManager with fn output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ JIT Runtime ============

///|
/// Complete JIT runtime combining code cache and memory management
struct JITRuntime {
  // Code cache
  cache : CodeCache
  // Memory manager
  memory : MemoryManager
  // Compilation statistics
  mut compilations : Int
  mut recompilations : Int
}

///|
pub fn JITRuntime::new(cache_size : Int, region_size : Int) -> JITRuntime {
  {
    cache: CodeCache::new(cache_size),
    memory: MemoryManager::new(region_size),
    compilations: 0,
    recompilations: 0,
  }
}

///|
/// Register a compiled function
pub fn JITRuntime::register(
  self : JITRuntime,
  func_idx : Int,
  func : CompiledFunction,
) -> Result[Int, String] {
  // Write code to memory
  match self.memory.write_code(func.code) {
    Ok((region, offset)) => {
      // Update compilation stats
      if self.cache.contains(func_idx) {
        self.recompilations = self.recompilations + 1
      } else {
        self.compilations = self.compilations + 1
      }

      // Add to cache
      self.cache.insert(func_idx, func)

      // Return the effective address
      Ok(region.address_at(offset))
    }
    Err(e) => Err(e)
  }
}

///|
/// Look up a compiled function
pub fn JITRuntime::lookup(
  self : JITRuntime,
  func_idx : Int,
) -> CompiledFunction? {
  self.cache.get(func_idx)
}

///|
/// Invalidate a function (will be recompiled on next call)
pub fn JITRuntime::invalidate(self : JITRuntime, func_idx : Int) -> Unit {
  self.cache.invalidate(func_idx)
}

///|
/// Clear all compiled code
pub fn JITRuntime::clear(self : JITRuntime) -> Unit {
  self.cache.clear()
  // Note: Memory regions are not freed, just marked as invalid in cache
}

///|
/// Get runtime statistics
pub fn JITRuntime::stats(
  self : JITRuntime,
) -> (Int, Int, Int, Int, Int, Int, Int) {
  let (cache_size, cache_count, hits, misses) = self.cache.stats()
  let mem_used = self.memory.total_used()
  (
    self.compilations,
    self.recompilations,
    cache_count,
    cache_size,
    hits,
    misses,
    mem_used,
  )
}

///|
fn JITRuntime::to_string(self : JITRuntime) -> String {
  let (comps, recomps, count, _, hits, misses, mem_used) = self.stats()
  "JITRuntime(compiled=\{comps}, recompiled=\{recomps}, cached=\{count}, hits=\{hits}, misses=\{misses}, memory=\{mem_used})"
}

///|
pub impl Show for JITRuntime with fn output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Helper Functions ============

///|
/// Convert an integer to hex string
fn Int::to_hex(self : Int) -> String {
  @types.int_to_hex(self)
}
