///|
/// Encode a condition for the AArch64 `cond` field.
///
/// Public emission entry points verify the function's target dialect before
/// reaching this internal encoder.
fn aarch64_cond_bits(cond : @instr.Cond) -> Int {
  match cond {
    Eq => 0
    Ne => 1
    Hs => 2
    Lo => 3
    Mi => 4
    Pl => 5
    Vs => 6
    Vc => 7
    Hi => 8
    Ls => 9
    Ge => 10
    Lt => 11
    Gt => 12
    Le => 13
    Al => 14
    AMD64(_) => abort("verified AArch64 emission received an AMD64 condition")
  }
}
