/**
 * DWARF Debug Info Generation for JIT Code
 *
 * This module generates minimal DWARF debug information and registers
 * JIT-compiled code with LLDB using the GDB JIT interface.
 *
 * The GDB JIT interface is a standard protocol where:
 * 1. We create an in-memory object file (Mach-O on macOS) with DWARF sections
 * 2. We register it via __jit_debug_descriptor and __jit_debug_register_code()
 * 3. LLDB sets a breakpoint on __jit_debug_register_code and reads the descriptor
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifdef __APPLE__
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#endif

// ============================================================================
// GDB JIT Interface (standard protocol)
// ============================================================================

typedef enum {
    JIT_NOACTION = 0,
    JIT_REGISTER_FN,
    JIT_UNREGISTER_FN
} jit_actions_t;

struct jit_code_entry {
    struct jit_code_entry *next_entry;
    struct jit_code_entry *prev_entry;
    const char *symfile_addr;
    uint64_t symfile_size;
};

struct jit_descriptor {
    uint32_t version;
    uint32_t action_flag;
    struct jit_code_entry *relevant_entry;
    struct jit_code_entry *first_entry;
};

// These symbols must be exactly named for LLDB to find them
// Use 'used' to prevent optimization, 'visibility' for external access
__attribute__((used, visibility("default")))
struct jit_descriptor __jit_debug_descriptor = { 1, JIT_NOACTION, NULL, NULL };

// LLDB sets a breakpoint on this function
// Must be noinline and have a real instruction for the breakpoint
__attribute__((noinline, used, visibility("default")))
void __jit_debug_register_code(void) {
    // Empty - LLDB breaks here and reads __jit_debug_descriptor
    // The volatile asm ensures this isn't optimized away
    __asm__ volatile("nop" ::: "memory");
}

// ============================================================================
// DWARF Constants
// ============================================================================

// DWARF tags
#define DW_TAG_compile_unit     0x11
#define DW_TAG_subprogram       0x2e

// DWARF attributes
#define DW_AT_name              0x03
#define DW_AT_producer          0x25
#define DW_AT_language          0x13
#define DW_AT_low_pc            0x11
#define DW_AT_high_pc           0x12

// DWARF forms
#define DW_FORM_addr            0x01
#define DW_FORM_data2           0x05
#define DW_FORM_data4           0x06
#define DW_FORM_data8           0x07
#define DW_FORM_string          0x08

// DWARF children
#define DW_CHILDREN_no          0x00
#define DW_CHILDREN_yes         0x01

// DWARF language (using assembler as closest to machine code)
#define DW_LANG_Mips_Assembler  0x8001

// ============================================================================
// Data Structures
// ============================================================================

#define MAX_DWARF_FUNCTIONS 1024

typedef struct {
    char name[256];
    uint64_t addr;
    uint32_t size;
    int func_idx;
} dwarf_func_t;

typedef struct {
    dwarf_func_t functions[MAX_DWARF_FUNCTIONS];
    int num_functions;
    uint64_t low_pc;
    uint64_t high_pc;
    struct jit_code_entry *code_entry;
    char *object_buffer;
    size_t object_size;
} dwarf_builder_t;

// ============================================================================
// Buffer Writing Helpers
// ============================================================================

typedef struct {
    uint8_t *data;
    size_t capacity;
    size_t size;
} buffer_t;

static void buffer_init(buffer_t *buf, size_t initial_capacity) {
    buf->data = (uint8_t *)malloc(initial_capacity);
    buf->capacity = initial_capacity;
    buf->size = 0;
}

static void buffer_ensure(buffer_t *buf, size_t additional) {
    if (buf->size + additional > buf->capacity) {
        buf->capacity = (buf->size + additional) * 2;
        buf->data = (uint8_t *)realloc(buf->data, buf->capacity);
    }
}

static void buffer_write_u8(buffer_t *buf, uint8_t v) {
    buffer_ensure(buf, 1);
    buf->data[buf->size++] = v;
}

static void buffer_write_u16(buffer_t *buf, uint16_t v) {
    buffer_ensure(buf, 2);
    memcpy(buf->data + buf->size, &v, 2);
    buf->size += 2;
}

static void buffer_write_u32(buffer_t *buf, uint32_t v) {
    buffer_ensure(buf, 4);
    memcpy(buf->data + buf->size, &v, 4);
    buf->size += 4;
}

static void buffer_write_u64(buffer_t *buf, uint64_t v) {
    buffer_ensure(buf, 8);
    memcpy(buf->data + buf->size, &v, 8);
    buf->size += 8;
}

static void buffer_write_uleb128(buffer_t *buf, uint64_t v) {
    do {
        uint8_t byte = v & 0x7f;
        v >>= 7;
        if (v != 0) byte |= 0x80;
        buffer_write_u8(buf, byte);
    } while (v != 0);
}

static void buffer_write_string(buffer_t *buf, const char *s) {
    size_t len = strlen(s) + 1;
    buffer_ensure(buf, len);
    memcpy(buf->data + buf->size, s, len);
    buf->size += len;
}

static void buffer_write_bytes(buffer_t *buf, const void *data, size_t len) {
    buffer_ensure(buf, len);
    memcpy(buf->data + buf->size, data, len);
    buf->size += len;
}

static void buffer_align(buffer_t *buf, size_t alignment) {
    size_t padding = (alignment - (buf->size % alignment)) % alignment;
    buffer_ensure(buf, padding);
    memset(buf->data + buf->size, 0, padding);
    buf->size += padding;
}

static void buffer_free(buffer_t *buf) {
    free(buf->data);
    buf->data = NULL;
    buf->capacity = 0;
    buf->size = 0;
}

// ============================================================================
// DWARF Section Generation
// ============================================================================

// Generate .debug_abbrev section
static void generate_debug_abbrev(buffer_t *buf) {
    // Abbreviation 1: DW_TAG_compile_unit
    buffer_write_uleb128(buf, 1);                    // abbrev code
    buffer_write_uleb128(buf, DW_TAG_compile_unit);  // tag
    buffer_write_u8(buf, DW_CHILDREN_yes);           // has children

    buffer_write_uleb128(buf, DW_AT_producer);
    buffer_write_uleb128(buf, DW_FORM_string);

    buffer_write_uleb128(buf, DW_AT_language);
    buffer_write_uleb128(buf, DW_FORM_data2);

    buffer_write_uleb128(buf, DW_AT_name);
    buffer_write_uleb128(buf, DW_FORM_string);

    buffer_write_uleb128(buf, DW_AT_low_pc);
    buffer_write_uleb128(buf, DW_FORM_addr);

    buffer_write_uleb128(buf, DW_AT_high_pc);
    buffer_write_uleb128(buf, DW_FORM_data8);

    buffer_write_uleb128(buf, 0);  // attr terminator
    buffer_write_uleb128(buf, 0);  // form terminator

    // Abbreviation 2: DW_TAG_subprogram
    buffer_write_uleb128(buf, 2);                    // abbrev code
    buffer_write_uleb128(buf, DW_TAG_subprogram);    // tag
    buffer_write_u8(buf, DW_CHILDREN_no);            // no children

    buffer_write_uleb128(buf, DW_AT_name);
    buffer_write_uleb128(buf, DW_FORM_string);

    buffer_write_uleb128(buf, DW_AT_low_pc);
    buffer_write_uleb128(buf, DW_FORM_addr);

    buffer_write_uleb128(buf, DW_AT_high_pc);
    buffer_write_uleb128(buf, DW_FORM_data8);

    buffer_write_uleb128(buf, 0);  // attr terminator
    buffer_write_uleb128(buf, 0);  // form terminator

    // End of abbreviations
    buffer_write_uleb128(buf, 0);
}

// Generate .debug_info section
static void generate_debug_info(buffer_t *buf, dwarf_builder_t *builder,
                                 size_t abbrev_offset) {
    size_t unit_start = buf->size;

    // Compilation unit header (will patch length later)
    buffer_write_u32(buf, 0);  // unit_length placeholder
    buffer_write_u16(buf, 4);  // version (DWARF 4)
    buffer_write_u32(buf, (uint32_t)abbrev_offset);  // debug_abbrev_offset
    buffer_write_u8(buf, 8);   // address_size (64-bit)

    size_t die_start = buf->size;

    // DW_TAG_compile_unit (abbrev 1)
    buffer_write_uleb128(buf, 1);
    buffer_write_string(buf, "wasmoon JIT compiler");   // DW_AT_producer
    buffer_write_u16(buf, DW_LANG_Mips_Assembler);      // DW_AT_language
    buffer_write_string(buf, "<jit>");                   // DW_AT_name
    buffer_write_u64(buf, builder->low_pc);             // DW_AT_low_pc
    buffer_write_u64(buf, builder->high_pc - builder->low_pc);  // DW_AT_high_pc (size)

    // Function DIEs
    for (int i = 0; i < builder->num_functions; i++) {
        dwarf_func_t *func = &builder->functions[i];

        // DW_TAG_subprogram (abbrev 2)
        buffer_write_uleb128(buf, 2);
        buffer_write_string(buf, func->name);           // DW_AT_name
        buffer_write_u64(buf, func->addr);              // DW_AT_low_pc
        buffer_write_u64(buf, (uint64_t)func->size);    // DW_AT_high_pc (size)
    }

    // End of children (null DIE)
    buffer_write_uleb128(buf, 0);

    // Patch unit length (excludes the length field itself)
    uint32_t unit_length = (uint32_t)(buf->size - unit_start - 4);
    memcpy(buf->data + unit_start, &unit_length, 4);
}

// ============================================================================
// Mach-O Object File Generation (macOS)
// ============================================================================

#ifdef __APPLE__

// Section names for DWARF
#define SECT_DEBUG_INFO    "__debug_info"
#define SECT_DEBUG_ABBREV  "__debug_abbrev"
#define SEGNAME_DWARF      "__DWARF"

static void generate_macho_object(dwarf_builder_t *builder, buffer_t *output) {
    // Generate DWARF sections first
    buffer_t abbrev_buf, info_buf;
    buffer_init(&abbrev_buf, 256);
    buffer_init(&info_buf, 4096);

    generate_debug_abbrev(&abbrev_buf);
    generate_debug_info(&info_buf, builder, 0);  // abbrev offset = 0 relative to section

    // Calculate layout
    // We need two segments:
    // 1. __TEXT segment covering the JIT code address range (no file content, just vmaddr)
    // 2. __DWARF segment with debug sections
    size_t header_size = sizeof(struct mach_header_64);

    // __TEXT segment with one __text section (for symbols to reference)
    size_t text_segment_cmd_size = sizeof(struct segment_command_64) + sizeof(struct section_64);

    // __DWARF segment with two sections
    size_t dwarf_segment_cmd_size = sizeof(struct segment_command_64) +
                                     2 * sizeof(struct section_64);
    size_t symtab_cmd_size = sizeof(struct symtab_command);
    size_t load_cmds_size = text_segment_cmd_size + dwarf_segment_cmd_size + symtab_cmd_size;

    size_t section_offset = header_size + load_cmds_size;
    section_offset = (section_offset + 7) & ~7;  // 8-byte align

    size_t abbrev_offset = section_offset;
    size_t info_offset = abbrev_offset + abbrev_buf.size;
    info_offset = (info_offset + 7) & ~7;  // 8-byte align

    size_t total_dwarf_size = (info_offset - section_offset) + info_buf.size;

    // Symbol table comes after sections
    size_t symtab_offset = info_offset + info_buf.size;
    symtab_offset = (symtab_offset + 7) & ~7;

    // String table
    size_t strtab_offset = symtab_offset + builder->num_functions * sizeof(struct nlist_64);

    // Build string table
    buffer_t strtab;
    buffer_init(&strtab, 1024);
    buffer_write_u8(&strtab, 0);  // First byte is null

    uint32_t *string_offsets = (uint32_t *)malloc(builder->num_functions * sizeof(uint32_t));
    for (int i = 0; i < builder->num_functions; i++) {
        string_offsets[i] = (uint32_t)strtab.size;
        buffer_write_string(&strtab, builder->functions[i].name);
    }

    size_t total_size = strtab_offset + strtab.size;

    // Write Mach-O header
    buffer_ensure(output, total_size);

    struct mach_header_64 header = {
        .magic = MH_MAGIC_64,
        .cputype = CPU_TYPE_ARM64,
        .cpusubtype = CPU_SUBTYPE_ARM64_ALL,
        .filetype = MH_OBJECT,
        .ncmds = 3,  // text segment + dwarf segment + symtab
        .sizeofcmds = (uint32_t)load_cmds_size,
        .flags = 0,
        .reserved = 0
    };
    buffer_write_bytes(output, &header, sizeof(header));

    // __TEXT segment - covers the JIT code address range
    // This tells LLDB where our code lives in memory
    uint64_t text_vmaddr = builder->low_pc;
    uint64_t text_vmsize = builder->high_pc - builder->low_pc;

    struct segment_command_64 text_segcmd = {
        .cmd = LC_SEGMENT_64,
        .cmdsize = (uint32_t)text_segment_cmd_size,
        .segname = "__TEXT",
        .vmaddr = text_vmaddr,
        .vmsize = text_vmsize,
        .fileoff = 0,      // No file content
        .filesize = 0,     // No file content
        .maxprot = VM_PROT_READ | VM_PROT_EXECUTE,
        .initprot = VM_PROT_READ | VM_PROT_EXECUTE,
        .nsects = 1,
        .flags = 0
    };
    buffer_write_bytes(output, &text_segcmd, sizeof(text_segcmd));

    // __text section - placeholder for symbol references
    // Note: offset must be valid (past headers) even if there's no file content
    // We point it to section_offset where DWARF data starts, but with size=0
    struct section_64 text_sect = {0};
    strncpy(text_sect.sectname, "__text", 16);
    strncpy(text_sect.segname, "__TEXT", 16);
    text_sect.addr = text_vmaddr;
    text_sect.size = 0;        // No file content (size=0)
    text_sect.offset = (uint32_t)section_offset;  // Valid offset past headers
    text_sect.align = 0;
    text_sect.reloff = 0;
    text_sect.nreloc = 0;
    text_sect.flags = S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS;
    buffer_write_bytes(output, &text_sect, sizeof(text_sect));

    // __DWARF segment for debug sections
    struct segment_command_64 dwarf_segcmd = {
        .cmd = LC_SEGMENT_64,
        .cmdsize = (uint32_t)dwarf_segment_cmd_size,
        .segname = "__DWARF",
        .vmaddr = 0,
        .vmsize = total_dwarf_size,
        .fileoff = section_offset,
        .filesize = total_dwarf_size,
        .maxprot = VM_PROT_READ,
        .initprot = VM_PROT_READ,
        .nsects = 2,
        .flags = 0
    };
    buffer_write_bytes(output, &dwarf_segcmd, sizeof(dwarf_segcmd));

    // Section: __debug_abbrev
    struct section_64 abbrev_sect = {0};
    strncpy(abbrev_sect.sectname, SECT_DEBUG_ABBREV, 16);
    strncpy(abbrev_sect.segname, SEGNAME_DWARF, 16);
    abbrev_sect.addr = 0;
    abbrev_sect.size = abbrev_buf.size;
    abbrev_sect.offset = (uint32_t)abbrev_offset;
    abbrev_sect.align = 0;
    abbrev_sect.reloff = 0;
    abbrev_sect.nreloc = 0;
    abbrev_sect.flags = S_ATTR_DEBUG;
    buffer_write_bytes(output, &abbrev_sect, sizeof(abbrev_sect));

    // Section: __debug_info
    struct section_64 info_sect = {0};
    strncpy(info_sect.sectname, SECT_DEBUG_INFO, 16);
    strncpy(info_sect.segname, SEGNAME_DWARF, 16);
    info_sect.addr = 0;
    info_sect.size = info_buf.size;
    info_sect.offset = (uint32_t)info_offset;
    info_sect.align = 0;
    info_sect.reloff = 0;
    info_sect.nreloc = 0;
    info_sect.flags = S_ATTR_DEBUG;
    buffer_write_bytes(output, &info_sect, sizeof(info_sect));

    // Symbol table command
    struct symtab_command symtab = {
        .cmd = LC_SYMTAB,
        .cmdsize = sizeof(struct symtab_command),
        .symoff = (uint32_t)symtab_offset,
        .nsyms = (uint32_t)builder->num_functions,
        .stroff = (uint32_t)strtab_offset,
        .strsize = (uint32_t)strtab.size
    };
    buffer_write_bytes(output, &symtab, sizeof(symtab));

    // Pad to section offset
    buffer_align(output, 8);
    while (output->size < abbrev_offset) {
        buffer_write_u8(output, 0);
    }

    // Write __debug_abbrev content
    buffer_write_bytes(output, abbrev_buf.data, abbrev_buf.size);

    // Pad to info offset
    buffer_align(output, 8);
    while (output->size < info_offset) {
        buffer_write_u8(output, 0);
    }

    // Write __debug_info content
    buffer_write_bytes(output, info_buf.data, info_buf.size);

    // Pad to symtab offset
    buffer_align(output, 8);
    while (output->size < symtab_offset) {
        buffer_write_u8(output, 0);
    }

    // Write symbol table entries
    // Symbols reference section 1 (__text in __TEXT segment)
    for (int i = 0; i < builder->num_functions; i++) {
        struct nlist_64 sym = {
            .n_un.n_strx = string_offsets[i],
            .n_type = N_SECT | N_EXT,
            .n_sect = 1,  // __text section (1-indexed)
            .n_desc = 0,
            .n_value = builder->functions[i].addr
        };
        buffer_write_bytes(output, &sym, sizeof(sym));
    }

    // Write string table
    buffer_write_bytes(output, strtab.data, strtab.size);

    // Cleanup
    free(string_offsets);
    buffer_free(&strtab);
    buffer_free(&abbrev_buf);
    buffer_free(&info_buf);
}

#else
// Linux/other platforms - generate ELF (stub for now)
static void generate_elf_object(dwarf_builder_t *builder, buffer_t *output) {
    // TODO: Implement ELF generation for Linux
    (void)builder;
    (void)output;
}
#endif

// ============================================================================
// Public API
// ============================================================================

#ifdef __APPLE__
#define MOONBIT_FFI_EXPORT __attribute__((visibility("default")))
#else
#define MOONBIT_FFI_EXPORT __attribute__((visibility("default")))
#endif

MOONBIT_FFI_EXPORT void *wasmoon_dwarf_create(void) {
    dwarf_builder_t *builder = (dwarf_builder_t *)calloc(1, sizeof(dwarf_builder_t));
    builder->low_pc = UINT64_MAX;
    builder->high_pc = 0;
    return builder;
}

MOONBIT_FFI_EXPORT void wasmoon_dwarf_add_function(
    void *dwarf,
    const char *name,
    int64_t addr,
    int size,
    int func_idx
) {
    dwarf_builder_t *builder = (dwarf_builder_t *)dwarf;
    if (builder->num_functions >= MAX_DWARF_FUNCTIONS) {
        fprintf(stderr, "DWARF: too many functions (max %d)\n", MAX_DWARF_FUNCTIONS);
        return;
    }

    dwarf_func_t *func = &builder->functions[builder->num_functions++];
    strncpy(func->name, name, sizeof(func->name) - 1);
    func->name[sizeof(func->name) - 1] = '\0';
    func->addr = (uint64_t)addr;
    func->size = (uint32_t)size;
    func->func_idx = func_idx;

    // Update address range
    if (func->addr < builder->low_pc) {
        builder->low_pc = func->addr;
    }
    if (func->addr + func->size > builder->high_pc) {
        builder->high_pc = func->addr + func->size;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_dwarf_register(void *dwarf, int verbose) {
    dwarf_builder_t *builder = (dwarf_builder_t *)dwarf;

    if (builder->num_functions == 0) {
        return;
    }

    // Generate object file
    buffer_t object;
    buffer_init(&object, 8192);

#ifdef __APPLE__
    generate_macho_object(builder, &object);
#else
    generate_elf_object(builder, &object);
#endif

    // Store object buffer
    builder->object_buffer = (char *)object.data;
    builder->object_size = object.size;

    // Create JIT code entry
    struct jit_code_entry *entry = (struct jit_code_entry *)
        calloc(1, sizeof(struct jit_code_entry));
    entry->symfile_addr = builder->object_buffer;
    entry->symfile_size = builder->object_size;

    // Link into descriptor list
    entry->next_entry = __jit_debug_descriptor.first_entry;
    if (__jit_debug_descriptor.first_entry) {
        __jit_debug_descriptor.first_entry->prev_entry = entry;
    }
    __jit_debug_descriptor.first_entry = entry;

    // Register with debugger
    __jit_debug_descriptor.relevant_entry = entry;
    __jit_debug_descriptor.action_flag = JIT_REGISTER_FN;
    __jit_debug_register_code();
    __jit_debug_descriptor.action_flag = JIT_NOACTION;

    builder->code_entry = entry;

    // Debug output only when verbose flag is set
    if (verbose) {
        fprintf(stderr, "[DWARF] Registered %d functions with debugger (low_pc=0x%llx, high_pc=0x%llx)\n",
                builder->num_functions, builder->low_pc, builder->high_pc);
    }

    // Debug: dump object file for inspection (still uses env var)
    const char *dump_path = getenv("WASMOON_DWARF_DUMP");
    if (dump_path) {
        FILE *f = fopen(dump_path, "wb");
        if (f) {
            fwrite(builder->object_buffer, 1, builder->object_size, f);
            fclose(f);
            if (verbose) {
                fprintf(stderr, "[DWARF] Dumped object to %s (%zu bytes)\n", dump_path, builder->object_size);
            }
        }
    }
}

MOONBIT_FFI_EXPORT void wasmoon_dwarf_unregister(void *dwarf) {
    dwarf_builder_t *builder = (dwarf_builder_t *)dwarf;

    if (builder->code_entry) {
        // Unlink from descriptor list
        struct jit_code_entry *entry = builder->code_entry;

        if (entry->prev_entry) {
            entry->prev_entry->next_entry = entry->next_entry;
        } else {
            __jit_debug_descriptor.first_entry = entry->next_entry;
        }
        if (entry->next_entry) {
            entry->next_entry->prev_entry = entry->prev_entry;
        }

        // Notify debugger
        __jit_debug_descriptor.relevant_entry = entry;
        __jit_debug_descriptor.action_flag = JIT_UNREGISTER_FN;
        __jit_debug_register_code();
        __jit_debug_descriptor.action_flag = JIT_NOACTION;

        free(entry);
        builder->code_entry = NULL;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_dwarf_destroy(void *dwarf) {
    dwarf_builder_t *builder = (dwarf_builder_t *)dwarf;

    wasmoon_dwarf_unregister(dwarf);

    if (builder->object_buffer) {
        free(builder->object_buffer);
        builder->object_buffer = NULL;
    }

    free(builder);
}

// ============================================================================
// Backtrace Support
// ============================================================================

// Global pointer to the active DWARF builder for address lookups
static dwarf_builder_t *g_active_dwarf = NULL;

// Set the active DWARF builder for address lookups
MOONBIT_FFI_EXPORT void wasmoon_dwarf_set_active(void *dwarf) {
    g_active_dwarf = (dwarf_builder_t *)dwarf;
}

// Get JIT code address range (for frame walking boundary detection)
MOONBIT_FFI_EXPORT uint64_t wasmoon_dwarf_get_low_pc(void) {
    if (g_active_dwarf) {
        return g_active_dwarf->low_pc;
    }
    return 0;
}

MOONBIT_FFI_EXPORT uint64_t wasmoon_dwarf_get_high_pc(void) {
    if (g_active_dwarf) {
        return g_active_dwarf->high_pc;
    }
    return 0;
}

// Lookup an address in the DWARF builder
// Returns: 1 if found, 0 if not found
// If found, fills in name (up to name_size bytes), func_idx, and offset
MOONBIT_FFI_EXPORT int wasmoon_dwarf_lookup_address(
    void *dwarf,
    uint64_t addr,
    char *name_out,
    int name_size,
    int *func_idx_out,
    int64_t *offset_out
) {
    dwarf_builder_t *builder = (dwarf_builder_t *)dwarf;
    if (!builder) {
        builder = g_active_dwarf;
    }
    if (!builder || builder->num_functions == 0) {
        return 0;
    }

    // Linear search for the function containing this address
    for (int i = 0; i < builder->num_functions; i++) {
        dwarf_func_t *func = &builder->functions[i];
        if (addr >= func->addr && addr < func->addr + func->size) {
            // Found it
            if (name_out && name_size > 0) {
                strncpy(name_out, func->name, name_size - 1);
                name_out[name_size - 1] = '\0';
            }
            if (func_idx_out) {
                *func_idx_out = func->func_idx;
            }
            if (offset_out) {
                *offset_out = (int64_t)(addr - func->addr);
            }
            return 1;
        }
    }
    return 0;
}

// Maximum backtrace depth
#define MAX_BACKTRACE_DEPTH 64

// Backtrace frame structure
typedef struct {
    uint64_t pc;        // Program counter / return address
    uint64_t fp;        // Frame pointer
} backtrace_frame_t;

// Capture a backtrace using pre-captured frames from signal handler
// The frame chain was captured in the signal handler while the WASM stack was still valid
// Returns the number of frames captured
// frames_out should point to an array of at least MAX_BACKTRACE_DEPTH * 2 int64s
// (alternating pc, fp pairs)
MOONBIT_FFI_EXPORT int wasmoon_dwarf_capture_backtrace_ex(
    uint64_t initial_pc,
    uint64_t initial_fp,
    uint64_t initial_lr,
    int64_t *frames_out,
    int max_frames
) {
    (void)initial_pc;
    (void)initial_fp;
    (void)initial_lr;

    if (!frames_out || max_frames <= 0) {
        return 0;
    }
    if (max_frames > MAX_BACKTRACE_DEPTH) {
        max_frames = MAX_BACKTRACE_DEPTH;
    }

    // Use pre-captured frames from signal handler
    extern __thread volatile uintptr_t g_trap_frames_pc[];
    extern __thread volatile uintptr_t g_trap_frames_fp[];
    extern __thread volatile int g_trap_frame_count;

    int count = 0;
    int captured = g_trap_frame_count;
    if (captured > max_frames) {
        captured = max_frames;
    }

    for (int i = 0; i < captured; i++) {
        frames_out[count * 2] = (int64_t)g_trap_frames_pc[i];
        frames_out[count * 2 + 1] = (int64_t)g_trap_frames_fp[i];
        count++;
    }

    return count;
}

// Backward compatible wrapper
MOONBIT_FFI_EXPORT int wasmoon_dwarf_capture_backtrace(
    uint64_t initial_pc,
    uint64_t initial_fp,
    int64_t *frames_out,
    int max_frames
) {
    return wasmoon_dwarf_capture_backtrace_ex(initial_pc, initial_fp, 0, frames_out, max_frames);
}

// Format a backtrace as a string
// Returns the number of bytes written (excluding null terminator)
MOONBIT_FFI_EXPORT int wasmoon_dwarf_format_backtrace(
    void *dwarf,
    int64_t *frames,
    int frame_count,
    char *buffer,
    int buffer_size
) {
    if (!buffer || buffer_size <= 0) {
        return 0;
    }

    dwarf_builder_t *builder = (dwarf_builder_t *)dwarf;
    if (!builder) {
        builder = g_active_dwarf;
    }

    int written = 0;
    int remaining = buffer_size - 1;  // Reserve space for null terminator

    for (int i = 0; i < frame_count && remaining > 0; i++) {
        uint64_t pc = (uint64_t)frames[i * 2];

        char name[256] = "<unknown>";
        int func_idx = -1;
        int64_t offset = 0;

        if (builder) {
            wasmoon_dwarf_lookup_address(builder, pc, name, sizeof(name), &func_idx, &offset);
        }

        int n;
        if (func_idx >= 0) {
            n = snprintf(buffer + written, remaining,
                         "  #%d 0x%llx %s+0x%llx\n",
                         i, (unsigned long long)pc, name, (unsigned long long)offset);
        } else {
            n = snprintf(buffer + written, remaining,
                         "  #%d 0x%llx <unknown>\n",
                         i, (unsigned long long)pc);
        }

        if (n < 0 || n >= remaining) {
            break;
        }
        written += n;
        remaining -= n;
    }

    buffer[written] = '\0';
    return written;
}
