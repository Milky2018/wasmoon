// Moon native-stub driver: Microsoft C compilation and MASM assembly only.
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

// The CRT spawn family joins arguments without quoting them.
static wchar_t *quote(const wchar_t *arg) {
    size_t n = wcslen(arg), used = 0, slashes = 0;
    wchar_t *out = calloc(n * 2 + 3, sizeof(wchar_t));
    if (!out) exit(2);
    out[used++] = L'"';
    for (size_t i = 0; i <= n; i++) {
        wchar_t c = arg[i];
        if (c == L'\\') { slashes++; continue; }
        size_t copies = (c == L'"' || c == 0) ? slashes * 2 : slashes;
        while (copies--) out[used++] = L'\\';
        slashes = 0;
        if (!c) break;
        if (c == L'"') out[used++] = L'\\';
        out[used++] = c;
    }
    out[used++] = L'"';
    out[used] = 0;
    return out;
}

int wmain(int argc, wchar_t **argv) {
    const wchar_t *tool = _wgetenv(L"WASMOON_MSVC_CL");
    const wchar_t **args = calloc((size_t)argc + 8, sizeof(wchar_t *));
    if (!args || !tool) { fwprintf(stderr, L"Run scripts/msvc/setup.ps1 first.\n"); return 2; }
    int count = 0;
    const wchar_t *base = wcsrchr(argv[0], L'\\');
    base = base ? base + 1 : argv[0];
    int librarian = _wcsicmp(base, L"lib.exe") == 0;
    const wchar_t *assembly = NULL, *output = NULL;
    for (int i = 1; i < argc; i++) {
        size_t n = wcslen(argv[i]);
        if (n > 2 && wcscmp(argv[i] + n - 2, L".S") == 0) assembly = argv[i];
        if (wcsncmp(argv[i], L"/Fo", 3) == 0) output = argv[i];
    }
    if (librarian) tool = _wgetenv(L"WASMOON_MSVC_LIB");
    else if (assembly) tool = _wgetenv(L"WASMOON_MSVC_ML64");
    if (!tool) return 2;
    args[count++] = quote(tool);
    if (assembly) {
        if (!output) { fwprintf(stderr, L"Missing MASM object output.\n"); return 2; }
        wchar_t *source = calloc(wcslen(assembly) + 5, sizeof(wchar_t));
        if (!source) return 2;
        wcscpy(source, assembly);
        wcscpy(source + wcslen(source) - 2, L".asm");
        args[count++] = quote(L"/nologo");
        args[count++] = quote(L"/c");
        args[count++] = quote(output);
        args[count++] = quote(source);
    } else {
        if (!librarian) {
            args[count++] = quote(L"/experimental:c11atomics");
            args[count++] = quote(L"/D_CRT_SECURE_NO_WARNINGS");
        }
        for (int i = 1; i < argc; i++) args[count++] = quote(argv[i]);
    }
    intptr_t status = _wspawnv(_P_WAIT, tool, args);
    if (status == -1) { _wperror(tool); return 2; }
    return (int)status;
}
