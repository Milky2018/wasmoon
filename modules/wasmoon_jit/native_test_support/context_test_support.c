#include "../jit_ffi/jit_internal.h"

extern void wasmoon_jit_ctx_init_data_segments(int64_t ctx, int count);
extern void wasmoon_jit_ctx_init_elem_segments(int64_t ctx, int count);

// Exercise the optional state's ownership through reset, reuse and destruction.
MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_optional_state(void) {
    jit_context_t *first = alloc_context_internal(1);
    jit_context_t *second = alloc_context_internal(1);
    if (!first || !second) {
        free_context_internal(first);
        free_context_internal(second);
        return 0;
    }
    int passed = !ctx_runtime(first)->segments &&
        !ctx_runtime(first)->exception_arena && !ctx_runtime(first)->continuation_arena;
    int64_t address = (int64_t)(uintptr_t)first;
    wasmoon_jit_ctx_init_data_segments(address, 0);
    wasmoon_jit_ctx_init_elem_segments(address, 0);
    passed = passed && !ctx_runtime(first)->segments;
    wasmoon_jit_ctx_init_data_segments(address, 1);
    wasmoon_jit_ctx_init_elem_segments(address, 2);
    passed = passed && ctx_runtime(first)->segments &&
        Moonbit_array_length(ctx_runtime(first)->segments->data_segments) == 1 &&
        Moonbit_array_length(ctx_runtime(first)->segments->elem_segments) == 2 &&
        !ctx_runtime(second)->segments;
    ctx_clear_segments_internal(first);
    passed = passed && !ctx_runtime(first)->segments;
    ctx_clear_segments_internal(first);
    wasmoon_jit_ctx_init_elem_segments(address, 1);
    passed = passed && ctx_runtime(first)->segments &&
        Moonbit_array_length(ctx_runtime(first)->segments->elem_segments) == 1 &&
        !ctx_runtime(first)->segments->data_segments;
    free_context_internal(first);
    free_context_internal(second);
    return passed;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_safepoint_ownership(void) {
    jit_context_t *ctx = alloc_context_internal(3);
    if (!ctx) return 0;
    uint8_t blob[] = {1, 2, 3};
    int32_t offsets[] = {4, 12};
    int passed = !ctx_runtime(ctx)->gc_func_safepoint_tables;
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 1, blob, 3, offsets, 2);
    wasmoon_gc_safepoint_table_t *table = &ctx_runtime(ctx)->gc_func_safepoint_tables[1];
    blob[0] = 9;
    offsets[0] = 20;
    passed &= table->stackmap_blob[0] == 1 && table->code_offsets[0] == 4;
    ctx_gc_use_func_safepoints_internal(ctx, 1);
    passed &= ctx_runtime(ctx)->gc_safepoint_table == table;
    // Replacing one slot must release its previous copies and preserve peers.
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 2, blob, 3, offsets, 2);
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 1, blob, 1, offsets, 1);
    passed &= table->stackmap_blob_size == 1 && table->code_offsets[0] == 20;
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 1, NULL, 0, NULL, 0);
    passed &= !table->stackmap_blob && !table->code_offsets;
    ctx_gc_use_func_safepoints_internal(ctx, 1);
    passed &= !ctx_runtime(ctx)->gc_safepoint_table;
    passed &= ctx_runtime(ctx)->gc_func_safepoint_tables[2].stackmap_blob[0] == 9;
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 1, blob, 3, offsets, 2);
    free_context_internal(ctx);
    return passed;
}

