///|
pub(all) enum RawLaneSize {
  B8
  H16
  S32
  D64
} derive(Debug)

///|
impl Show for RawLaneSize with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
pub(all) enum RawCondition {
  RawEq
  RawNe
  RawHs
  RawLo
  RawPl
  RawVs
  RawPs
  RawPc
  RawHi
  RawLs
  RawGe
  RawLt
  RawGt
  RawLe
  RawAl
}

///|
pub extend RawLaneSize with Debug::{to_repr}
