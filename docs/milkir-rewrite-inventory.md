# MilkIR rewrite migration inventory

This is an audit of all **276 registered rule names** in
`98921fe7^:modules/milkir/egraph/rules_matcher.schema`, completed for ISS-461.
It is a migration ledger, not a runtime schema or code generator. Rules remain
handwritten MoonBit. A row denotes a rule family, not unrestricted application
to every possible operand graph.

## Interpretation

- **Migrated**: the applicable, legal, profitable cases have direct equivalents.
  Width, type, single-use and strict-cost guards deliberately restrict several
  old patterns. This is not a promise that every equivalent expression rewrites.
- **Obsolete**: identity-only rules or intermediate opcodes without a MilkIR
  producer/encoding. Do not manufacture an unlowerable IR to inflate coverage.
- **Unsafe**: fails a modular arithmetic counterexample without extra facts.
- **Unprofitable**: equal/more operations under the target-independent cost
  contract, or increases live ranges without measured benefit. These are not
  correctness failures; a future measured scheduling/lowering change may
  legitimately choose a different form.
- **Target-owned**: depends on immediate/fused instruction costs or cannot be
  represented while preserving MilkIR operand types. This names the proper
  owner, not a claim that both targets already perform the transformation.

Counts: 195 migrated, 35 unprofitable, 8 target-owned, 36 obsolete, 2 unsafe.
No registered name is unclassified.

## Important corrections

The removed elaborator explicitly refused scalar min/max, iabs, spaceship,
float and vector destinations. Its rule count therefore overstated executable
optimization coverage. Current scalar min/max/abs stay in compare/select form;
bound comparisons are simplified on that representation.

The former vector splat constant rule always emitted two 64-bit lanes, and
scalar lifting ignored lane width. Current folding uses all six explicit lane
types; arithmetic/bitwise lifting requires identical integer lane types.
Unary/shift/min/max lifting is not introduced merely to change representation.

The former float constant matcher treated every float as f64, used ordinary
round for nearest, and used multiplication for copysign. Current folds are
typed: sign changes preserve payload bits, nearest uses ties-to-even, min/max
preserve signed zero, and arithmetic NaNs remain runtime operations. There is
no scalar copysign opcode to migrate.

The old `neg(ushr(x, k))` test accepted either 31 or 63 for either type. The
replacement requires the normalized amount to equal the actual width minus
one. The unrestricted `ireduce(shl(x, n))` rule changes count masking (for
example, 64-bit shift by 32 versus 32-bit shift by 0); only proven counts
are narrowed.

Zero-extended addition cannot narrow through overflow:
`uext32(0xffffffff) + uext32(1) = 0x100000000`, not zero.
Likewise `uext32(0xffffffff) - uext32(0) = 4294967295`, not `sext32(-1)`.

Disabled division/remainder skeleton rules are outside the 276 registered
names and remain disabled. No cancellation removes a possibly trapping
division. Mandatory constant folding retains divide-by-zero and signed
division overflow checks.

## Per-rule disposition

