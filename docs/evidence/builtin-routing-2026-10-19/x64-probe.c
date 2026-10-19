#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include "code.h"
extern void probe(void *, uint64_t *, uint64_t *);
static int bridge(void *ctx, int32_t id, int64_t *values, int32_t args, int32_t results) {
    (void)ctx;
    if (id != 17 || args != 0 || results != 10) abort();
    for (int i = 0; i < 10; ++i) values[i] = 100 + i;
    return 0;
}
int main(void) {
    int patched = 0;
    for (size_t i = 0; i + 13 <= sizeof(code); ++i) {
        if (code[i] == 0x49 && code[i + 1] == 0xbb && code[i + 10] == 0x41 && code[i + 11] == 0xff && code[i + 12] == 0xd3) {
            uintptr_t target = (uintptr_t)bridge;
            memcpy(code + i + 2, &target, sizeof(target));
            patched++;
        }
    }
    if (patched != 1) abort();
    void *entry = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (entry == MAP_FAILED) abort();
    memcpy(entry, code, sizeof(code));
    if (mprotect(entry, 4096, PROT_READ | PROT_EXEC)) abort();
    uint64_t values[10] = {0};
    probe(entry, values, values + 8);
    int passed = 1;
    for (int i = 0; i < 10; ++i) {
        printf("result[%d]=%llu expected=%d\n", i, (unsigned long long)values[i], 100 + i);
        if (values[i] != (uint64_t)(100 + i)) passed = 0;
    }
    munmap(entry, 4096);
    return passed ? 0 : 1;
}
