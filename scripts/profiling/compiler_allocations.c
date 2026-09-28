/* Diagnostic-only tracing for the serial native compiler fixture.
 * Compile generated MoonBit C and runtime.c with allocator substitutions.
 * Native stubs and mmap are outside this trace. Instrumented time/RSS are invalid
 * performance measurements: the recorder has its own large fixed tables.
 */
#include <dlfcn.h>
#include <execinfo.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *mi_malloc(size_t size);
void mi_free(void *pointer);

#define POINTER_SLOTS (1u << 22)
#define STACK_SLOTS (1u << 17)
#define STACK_DEPTH 10
#define TOMBSTONE ((void *)1)

typedef struct {
  void *pointer;
  size_t size;
  unsigned group;
} Allocation;

typedef struct {
  void *frames[STACK_DEPTH];
  unsigned depth;
  uint64_t count, total, live, peak;
} Stack;

static Allocation allocations[POINTER_SLOTS];
static Stack stacks[STACK_SLOTS];
static uint64_t live, total, count, peak, untracked_frees;

static unsigned pointer_slot(void *pointer) {
  uint64_t hash = ((uintptr_t)pointer >> 4) * UINT64_C(11400714819323198485);
  return (unsigned)(hash >> 42);
}

static void report(void) {
  const char *path = getenv("WASMOON_ALLOC_PROFILE");
  if (!path) return;
  FILE *file = fopen(path, "w");
  if (!file) abort();
  Dl_info image;
  if (!dladdr((void *)report, &image)) abort();
  fprintf(file, "base %p total %llu count %llu live %llu peak %llu untracked_frees %llu\n",
          image.dli_fbase, (unsigned long long)total, (unsigned long long)count,
          (unsigned long long)live, (unsigned long long)peak,
          (unsigned long long)untracked_frees);
  for (unsigned i = 0; i < STACK_SLOTS; i++) {
    Stack *stack = &stacks[i];
    if (!stack->count) continue;
    fprintf(file, "%llu %llu %llu %llu", (unsigned long long)stack->total,
            (unsigned long long)stack->count, (unsigned long long)stack->live,
            (unsigned long long)stack->peak);
    for (unsigned j = 0; j < stack->depth; j++)
      fprintf(file, " %p", stack->frames[j]);
    fputc('\n', file);
  }
  if (fclose(file)) abort();
}

__attribute__((constructor)) static void setup(void) {
  atexit(report);
}

void *probe_alloc(size_t size) {
  void *pointer = mi_malloc(size);
  if (!pointer) abort();
  void *frames[STACK_DEPTH] = {0};
  int depth = backtrace(frames, STACK_DEPTH);
  if (depth < 1) abort();
  unsigned hash = 0;
  for (int i = 1; i < depth; i++)
    hash = (hash * 33) ^ ((uintptr_t)frames[i] >> 2);
  hash &= STACK_SLOTS - 1;
  unsigned probes = 0;
  while (stacks[hash].count &&
         (stacks[hash].depth != (unsigned)depth - 1 ||
          memcmp(stacks[hash].frames, frames + 1, (depth - 1) * sizeof(void *)))) {
    if (++probes == STACK_SLOTS) abort();
    hash = (hash + 1) & (STACK_SLOTS - 1);
  }
  Stack *stack = &stacks[hash];
  if (!stack->count) {
    stack->depth = depth - 1;
    memcpy(stack->frames, frames + 1, (depth - 1) * sizeof(void *));
  }
  stack->count++;
  stack->total += size;
  stack->live += size;
  if (stack->live > stack->peak) stack->peak = stack->live;
  unsigned slot = pointer_slot(pointer);
  probes = 0;
  while (allocations[slot].pointer && allocations[slot].pointer != TOMBSTONE) {
    if (++probes == POINTER_SLOTS) abort();
    slot = (slot + 1) & (POINTER_SLOTS - 1);
  }
  allocations[slot] = (Allocation){pointer, size, hash};
  total += size;
  count++;
  live += size;
  if (live > peak) peak = live;
  return pointer;
}

void probe_free(void *pointer) {
  if (pointer) {
    unsigned slot = pointer_slot(pointer);
    unsigned probes = 0;
    while (allocations[slot].pointer && allocations[slot].pointer != pointer) {
      if (++probes == POINTER_SLOTS) abort();
      slot = (slot + 1) & (POINTER_SLOTS - 1);
    }
    if (allocations[slot].pointer == pointer) {
      live -= allocations[slot].size;
      stacks[allocations[slot].group].live -= allocations[slot].size;
      allocations[slot].pointer = TOMBSTONE;
    } else {
      untracked_frees++;
    }
  }
  mi_free(pointer);
}
