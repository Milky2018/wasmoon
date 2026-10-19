#include <libproc.h>
#include <sys/resource.h>
#include <unistd.h>
#include <stdio.h>
int main(void) {
    struct rusage_info_v4 a, b;
    int x=proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&a);
    volatile unsigned long long sum = 0;
    for (int i = 0; i < 1000000; ++i) sum += i;
    int y=proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&b);
    printf("%d %d %llu %llu %llu\n",x,y,b.ri_instructions-a.ri_instructions,b.ri_cycles-a.ri_cycles,sum);
}
