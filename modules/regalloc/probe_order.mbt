///|
fn same_physical_reg(lhs : PhysicalReg, rhs : PhysicalReg) -> Bool {
  lhs.id == rhs.id && lhs.class == rhs.class
}

///|
fn append_probe_phase(
  out : Array[PhysicalReg],
  regs : Array[PhysicalReg],
  scan_limit : Int,
  offset : Int,
  skip_reg : PhysicalReg?,
) -> Unit {
  let n = regs.length()
  if n == 0 {
    return
  }
  let phase_scan_limit = if scan_limit < n { scan_limit } else { n }
  let phase_offset = (offset % n + n) % n
  let mut scanned = 0
  for i in 0..<n {
    if scanned >= phase_scan_limit {
      break
    }
    let preg = regs[(phase_offset + i) % n]
    if skip_reg is Some(skip) && same_physical_reg(preg, skip) {
      continue
    }
    scanned = scanned + 1
    out.push(preg)
  }
}

///|
pub fn plan_register_probe_order(
  available_regs : Array[PhysicalReg],
  caller_saved_regs : Array[PhysicalReg],
  callee_saved_regs : Array[PhysicalReg],
  prefer_caller_saved : Bool,
  scan_limit : Int,
  offset : Int,
  skip_reg : PhysicalReg?,
) -> Array[PhysicalReg] {
  let out : Array[PhysicalReg] = []
  let limit = if scan_limit < available_regs.length() {
    scan_limit
  } else {
    available_regs.length()
  }
  if prefer_caller_saved {
    append_probe_phase(out, caller_saved_regs, limit, offset, skip_reg)
    append_probe_phase(out, callee_saved_regs, limit, offset, skip_reg)
  } else {
    append_probe_phase(out, available_regs, limit, offset, skip_reg)
  }
  out
}
