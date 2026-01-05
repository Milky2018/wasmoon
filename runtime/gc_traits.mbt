// GC Trait Abstractions for Wasmoon
//
// This module defines two core traits for GC runtime:
// 1. GcHeap - Low-level object storage and access
// 2. GcRuntime - Runtime GC coordination (barriers, collection)
//
// GcCompiler trait is defined in vcode/ package due to dependencies.

// ============================================================
// GcHeap - Object Storage Layer
// ============================================================
//
// Responsible for:
// - Allocating struct and array objects
// - Accessing object fields and elements
// - Tracking object types
//
// Implementations:
// - MarkSweepHeap: Simple mark-sweep with tombstones
// - CopyingHeap: Semi-space copying collector
// - BumpAllocHeap: Fast bump allocation, no collection (for arenas)

///|
/// Low-level GC heap interface for object storage
pub(open) trait GcHeap {
  // === Allocation ===

  /// Allocate a struct with given type index and field values
  /// Returns the object reference index
  alloc_struct(Self, Int, Array[@types.Value]) -> Int

  /// Allocate an array with given type index and elements
  /// Returns the object reference index
  alloc_array(Self, Int, Array[@types.Value]) -> Int

  // === Object Access ===

  /// Get a struct field value
  struct_get(Self, Int, Int) -> @types.Value raise RuntimeError

  /// Set a struct field value
  struct_set(Self, Int, Int, @types.Value) -> Unit raise RuntimeError

  /// Get array length
  array_len(Self, Int) -> Int raise RuntimeError

  /// Get an array element
  array_get(Self, Int, Int) -> @types.Value raise RuntimeError

  /// Set an array element
  array_set(Self, Int, Int, @types.Value) -> Unit raise RuntimeError

  /// Fill array elements with a value
  array_fill(Self, Int, Int, @types.Value, Int) -> Unit raise RuntimeError

  /// Copy elements between arrays
  array_copy(Self, Int, Int, Int, Int, Int) -> Unit raise RuntimeError

  // === Type Information ===

  /// Get the type index of an object
  get_type_idx(Self, Int) -> Int raise RuntimeError

  /// Check if an object reference is valid and alive
  is_valid(Self, Int) -> Bool
}

// ============================================================
// GcRuntime - Runtime GC Coordination
// ============================================================
//
// Responsible for:
// - Triggering garbage collection
// - Managing roots (stack, globals)
// - Write/read barriers for incremental/concurrent GC
// - GC statistics and tuning
//
// Implementations:
// - StopTheWorldRuntime: Simple stop-the-world collection
// - IncrementalRuntime: Incremental collection with write barriers
// - NoGcRuntime: Never collect (for short-lived programs)

///|
/// GC statistics
pub struct GcStats {
  /// Total allocated objects (including freed slots)
  total_slots : Int
  /// Currently live objects
  live_objects : Int
  /// Free slots available for reuse
  free_slots : Int
  /// Number of GC cycles performed
  collections : Int
  /// Total bytes allocated (if tracked)
  bytes_allocated : Int64
  /// Total bytes collected (if tracked)
  bytes_collected : Int64
} derive(Show)

///|
/// Runtime GC coordination interface
pub(open) trait GcRuntime {
  // === Collection Control ===

  /// Check if GC should be triggered (called after allocation)
  should_collect(Self) -> Bool

  /// Perform garbage collection with given roots
  /// Roots are values from stack and globals that keep objects alive
  collect(Self, Array[@types.Value]) -> Unit

  /// Force a full GC cycle regardless of threshold
  force_collect(Self, Array[@types.Value]) -> Unit

  // === Barriers (for incremental/concurrent GC) ===

  /// Write barrier: called BEFORE writing a reference field
  /// For simple stop-the-world GC, this is a no-op
  /// For incremental GC, this maintains the tri-color invariant
  ///
  /// obj_idx: object being modified
  /// old_value: current value (being overwritten)
  /// new_value: new value being stored
  write_barrier_pre(Self, Int, @types.Value, @types.Value) -> Unit

  /// Write barrier: called AFTER writing a reference field
  /// Used by some GC algorithms (e.g., remembered sets)
  write_barrier_post(Self, Int, @types.Value) -> Unit

  /// Read barrier: called before reading a reference field
  /// For most GCs, this is a no-op
  /// For concurrent compacting GC, this handles forwarding
  read_barrier(Self, Int) -> @types.Value

  // === Statistics ===

  /// Get GC statistics
  stats(Self) -> GcStats

  /// Get number of collections performed
  collection_count(Self) -> Int

  /// Set the collection threshold (interpretation depends on implementation)
  set_threshold(Self, Int) -> Unit

  /// Get current threshold
  get_threshold(Self) -> Int
}

// ============================================================
// Combined GC Manager
// ============================================================
//
// Combines heap and runtime into a unified interface.
// This is what Store will use.

///|
/// Combined GC manager interface
pub(open) trait GcManager {
  // === Heap Operations (delegated) ===
  alloc_struct(Self, Int, Array[@types.Value]) -> Int
  alloc_array(Self, Int, Array[@types.Value]) -> Int
  struct_get(Self, Int, Int) -> @types.Value raise RuntimeError
  struct_set(Self, Int, Int, @types.Value) -> Unit raise RuntimeError
  array_len(Self, Int) -> Int raise RuntimeError
  array_get(Self, Int, Int) -> @types.Value raise RuntimeError
  array_set(Self, Int, Int, @types.Value) -> Unit raise RuntimeError
  array_fill(Self, Int, Int, @types.Value, Int) -> Unit raise RuntimeError
  array_copy(Self, Int, Int, Int, Int, Int) -> Unit raise RuntimeError
  get_type_idx(Self, Int) -> Int raise RuntimeError
  is_valid(Self, Int) -> Bool

  // === Runtime Operations (delegated) ===
  should_collect(Self) -> Bool
  collect(Self, Array[@types.Value]) -> Unit
  stats(Self) -> GcStats

  // === Barriers ===
  write_barrier(Self, Int, @types.Value, @types.Value) -> Unit
}
