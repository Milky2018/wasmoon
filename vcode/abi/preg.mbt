///|
/// Physical register - a real machine register
pub(all) struct PReg {
  index : Int // Register number (e.g., x0-x30 for AArch64)
  class : RegClass
}

///|
fn PReg::to_string(self : PReg) -> String {
  match self.class {
    Int => "x\{self.index}"
    Float32 | Float64 => "d\{self.index}"
    Vector => "v\{self.index}" // SIMD vector registers v0-v31
  }
}

///|
pub impl Show for PReg with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Spilled Register Encoding ============
// For CallIndirect with many spilled args, we encode the spill slot in the register index.
// Register indices >= SPILL_SLOT_BASE represent spilled values at slot (index - SPILL_SLOT_BASE).

///|
/// Base index for encoding spilled operands in PReg.index
/// PReg with index >= 256 represents a spilled value at slot (index - 256)
pub let spill_slot_base : Int = 256

///|
/// Check if a physical register represents a spilled value
pub fn PReg::is_spilled(self : PReg) -> Bool {
  self.index >= spill_slot_base
}

///|
/// Get the spill slot for a spilled register (returns -1 if not spilled)
pub fn PReg::get_spill_slot(self : PReg) -> Int {
  if self.index >= spill_slot_base {
    self.index - spill_slot_base
  } else {
    -1
  }
}

///|
/// Create a PReg that represents a spilled value at the given slot
pub fn PReg::spilled(slot : Int, class : RegClass) -> PReg {
  { index: spill_slot_base + slot, class }
}
