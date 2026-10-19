#include <libproc.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
static struct rusage_info_v4 start;
static int boundaries;
static int instrumented_clock_gettime(clockid_t clock, struct timespec *value) {
    int result = clock_gettime(clock, value);
    if (clock == CLOCK_THREAD_CPUTIME_ID) {
        struct rusage_info_v4 now;
        if (result || proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&now)) abort();
        if (++boundaries == 1) start = now;
        else if (boundaries == 2) {
            fprintf(stderr, "[DEBUG-rootcause-counters] %llu %llu\n",
                now.ri_instructions - start.ri_instructions,
                now.ri_cycles - start.ri_cycles);
        } else abort();
    }
    return result;
}
__attribute__((used)) static struct {
    const void *replacement;
    const void *original;
} interpose_clock __attribute__((section("__DATA,__interpose"))) = {
    (const void *)instrumented_clock_gettime, (const void *)clock_gettime
};
