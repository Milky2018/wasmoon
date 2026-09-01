///|
pub extend AliasRegion with Debug::{to_repr}

///|
pub extend AliasRegion with Eq::{not_equal, equal}

///|
pub extend AliasRegion with Hash::{hash, hash_combine}

///|
pub extend Block with Debug::{to_repr}

///|
pub extend CFG with Debug::{to_repr}

///|
pub extend CallOp with Debug::{to_repr}

///|
pub extend CallOp with Eq::{not_equal, equal}

///|
pub extend CallOp with Hash::{hash, hash_combine}

///|
pub extend ContextField with Debug::{to_repr}

///|
pub extend ContextField with Eq::{not_equal, equal}

///|
pub extend ContextField with Hash::{hash, hash_combine}

///|
pub extend ConversionOp with Debug::{to_repr}

///|
pub extend ConversionOp with Eq::{not_equal, equal}

///|
pub extend ConversionOp with Hash::{hash, hash_combine}

///|
pub extend ExtOp with Debug::{to_repr}

///|
pub extend ExtOp with Eq::{not_equal, equal}

///|
pub extend ExtOp with Hash::{hash, hash_combine}

///|
pub extend ExtOpDescriptor with Debug::{to_repr}

///|
pub extend ExtOpDescriptor with Eq::{not_equal, equal}

///|
pub extend ExtOpDescriptor with Hash::{hash, hash_combine}

///|
pub extend ExtensionInstView with Debug::{to_repr}

///|
pub extend ExternalSymbol with Debug::{to_repr}

///|
pub extend ExternalSymbol with Eq::{not_equal, equal}

///|
pub extend ExternalSymbol with Hash::{hash, hash_combine}

///|
pub extend FloatBinaryOp with Debug::{to_repr}

///|
pub extend FloatBinaryOp with Eq::{not_equal, equal}

///|
pub extend FloatBinaryOp with Hash::{hash, hash_combine}

///|
pub extend FloatCC with Debug::{to_repr}

///|
pub extend FloatCC with Eq::{not_equal, equal}

///|
pub extend FloatCC with Hash::{hash, hash_combine}

///|
pub extend FloatUnaryOp with Debug::{to_repr}

///|
pub extend FloatUnaryOp with Eq::{not_equal, equal}

///|
pub extend FloatUnaryOp with Hash::{hash, hash_combine}

///|
pub extend Function with Debug::{to_repr}

///|
pub extend GlobalValue with Debug::{to_repr}

///|
pub extend GlobalValue with Eq::{not_equal, equal}

///|
pub extend GlobalValue with Hash::{hash, hash_combine}

///|
pub extend GlobalValueData with Debug::{to_repr}

///|
pub extend GlobalValueData with Eq::{not_equal, equal}

///|
pub extend GlobalValueData with Hash::{hash, hash_combine}

///|
pub extend GlobalValueStability with Debug::{to_repr}

///|
pub extend GlobalValueStability with Eq::{not_equal, equal}

///|
pub extend GlobalValueStability with Hash::{hash, hash_combine}

///|
pub extend Inst with Debug::{to_repr}

///|
pub extend Inst with Eq::{not_equal, equal}

///|
pub extend Inst with Hash::{hash, hash_combine}

///|
pub extend IntBinaryOp with Debug::{to_repr}

///|
pub extend IntBinaryOp with Eq::{not_equal, equal}

///|
pub extend IntBinaryOp with Hash::{hash, hash_combine}

///|
pub extend IntCC with Debug::{to_repr}

///|
pub extend IntCC with Eq::{not_equal, equal}

///|
pub extend IntCC with Hash::{hash, hash_combine}

///|
pub extend IntUnaryOp with Debug::{to_repr}

///|
pub extend IntUnaryOp with Eq::{not_equal, equal}

///|
pub extend IntUnaryOp with Hash::{hash, hash_combine}

///|
pub extend Loop with Debug::{to_repr}

///|
pub extend MemoryOp with Debug::{to_repr}

