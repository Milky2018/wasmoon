// Binary parser for WebAssembly modules.
//
// This package was originally implemented in a single file (parser/parser.mbt).
// It has been split into multiple files for maintainability:
// - error.mbt: ParserError + messages
// - state.mbt: Parser state + basic byte readers
// - leb128.mbt: LEB128 decoding
// - basic_types.mbt: primitive readers + UTF-8 decoding
// - value_types.mbt: ValueType / BlockType parsing
// - rec_group_types.mbt: WasmGC rec group/type parsing
// - func_type_vec.mbt: vec reader helper
// - table_memory_types.mbt: table/memory/global type parsing
// - elem_segment.mbt: element segment parsing
// - instructions.mbt: instruction parsing
// - sections.mbt: parse_module + section decoding
// - leb128_wbtest.mbt: LEB128 regression tests
