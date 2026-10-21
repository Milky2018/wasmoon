// Invoke the real managed create/publish callbacks with a borrowed request.
// No guest instructions are executed; this fixture tests unpublished ownership.
MOONBIT_FFI_EXPORT int64_t wasmoon_test_create_continuation(
    void *state, void *context,
    int64_t (*create)(void *, continuation_create_request_t *)) {
    int32_t roots[] = {1};
    native_continuation_type_t type = {0};
    type.params = 1;
    type.roots = roots;
    jit_context_t *ctx = (void *)(uintptr_t)wasmoon_jit_context_ptr(context);
    continuation_create_request_t request = {ctx, &type, 1};
    // The body borrows type. The callback must close it or finish examining it
    // synchronously, before the request and type leave this scope.
    return create(state, &request);
}