///|
pub extend MemoryOp with Eq::{not_equal, equal}

///|
pub extend MemoryOp with Hash::{hash, hash_combine}

///|
pub extend Metadata with Debug::{to_repr}

///|
pub extend Metadata with Eq::{not_equal, equal}

///|
pub extend Opcode with Debug::{to_repr}

///|
pub extend Opcode with Eq::{not_equal, equal}

///|
pub extend Opcode with Hash::{hash, hash_combine}

///|
pub extend Opcode with Show::{to_string, output}

///|
pub extend OptResult with Eq::{not_equal, equal}

///|
pub extend ScalarOp with Debug::{to_repr}

///|
pub extend ScalarOp with Eq::{not_equal, equal}

///|
pub extend ScalarOp with Hash::{hash, hash_combine}

///|
pub extend Signature with Debug::{to_repr}

///|
pub extend Signature with Eq::{not_equal, equal}

///|
pub extend Signature with Hash::{hash, hash_combine}

///|
pub extend Terminator with Debug::{to_repr}

///|
pub extend Type with Debug::{to_repr}

///|
pub extend Type with Eq::{not_equal, equal}

///|
pub extend Type with Hash::{hash, hash_combine}

///|
pub extend Type with Show::{to_string, output}

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
pub extend VectorExtension with Debug::{to_repr}

///|
pub extend VectorExtension with Eq::{not_equal, equal}

///|
pub extend VectorExtension with Hash::{hash, hash_combine}

///|
pub extend VectorFloatBinaryOp with Debug::{to_repr}

///|
pub extend VectorFloatBinaryOp with Eq::{not_equal, equal}

///|
pub extend VectorFloatBinaryOp with Hash::{hash, hash_combine}

///|
pub extend VectorFloatCompareOp with Debug::{to_repr}

///|
pub extend VectorFloatCompareOp with Eq::{not_equal, equal}

///|
pub extend VectorFloatCompareOp with Hash::{hash, hash_combine}

///|
pub extend VectorFloatLane with Debug::{to_repr}

///|
pub extend VectorFloatLane with Eq::{not_equal, equal}

///|
pub extend VectorFloatLane with Hash::{hash, hash_combine}

///|
pub extend VectorFloatUnaryOp with Debug::{to_repr}

///|
pub extend VectorFloatUnaryOp with Eq::{not_equal, equal}

///|
pub extend VectorFloatUnaryOp with Hash::{hash, hash_combine}

///|
pub extend VectorFmaOp with Debug::{to_repr}

///|
pub extend VectorFmaOp with Eq::{not_equal, equal}

///|
pub extend VectorFmaOp with Hash::{hash, hash_combine}

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
pub extend VectorIntCompareOp with Debug::{to_repr}

///|
pub extend VectorIntCompareOp with Eq::{not_equal, equal}

///|
pub extend VectorIntCompareOp with Hash::{hash, hash_combine}

///|
pub extend VectorIntLane with Debug::{to_repr}

///|
pub extend VectorIntLane with Eq::{not_equal, equal}

///|
pub extend VectorIntLane with Hash::{hash, hash_combine}

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
pub extend VectorMemoryOp with Debug::{to_repr}

///|
pub extend VectorMemoryOp with Eq::{not_equal, equal}

///|
pub extend VectorMemoryOp with Hash::{hash, hash_combine}

///|
pub extend VectorOp with Debug::{to_repr}

///|
pub extend VectorOp with Eq::{not_equal, equal}

///|
pub extend VectorOp with Hash::{hash, hash_combine}

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
pub extend VectorSignedness with Debug::{to_repr}

///|
pub extend VectorSignedness with Eq::{not_equal, equal}

///|
pub extend VectorSignedness with Hash::{hash, hash_combine}

///|
pub extend VerifyError with Debug::{to_repr}

///|
pub extend VerifyError with Eq::{not_equal, equal}

///|
pub extend VerifyError with Show::{to_string, output}