| Legacy name (without `rule_`) | Disposition | Implementation or reason |
| --- | --- | --- |
| `add_zero` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `sub_zero` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `mul_one` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `mul_zero` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `idempotent` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `xor_self` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `sub_self` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `and_zero` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `or_zero` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `xor_zero` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `and_all_ones` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `or_all_ones` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `or_self` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `xor_all_ones` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `xor_not` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `or_not` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `and_not` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `double_bnot` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `demorgan_or` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `demorgan_and` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `and_xor_xor` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `or_xor_and` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `and_or_absorb` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `xor_xor_cancel` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `factor_and_xor` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `and_add_xor` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `or_add_and` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `or_and_not` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `or_or_absorb` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `and_and_absorb` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `xor_not_and` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `and_or_not` | migrated | Direct integer identity/bitwise dispatch; factoring requires single-use children. |
| `shl_zero` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `shr_zero` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `shift_of_zero` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `rot_zero` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `shl_shl` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `ushr_ushr` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `sshr_sshr` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `rotl_rotr_cancel` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `rotr_rotl_cancel` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `ushr_shl_mask` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `shl_ushr_mask` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `band_shl_shl` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `sub_shl_shl` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `add_shl_shl` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `ushr_band_shl` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `shl_ushr_to_rotl` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `neg_ushr_to_sshr` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `shl_shl_overflow` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `ushr_ushr_overflow` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `rotl_rotl_combine` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `rotr_rotr_combine` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `rotr_rotl_to_rotl` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `rotl_rotr_to_rotr` | migrated | Width-normalized shift/rotate dispatch; new-operation forms require a strict cost decrease. |
| `shift_extend_amount` | target-owned | MilkIR scalar shifts require equal operand types; removing only the amount conversion violates the IR contract. Target lowering may use the low register bits. |
| `shift_reduce_amount` | target-owned | MilkIR scalar shifts require equal operand types; removing only the amount conversion violates the IR contract. Target lowering may use the low register bits. |
| `mul_pow2` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_mul_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `mul_shl_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `double` | target-owned | Same-cost or expanding arithmetic forms depend on target immediate/address/fused-instruction costs; retain canonical arithmetic. |
| `mul_3` | target-owned | Same-cost or expanding arithmetic forms depend on target immediate/address/fused-instruction costs; retain canonical arithmetic. |
| `mul_5` | target-owned | Same-cost or expanding arithmetic forms depend on target immediate/address/fused-instruction costs; retain canonical arithmetic. |
| `mul_7` | target-owned | Same-cost or expanding arithmetic forms depend on target immediate/address/fused-instruction costs; retain canonical arithmetic. |
| `mul_9` | target-owned | Same-cost or expanding arithmetic forms depend on target immediate/address/fused-instruction costs; retain canonical arithmetic. |
| `neg_zero` | obsolete | Legacy identity/no-op; input already is the canonical representation. |
| `sub_neg` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `add_neg` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `mul_neg_one` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `neg_mul_neg` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `neg_sub_swap` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `bnot_add_one` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `bnot_sub_one` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `bnot_add_neg_one` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `or_add_neg` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `add_sub_or_to_and` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `sub_add_cancel` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `add_sub_cancel` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `sub_sub_cancel` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `mul_shl_one` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `const_fold` | migrated | Existing mandatory scalar constant folding plus acyclic rotate/count/not folding. Division/remainder retain trap guards; absent Bswap/Bitrev opcodes are not recreated. |
| `reassoc_add_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_sub_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_or_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_and_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_xor_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_sub_add_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_add_sub_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_sub_sub_const_left` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_add_sub_const_left` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `reassoc_shl_const` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `reassoc_ushr_const` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `reassoc_sshr_const` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `select_const` | migrated | Modular integer algebra; negation is represented directly as subtraction from zero. |
| `sub_neg_const` | target-owned | Same-cost or expanding arithmetic forms depend on target immediate/address/fused-instruction costs; retain canonical arithmetic. |
| `rebalance_add_consts` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `rebalance_mul_consts` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `rebalance_and_consts` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `rebalance_or_consts` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `rebalance_xor_consts` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `fconst_fold_binary` | migrated | Typed float constants and bit-preserving sign identities; NaN arithmetic remains at runtime, min/max handle signed zero. |
| `fconst_fold_unary` | migrated | Typed float constants and bit-preserving sign identities; NaN arithmetic remains at runtime, min/max handle signed zero. |
| `fneg_fneg` | migrated | Typed float constants and bit-preserving sign identities; NaN arithmetic remains at runtime, min/max handle signed zero. |
| `fabs_fneg` | migrated | Typed float constants and bit-preserving sign identities; NaN arithmetic remains at runtime, min/max handle signed zero. |
| `fabs_fabs` | migrated | Typed float constants and bit-preserving sign identities; NaN arithmetic remains at runtime, min/max handle signed zero. |
| `fneg_fabs` | obsolete | Legacy identity/no-op; input already is the canonical representation. |
| `splat_const` | migrated | Explicit lane width; binary lifting requires matching lanes and single-use splats. |
| `band_splat_splat` | migrated | Explicit lane width; binary lifting requires matching lanes and single-use splats. |
| `bor_splat_splat` | migrated | Explicit lane width; binary lifting requires matching lanes and single-use splats. |
| `bxor_splat_splat` | migrated | Explicit lane width; binary lifting requires matching lanes and single-use splats. |
| `bnot_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `iadd_splat_splat` | migrated | Explicit lane width; binary lifting requires matching lanes and single-use splats. |
| `isub_splat_splat` | migrated | Explicit lane width; binary lifting requires matching lanes and single-use splats. |
| `imul_splat_splat` | migrated | Explicit lane width; binary lifting requires matching lanes and single-use splats. |
| `ineg_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `iabs_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `popcnt_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `smin_splat_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `umin_splat_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `smax_splat_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `umax_splat_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `rotl_splat` | obsolete | MilkIR has no lane-wise vector rotate opcode. |
| `rotr_splat` | obsolete | MilkIR has no lane-wise vector rotate opcode. |
| `ishl_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `ushr_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `sshr_splat` | unprofitable | Creates the same number or more live operations; narrow lanes additionally require truncation/sign or shift-count normalization. Constant splats fold directly. |
| `uextend_uextend` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `sextend_sextend` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `sextend_uextend` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `sextend_icmp` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_uextend` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_sextend` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `band_uextend` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `bor_uextend` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `bxor_uextend` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_ineg` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_bnot` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_iadd` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_isub` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_imul` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_band` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_bor` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_bxor` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_ireduce` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_ishl` | migrated | Repaired: only known wide shift counts; counts 32..63 yield zero and 0..31 narrow only if cheaper. The unrestricted legacy rule is invalid. |
| `eq_sextend_zero` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ne_sextend_zero` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `icmp_sextend_zero` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `iadd_uextend` | unsafe | Wide arithmetic cannot be replaced by narrow modular arithmetic without an overflow/range proof. |
| `isub_uextend` | unsafe | Wide arithmetic cannot be replaced by narrow modular arithmetic without an overflow/range proof. |
| `slt_uextend_zero` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `sge_uextend_zero` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `band_uextend_mask` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `band_sextend_mask` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_const` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `uextend_const` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `sextend_const` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `uextend_identity` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `sextend_identity` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_identity` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `band_uextend_mask_precise` | migrated | Typed conversion, mask and narrowing dispatch; distributed narrowing requires a cheaper candidate. |
| `ireduce_uextend_skip` | obsolete | Require three distinct scalar integer widths; MilkIR has only i32/i64. Equal-width round trips are covered. |
| `ireduce_sextend_skip` | obsolete | Require three distinct scalar integer widths; MilkIR has only i32/i64. Equal-width round trips are covered. |
| `ireduce_uextend_to_extend` | obsolete | Require three distinct scalar integer widths; MilkIR has only i32/i64. Equal-width round trips are covered. |
| `ireduce_sextend_to_extend` | obsolete | Require three distinct scalar integer widths; MilkIR has only i32/i64. Equal-width round trips are covered. |
| `canon_add` | migrated | Constants move to the right in direct scalar dispatch. |
| `canon_mul` | migrated | Constants move to the right in direct scalar dispatch. |
| `canon_and` | migrated | Constants move to the right in direct scalar dispatch. |
| `canon_or` | migrated | Constants move to the right in direct scalar dispatch. |
| `canon_xor` | migrated | Constants move to the right in direct scalar dispatch. |
| `rebalance_add_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `rebalance_add_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `rebalance_mul_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `rebalance_mul_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `rebalance_and_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `rebalance_and_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `rebalance_xor_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `rebalance_xor_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `sub_sub_sub_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `sub_sub_add_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `sub_add_sub_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `sub_add_add_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `add_sub_sub_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `add_sub_add_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `add_add_sub_right` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `sub_sub_sub_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `sub_sub_add_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `sub_add_sub_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `sub_add_add_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `add_sub_sub_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `add_sub_add_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `add_add_sub_left` | unprofitable | Reassociates three operations into three; no generic operation reduction, with potentially greater live ranges. Not a proven runtime improvement. |
| `eq_self` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ne_self` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `icmp_self` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ne_icmp_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `eq_icmp_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ne_icmp_one` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `eq_icmp_one` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `band_icmp_one` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ult_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ule_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ugt_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `uge_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `uge_one_to_ne_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ult_one_to_eq_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `sge_one_to_sgt_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `slt_one_to_sle_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `sgt_neg_one_to_sge_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `sle_neg_one_to_slt_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `eq_add_cancel` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ne_add_cancel` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `eq_xor_self` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ne_xor_self` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ugt_sub_self` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ule_sub_self` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ult_bnot_swap` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `slt_bnot_swap` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `xor_cmp_to_ne` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `band_contradictory_cmp` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `select_uextend_icmp` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `eq_add_const` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ne_add_const` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `eq_sub_const` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ne_sub_const` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `icmp_swap_const` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `eq_add_add_const` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `ne_add_add_const` | migrated | Single-use constant reassociation or shift factoring removes an operation; staged constants fold immediately. |
| `select_same` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `select_icmp_one_zero` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `select_icmp_zero_one` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `select_nested_same_cond_right` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `select_nested_same_cond_left` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `select_uextend_cond` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `add_select_const` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `select_to_smax` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_smin` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_umax` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_umin` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_smax_swapped` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_smin_swapped` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_umax_swapped` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_umin_swapped` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_iabs_positive` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `select_to_iabs_negative` | obsolete | Scalar min/max/abs remain compare/select expressions; the old destination opcode could not be elaborated. |
| `smin_never_greater` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `never_less_than_smin` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `umin_never_greater` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `never_less_than_umin` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ugt_umax` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `uge_umax` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `ule_umax` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `sgt_smax` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `sge_smax` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `slt_smin` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `sle_smin` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `sge_smin` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `sle_smax` | migrated | Direct comparison/select dispatch; min/max bound proofs match the canonical compare/select expression. |
| `spaceship_eq_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_ne_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_s_lt_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_u_lt_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_s_le_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_u_le_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_s_gt_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_u_gt_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_s_ge_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_u_ge_zero` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_s_eq_neg_one` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_u_eq_neg_one` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_s_ne_neg_one` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_u_ne_neg_one` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_s_eq_one` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_u_eq_one` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_s_ne_one` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
| `spaceship_u_ne_one` | obsolete | No scalar spaceship opcode, producer or elaboration exists in MilkIR. |
