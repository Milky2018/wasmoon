///|
/// Target-neutral register-class identity shared by VCode and register
/// allocation.
///
/// `FpVector` preserves targets whose scalar floating-point and vector values
/// occupy one physical register bank. `Float` and `Vector` remain available to
/// standalone allocator embeddings that model distinct banks.
pub(all) enum RegClass {
  Int
  Float
  Vector
  FpVector
} derive(Eq, Debug, Hash)

///|
pub extend RegClass with Debug::{to_repr}

///|
pub extend RegClass with Eq::{not_equal, equal}

///|
pub extend RegClass with Hash::{hash, hash_combine}

///|
pub fn RegClass::text(self : RegClass) -> String {
  match self {
    Int => "int"
    Float => "float"
    Vector => "vector"
    FpVector => "fpvec"
  }
}
