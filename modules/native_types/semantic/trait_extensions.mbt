///|
pub extend AtomicRmwOp with Debug::{to_repr}

///|
pub extend AtomicRmwOp with Eq::{not_equal, equal}

///|
pub extend AtomicRmwOp with Hash::{hash, hash_combine}

///|
pub extend AtomicSpec with Debug::{to_repr}

///|
pub extend AtomicSpec with Eq::{not_equal, equal}

///|
pub extend AtomicSpec with Hash::{hash, hash_combine}

///|
pub extend Block with Debug::{to_repr}

///|
pub extend Block with Eq::{not_equal, equal}

///|
pub extend Block with Hash::{hash, hash_combine}

///|
pub extend Callee with Debug::{to_repr}

///|
pub extend Callee with Eq::{not_equal, equal}

///|
pub extend Callee with Hash::{hash, hash_combine}

///|
pub extend CleanupStats with Debug::{to_repr}

///|
pub extend CleanupStats with Eq::{not_equal, equal}

///|
pub extend ConversionOp with Debug::{to_repr}

///|
pub extend ConversionOp with Eq::{not_equal, equal}

///|
pub extend ConversionOp with Hash::{hash, hash_combine}

///|
pub extend Edge with Debug::{to_repr}

///|
pub extend Edge with Eq::{not_equal, equal}

///|
pub extend FloatBinaryOp with Debug::{to_repr}

///|
pub extend FloatBinaryOp with Eq::{not_equal, equal}

///|
pub extend FloatBinaryOp with Hash::{hash, hash_combine}

///|
pub extend FloatComparison with Debug::{to_repr}

///|
pub extend FloatComparison with Eq::{not_equal, equal}

///|
pub extend FloatComparison with Hash::{hash, hash_combine}

///|
pub extend FloatTernaryOp with Debug::{to_repr}

///|
pub extend FloatTernaryOp with Eq::{not_equal, equal}

///|
pub extend FloatTernaryOp with Hash::{hash, hash_combine}

///|
pub extend FloatUnaryOp with Debug::{to_repr}

///|
pub extend FloatUnaryOp with Eq::{not_equal, equal}

///|
pub extend FloatUnaryOp with Hash::{hash, hash_combine}

///|
pub extend Function with Debug::{to_repr}

///|
pub extend Function with Show::{to_string, output}

///|
pub extend StackMapArgumentRoots with Debug::{to_repr}

///|
pub extend StackMapArgumentRoots with Eq::{equal, not_equal}

///|
pub extend CallAbiElaborationError with Debug::{to_repr}

///|
pub extend CallAbiElaborationError with Eq::{equal, not_equal}

///|
pub extend CallAbiElaborationError with Show::{to_string, output}

///|
pub extend Instruction with Debug::{to_repr}

///|
pub extend Instruction with Eq::{not_equal, equal}

///|
pub extend Instruction with Hash::{hash, hash_combine}

///|
pub extend InstructionMetadata with Debug::{to_repr}

///|
pub extend InstructionMetadata with Eq::{not_equal, equal}

///|
pub extend IntBinaryOp with Debug::{to_repr}

///|
pub extend IntBinaryOp with Eq::{not_equal, equal}

///|
pub extend IntBinaryOp with Hash::{hash, hash_combine}

///|
pub extend IntComparison with Debug::{to_repr}

///|
pub extend IntComparison with Eq::{not_equal, equal}

///|
pub extend IntComparison with Hash::{hash, hash_combine}

///|
pub extend IntOverflowOp with Debug::{to_repr}

///|
pub extend IntOverflowOp with Eq::{not_equal, equal}

///|
pub extend IntOverflowOp with Hash::{hash, hash_combine}

///|
pub extend IntUnaryOp with Debug::{to_repr}

///|
pub extend IntUnaryOp with Eq::{not_equal, equal}

///|
pub extend IntUnaryOp with Hash::{hash, hash_combine}

///|
pub extend LoadSpec with Debug::{to_repr}

///|
pub extend LoadSpec with Eq::{not_equal, equal}

///|
pub extend LoadSpec with Hash::{hash, hash_combine}

///|
pub extend MachVVerifyError with Debug::{to_repr}

///|
pub extend MachVVerifyError with Eq::{not_equal, equal}

///|
pub extend MachVVerifyError with Show::{to_string, output}

///|
pub extend Operation with Debug::{to_repr}

///|
pub extend Operation with Eq::{not_equal, equal}

///|
pub extend ReferenceComparison with Debug::{to_repr}

///|
pub extend ReferenceComparison with Eq::{not_equal, equal}

///|
pub extend ReferenceComparison with Hash::{hash, hash_combine}

///|
pub extend SemanticCall with Debug::{to_repr}

///|
pub extend SemanticCall with Eq::{not_equal, equal}

///|
pub extend SemanticCall with Hash::{hash, hash_combine}

///|
pub extend StackObject with Debug::{to_repr}

///|
pub extend StackObject with Eq::{not_equal, equal}