extern int64_t wasmoon_jit_context_ptr(void *context);

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_storage_bytes(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    const uint8_t *layout = ctx_runtime(ctx)->layout;
    if (!layout) return (int32_t)sizeof(jit_context_owner_t);
    if (ctx_memories(ctx)) assert((char *)ctx_memories(ctx) == (char *)ctx + context_layout_field(layout, 24));
    if (ctx_tables(ctx)) assert((char *)ctx_tables(ctx) == (char *)ctx + context_layout_field(layout, 25));
    if (ctx_table_sizes(ctx)) assert((char *)ctx_table_sizes(ctx) == (char *)ctx + context_layout_field(layout, 26));
    if (ctx_table_max_sizes(ctx)) assert((char *)ctx_table_max_sizes(ctx) == (char *)ctx + context_layout_field(layout, 27));
    return (int32_t)sizeof(jit_runtime_state_t) + context_layout_field(layout, 23);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_layout_shared(void *first, void *second) {
    jit_context_t *a = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(first);
    jit_context_t *b = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(second);
    return ctx_runtime(a)->layout && ctx_runtime(a)->layout == ctx_runtime(b)->layout;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_callable_lookup(void *view, int64_t value) {
    jit_context_owner_t owner = {0};
    owner.runtime.callable_registry = view;
    return callable_type_for_value(&owner.abi, value);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_callable_lookup(void *context, int64_t value) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return callable_type_for_value(ctx, value);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_callable_subtype(void *context, int64_t value, int32_t expected) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return gc_ref_test_impl(ctx, FUNCREF_TAG | value, expected, 0);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_callable_tag(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return ctx_runtime(ctx)->callable_tag_count ? ctx_runtime(ctx)->callable_tags[0] : -1;
}

// Scratch roots belong to an invocation, including while it is parked.
MOONBIT_FFI_EXPORT int32_t wasmoon_test_activation_scratch_isolation(void) {
    jit_context_t *ctx = alloc_context_internal(1);
    if (!ctx) return 0;
    jit_trap_activation_t outer, inner;
    jit_trap_activation_init(&outer, ctx);
    jit_trap_activation_push(&outer);
    int64_t first = 16, second = 32;
    int passed = ctx_gc_set_root_scratch_internal(ctx, &first, 1);
    jit_trap_activation_init(&inner, ctx);
    jit_trap_activation_push(&inner);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 0;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &second, 1);
    jit_trap_activation_pop(&inner);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 1 &&
        ctx_execution(ctx)->gc_root_scratch[0] == first;
    jit_trap_activation_detach();
    jit_trap_activation_init(&inner, ctx);
    jit_trap_activation_push(&inner);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 0;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &second, 1);
    jit_trap_activation_abandon(&outer);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 1 &&
        ctx_execution(ctx)->gc_root_scratch[0] == second;
    jit_trap_activation_pop(&inner);
    free_context_internal(ctx);
    return passed;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_activation_resume_roots(void) {
    jit_context_t *ctx = alloc_context_internal(1);
    if (!ctx) return 0;
    GcHeap *heap = gc_heap_new(1024);
    ctx_set_gc_heap_internal(ctx, heap);
    int32_t ref = gc_heap_alloc_struct(heap, 0, NULL, 0);
    int64_t root = (int64_t)ref << 1;
    jit_trap_activation_t parked, caller;
    jit_trap_activation_init(&parked, ctx);
    jit_trap_activation_push(&parked);
    ctx_set_debug_current_func_idx(ctx, 17);
    int passed = ref != 0 && ctx_gc_set_root_scratch_internal(ctx, &root, 1);
    jit_trap_activation_detach();
    void *registration = NULL;
    passed &= jit_parked_gc_roots_register(&parked, &registration);
    gc_heap_collect(heap, NULL, 0);
    passed &= gc_heap_is_valid(heap, ref);
    jit_trap_activation_init(&caller, ctx);
    jit_trap_activation_push(&caller);
    ctx_set_debug_current_func_idx(ctx, 23);
    int64_t other = 1;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &other, 1);
    jit_trap_activation_attach(&parked);
    passed &= ctx_debug_current_func_idx(ctx) == 17;
    passed &= ctx_execution(ctx)->gc_root_scratch[0] == root;
    jit_parked_gc_roots_unregister(registration);
    registration = NULL;
    jit_trap_activation_pop(&parked);
    passed &= ctx_debug_current_func_idx(ctx) == 23;
    passed &= ctx_execution(ctx)->gc_root_scratch[0] == other;
    jit_trap_activation_pop(&caller);
    gc_heap_collect(heap, NULL, 0);
    passed &= !gc_heap_is_valid(heap, ref);
    // Standalone state is independent and destroyed by context teardown.
    passed &= ctx_runtime(ctx)->execution == NULL;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &other, 1);
    jit_trap_activation_init(&caller, ctx);
    jit_trap_activation_push(&caller);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 1 &&
        ctx_execution(ctx)->gc_root_scratch[0] == other;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &root, 1);
    jit_trap_activation_pop(&caller);
    passed &= ctx_execution(ctx)->gc_root_scratch[0] == other;
    free_context_internal(ctx);
    moonbit_decref(heap);
    return passed;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_gc_funcref_subtype(
    void *context, int32_t function, int32_t expected
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    if (!ctx || function < 0 || function >= ctx_runtime(ctx)->gc_num_funcs ||
        !ctx_runtime(ctx)->gc_func_type_indices) return 0;
    jit_trap_activation_t activation;
    jit_trap_activation_init(&activation, ctx);
    jit_trap_activation_push(&activation);
    int result = is_subtype_cached(ctx_runtime(ctx)->gc_func_type_indices[function], expected);
    jit_trap_activation_pop(&activation);
    return result;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_gc_legacy_rebind(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    int32_t types[] = {-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    int32_t canonical[] = {0, 1};
    int32_t functions[] = {1};
    set_type_cache_internal(ctx, types, 2);
    set_canonical_indices_internal(ctx, canonical, 2);
    set_func_type_indices_internal(ctx, functions, 1);
    types[6] = -1;
    canonical[1] = 0;
    functions[0] = 0;
    jit_runtime_state_t *state = ctx_runtime(ctx);
    int passed = state->gc_type_cache[6] == 0 &&
        state->gc_canonical_indices[1] == 1 && state->gc_func_type_indices[0] == 1;
    clear_type_cache_internal(ctx);
    clear_type_cache_internal(ctx);
    return passed && !state->gc_type_cache && !state->gc_canonical_indices &&
        !state->gc_func_type_indices;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_gc_metadata_shares(
    void *context, int32_t *types, int32_t *canonical, int32_t *functions
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    jit_runtime_state_t *state = ctx_runtime(ctx);
    return state->gc_type_cache == types && state->gc_canonical_indices == canonical &&
        state->gc_func_type_indices == functions;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_gc_payload_shares(
    void *context, uint8_t *blob, int32_t *offsets, int64_t *addresses
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    jit_runtime_state_t *state = ctx_runtime(ctx);
    return state->gc_func_safepoint_tables[0].stackmap_blob == blob &&
        state->gc_func_safepoint_tables[0].code_offsets == (uint32_t *)offsets &&
        state->gc_func_table == addresses;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_gc_payload_valid(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    jit_runtime_state_t *state = ctx_runtime(ctx);
    wasmoon_gc_safepoint_table_t *table = &state->gc_func_safepoint_tables[0];
    return table->stackmap_blob_size == 3 && table->stackmap_blob[2] == 3 &&
        table->safepoint_count == 2 && table->code_offsets[1] == 12 &&
        state->gc_func_table_size == 2 && state->gc_func_table[1] == 32;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_gc_payload_legacy(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    jit_runtime_state_t *state = ctx_runtime(ctx);
    wasmoon_gc_safepoint_table_t *table = &state->gc_func_safepoint_tables[0];
    uint8_t blob[] = {1, 2, 3};
    int32_t offsets[] = {4, 12};
    void *addresses[] = {(void *)(uintptr_t)16, (void *)(uintptr_t)32};
    int passed = ctx_gc_set_func_safepoints_internal(ctx, 0, blob, 3, offsets, 2);
    set_func_table_internal(ctx, addresses, 2);
    blob[2] = 99;
    offsets[1] = 99;
    addresses[1] = NULL;
    return passed && table == &state->gc_func_safepoint_tables[0] &&
        wasmoon_test_context_gc_payload_valid(context);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_gc_payload_empty(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    jit_runtime_state_t *state = ctx_runtime(ctx);
    wasmoon_gc_safepoint_table_t *table = &state->gc_func_safepoint_tables[0];
    return !table->stackmap_blob && !table->code_offsets &&
        !table->stackmap_blob_size && !table->safepoint_count &&
        !state->gc_func_table && !state->gc_func_table_size;
}

static int control_capture_releases;
static void release_control_capture(void *capture) {
    (void)capture;
    control_capture_releases++;
}
static int32_t poll_control_capture(void *capture) {
    return *(int32_t *)capture;
}
extern void wasmoon_jit_set_cancellation_callback(
    int64_t context, int32_t (*callback)(void *), void *capture);
extern void wasmoon_jit_clear_cancellation_callback(int64_t context);

static void set_control_capture(jit_context_t *ctx, int32_t value) {
    int32_t *capture = moonbit_make_external_object(release_control_capture, sizeof(int32_t));
    *capture = value;
    wasmoon_jit_set_cancellation_callback((int64_t)(uintptr_t)ctx,
        poll_control_capture, capture);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_activation_controls(void) {
    jit_context_t *ctx = alloc_context_internal(1);
    jit_context_t *other = alloc_context_internal(1);
    if (!ctx || !other) {
        free_context_internal(ctx);
        free_context_internal(other);
        return 0;
    }
    control_capture_releases = 0;
    set_control_capture(ctx, 1);
    ctx_runtime(ctx)->control_defaults.scheduling_budget = 9;
    jit_trap_activation_t root, child, bound, caller;
    jit_trap_activation_init(&root, ctx);
    jit_trap_activation_push(&root);
    wasmoon_jit_clear_cancellation_callback((int64_t)(uintptr_t)ctx);
    int passed = control_capture_releases == 0 && wasmoon_jit_cancellation_requested(ctx);
    root.controls->scheduling_budget = 3;
    set_control_capture(ctx, 0);
    ctx_runtime(ctx)->control_defaults.scheduling_budget = 5;
    jit_trap_activation_init(&child, ctx);
    jit_trap_activation_push(&child);
    passed &= !wasmoon_jit_cancellation_requested(ctx) &&
        child.controls->scheduling_budget == 5 && root.controls->scheduling_budget == 3;
    jit_trap_activation_init(&bound, other);
    bound.inherit_controls = 1;
    jit_trap_activation_push(&bound);
    passed &= bound.controls == child.controls;
    bound.controls->scheduling_budget--;
    jit_trap_activation_detach();
    passed &= child.controls->scheduling_budget == 4;
    jit_trap_activation_pop(&child);
    // A resumed continuation inherits its actual caller, not its old caller.
    jit_trap_activation_attach(&bound);
    passed &= bound.controls == root.controls && wasmoon_jit_cancellation_requested(other);
    jit_trap_activation_pop(&bound);
    jit_trap_activation_detach();
    jit_trap_activation_init(&caller, ctx);
    jit_trap_activation_push(&caller);
    jit_trap_activation_attach(&root);
    passed &= root.controls == &root.owned_controls &&
        root.controls->scheduling_budget == 3 && wasmoon_jit_cancellation_requested(ctx);
    jit_trap_activation_pop(&root);
    passed &= control_capture_releases == 1 && !wasmoon_jit_cancellation_requested(ctx);
    jit_trap_activation_detach();
    wasmoon_jit_clear_cancellation_callback((int64_t)(uintptr_t)ctx);
    passed &= control_capture_releases == 1;
    jit_trap_activation_abandon(&caller);
    passed &= control_capture_releases == 2;
    free_context_internal(other);
    free_context_internal(ctx);
    return passed;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_segments_share_data(void *context, uint8_t *data) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return ctx_runtime(ctx)->segments && ctx_runtime(ctx)->segments->data_segments[0] == data;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_segments_valid(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    jit_segments_state_t *state = ctx_runtime(ctx)->segments;
    return state && Moonbit_array_length(state->data_segments) == 1 &&
        Moonbit_array_length(state->elem_segments) == 1 &&
        Moonbit_array_length(state->data_segments[0]) == 3 && state->data_segments[0][2] == 3 &&
        Moonbit_array_length(state->elem_segments[0]) == 2 && state->elem_segments[0][0] == 16;
}

extern void wasmoon_jit_ctx_add_data_segment(int64_t, int, uint8_t *, int, int);
extern void wasmoon_jit_ctx_add_elem_segment(int64_t, int, int64_t *, int, int);

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_segments_legacy(void *context) {
    int64_t address = wasmoon_jit_context_ptr(context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)address;
    uint8_t data[] = {1, 2, 3};
    int64_t elements[] = {16, 0};
    wasmoon_jit_ctx_add_data_segment(address, 0, data, 3, 0);
    wasmoon_jit_ctx_add_elem_segment(address, 0, elements, 1, 0);
    data[2] = 99;
    elements[0] = 99;
    int passed = wasmoon_test_context_segments_valid(context);
    wasmoon_jit_ctx_add_data_segment(address, 0, data, 3, 1);
    wasmoon_jit_ctx_add_elem_segment(address, 0, elements, 1, 1);
    passed &= Moonbit_array_length(ctx_runtime(ctx)->segments->data_segments[0]) == 0 &&
        Moonbit_array_length(ctx_runtime(ctx)->segments->elem_segments[0]) == 0;
    return passed;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_segments_empty(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return !ctx_runtime(ctx)->segments;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_function_array(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    if (!ctx || Moonbit_array_length(ctx_func_table(ctx)) != ctx_func_count(ctx)) return 0;
    for (int i = 0; i < ctx_func_count(ctx); ++i) {
        if (ctx_func_table(ctx)[i]) return 0;
        // Array teardown must not treat these borrowed addresses as RC objects.
        ctx_func_table(ctx)[i] = (void *)(uintptr_t)(16 + i * 16);
        if (ctx_func_table(ctx)[i] != (void *)(uintptr_t)(16 + i * 16)) return 0;
    }
    return 1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_raw_context_function_array(void) {
    int passed = alloc_context_internal(-1) == NULL;
    for (int count = 0; count < 3; ++count) {
        jit_context_t *ctx = alloc_context_internal(count);
        if (!ctx) return 0;
        passed &= Moonbit_array_length(ctx_func_table(ctx)) == count;
        for (int i = 0; i < count; ++i) {
            passed &= ctx_func_table(ctx)[i] == NULL;
            ctx_func_table(ctx)[i] = (void *)(uintptr_t)(16 + i * 16);
        }
        free_context_internal(ctx);
    }
    return passed;
}

// Exercise RC-to-legacy and legacy-to-RC replacement under sanitizers.
MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_globals_ownership(void) {
    jit_context_t *ctx = alloc_context_internal(0);
    if (!ctx) return 0;
    int64_t *managed = moonbit_make_int64_array(2, 0);
    managed[0] = 16;
    managed[1] = 32;
    moonbit_incref(managed);
    ctx_set_globals_internal(ctx, managed, 1);
    moonbit_incref(managed);
    ctx_set_globals_internal(ctx, managed, 1);
    int passed = ctx_globals(ctx) == managed && managed[1] == 32;
    int64_t *legacy = malloc(2 * sizeof(int64_t));
    if (!legacy) { moonbit_decref(managed); free_context_internal(ctx); return 0; }
    legacy[0] = 48;
    ctx_set_globals_internal(ctx, legacy, 0);
    ctx_set_globals_internal(ctx, legacy, 0);
    passed &= ((int64_t *)ctx_globals(ctx))[0] == 48 && managed[0] == 16;
    ctx_set_globals_internal(ctx, managed, 1);
    free_context_internal(ctx);
    return passed;
}

// Observe allocation/identity without adding counters to production contexts.
MOONBIT_FFI_EXPORT int32_t wasmoon_test_safepoint_slots(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return ctx_runtime(ctx)->gc_func_safepoint_table_count;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_safepoints_shared(void *first, void *second) {
    jit_context_t *a = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(first);
    jit_context_t *b = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(second);
    return ctx_runtime(a)->gc_func_safepoint_tables &&
        ctx_runtime(a)->gc_func_safepoint_tables == ctx_runtime(b)->gc_func_safepoint_tables;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_safepoint_parked_sharing(void *first, void *second) {
    jit_context_t *a = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(first);
    jit_context_t *b = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(second);
    jit_trap_activation_t parked;
    jit_trap_activation_init(&parked, b);
    jit_trap_activation_push(&parked);
    ctx_gc_use_func_safepoints_internal(b, 0);
    ctx_gc_begin_frame_internal(b, 123);
    const wasmoon_gc_frame_t *frame = ctx_execution(b)->gc_frame_chain_head;
    int passed = frame && frame->table && frame->table->stackmap_blob[0] == 1 && frame->table->code_offsets[0] == 4;
    jit_trap_activation_detach();
    uint8_t blob = 9;
    int32_t offset = 7;
    passed &= ctx_gc_set_func_safepoints_internal(a, 0, &blob, 1, &offset, 1);
    passed &= ctx_runtime(a)->gc_func_safepoint_tables != ctx_runtime(b)->gc_func_safepoint_tables;
    passed &= frame->table->stackmap_blob[0] == 1;
    jit_trap_activation_attach(&parked);
    passed &= ctx_execution(b)->gc_frame_chain_head == frame;
    ctx_gc_end_frame_internal(b);
    jit_trap_activation_pop(&parked);
    passed &= ctx_runtime(a)->gc_func_safepoint_tables[0].stackmap_blob[0] == 9;
    return passed;
}
