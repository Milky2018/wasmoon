#include <libproc.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
static struct rusage_info_v4 start;
static struct timespec start_cpu;
static int started;
void profiled_putchar(int sentinel) {
    struct rusage_info_v4 now;
    struct timespec cpu;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpu)) abort();
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&now)) abort();
    if (sentinel == 1 && !started) {
        start = now; start_cpu = cpu; started = 1;
    } else if (sentinel == 2 && started) {
        long long elapsed = (cpu.tv_sec - start_cpu.tv_sec) * 1000000000LL + cpu.tv_nsec - start_cpu.tv_nsec;
        fprintf(stderr, "[DEBUG-rootcause-store] %lld %llu %llu\n", elapsed,
            now.ri_instructions - start.ri_instructions, now.ri_cycles - start.ri_cycles);
        started = 0;
    } else abort();
}

// The spectest native import calls putchar directly. Only the two diagnostic
// boundaries may call it; their argument is irrelevant to the measurement.
static int instrumented_putchar(int ignored) {
    static int calls;
    if (++calls > 2) abort();
    profiled_putchar(calls);
    return ignored;
}

__attribute__((used)) static struct {
    const void *replacement;
    const void *original;
} interpose_putchar __attribute__((section("__DATA,__interpose"))) = {
    (const void *)instrumented_putchar, (const void *)putchar
};