///|
pub extend StackObject with Hash::{hash, hash_combine}

///|
pub extend StoreSpec with Debug::{to_repr}

///|
pub extend StoreSpec with Eq::{not_equal, equal}

///|
pub extend StoreSpec with Hash::{hash, hash_combine}

///|
pub extend SwitchCase with Debug::{to_repr}

///|
pub extend SwitchCase with Eq::{not_equal, equal}

///|
pub extend Terminator with Debug::{to_repr}

///|
pub extend Terminator with Eq::{not_equal, equal}

///|
pub extend TerminatorMetadata with Debug::{to_repr}

///|
pub extend TerminatorMetadata with Eq::{not_equal, equal}

///|
pub extend TerminatorRecord with Debug::{to_repr}

///|
pub extend TerminatorRecord with Eq::{not_equal, equal}

///|
pub extend Value with Debug::{to_repr}

///|
pub extend Value with Eq::{not_equal, equal}

///|
pub extend Value with Hash::{hash, hash_combine}

///|
pub extend VectorBitwiseOp with Debug::{to_repr}

///|
pub extend VectorBitwiseOp with Eq::{not_equal, equal}

///|
pub extend VectorBitwiseOp with Hash::{hash, hash_combine}

///|
pub extend VectorConversionOp with Debug::{to_repr}

///|
pub extend VectorConversionOp with Eq::{not_equal, equal}

///|
pub extend VectorConversionOp with Hash::{hash, hash_combine}

///|
pub extend VectorFloatBinaryOp with Debug::{to_repr}

///|
pub extend VectorFloatBinaryOp with Eq::{not_equal, equal}

///|
pub extend VectorFloatBinaryOp with Hash::{hash, hash_combine}

///|
pub extend VectorFloatComparison with Debug::{to_repr}

///|
pub extend VectorFloatComparison with Eq::{not_equal, equal}

///|
pub extend VectorFloatComparison with Hash::{hash, hash_combine}

///|
pub extend VectorFloatUnaryOp with Debug::{to_repr}

///|
pub extend VectorFloatUnaryOp with Eq::{not_equal, equal}

///|
pub extend VectorFloatUnaryOp with Hash::{hash, hash_combine}

///|
pub extend VectorHalf with Debug::{to_repr}

///|
pub extend VectorHalf with Eq::{not_equal, equal}

///|
pub extend VectorHalf with Hash::{hash, hash_combine}

///|
pub extend VectorIntBinaryOp with Debug::{to_repr}

///|
pub extend VectorIntBinaryOp with Eq::{not_equal, equal}

///|
pub extend VectorIntBinaryOp with Hash::{hash, hash_combine}

///|
pub extend VectorIntComparison with Debug::{to_repr}

///|
pub extend VectorIntComparison with Eq::{not_equal, equal}

///|
pub extend VectorIntComparison with Hash::{hash, hash_combine}

///|
pub extend VectorIntShiftOp with Debug::{to_repr}

///|
pub extend VectorIntShiftOp with Eq::{not_equal, equal}

///|
pub extend VectorIntShiftOp with Hash::{hash, hash_combine}

///|
pub extend VectorIntUnaryOp with Debug::{to_repr}

///|
pub extend VectorIntUnaryOp with Eq::{not_equal, equal}

///|
pub extend VectorIntUnaryOp with Hash::{hash, hash_combine}

///|
pub extend VectorLane with Debug::{to_repr}

///|
pub extend VectorLane with Eq::{not_equal, equal}

///|
pub extend VectorLane with Hash::{hash, hash_combine}

///|
pub extend VectorLoadKind with Debug::{to_repr}

///|
pub extend VectorLoadKind with Eq::{not_equal, equal}

///|
pub extend VectorLoadKind with Hash::{hash, hash_combine}

///|
pub extend VectorLoadSpec with Debug::{to_repr}

///|
pub extend VectorLoadSpec with Eq::{not_equal, equal}

///|
pub extend VectorLoadSpec with Hash::{hash, hash_combine}

///|
pub extend VectorOp with Debug::{to_repr}

///|
pub extend VectorOp with Eq::{not_equal, equal}

///|
pub extend VectorPredicateOp with Debug::{to_repr}

///|
pub extend VectorPredicateOp with Eq::{not_equal, equal}

///|
pub extend VectorPredicateOp with Hash::{hash, hash_combine}

///|
pub extend VectorRelaxedOp with Debug::{to_repr}

///|
pub extend VectorRelaxedOp with Eq::{not_equal, equal}

///|
pub extend VectorRelaxedOp with Hash::{hash, hash_combine}

///|
pub extend VectorStoreLaneSpec with Debug::{to_repr}

///|
pub extend VectorStoreLaneSpec with Eq::{not_equal, equal}

///|
pub extend MandatoryCleanupPhase with Debug::{to_repr}

///|
pub extend MandatoryCleanupPhase with Eq::{not_equal, equal}

///|
pub extend VectorStoreLaneSpec with Hash::{hash, hash_combine}
