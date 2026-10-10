/*
 * swprof: what a context switch costs in hardware events (Cortex-A8 PMU via perf_event_open), for
 * threads (no address space change) against processes, the same pipe ping-pong as kbench. Run as
 * root on the test kernel, CPU pinned: swprof thread|process [ROUNDS]
 * Prints per switch, user and kernel together (the A8's PMU can't tell them apart): cycles,
 * instructions, branch mispredicts, exceptions taken, L1 I and D, L2 and I and D TLB refills. Two
 * passes (the A8 has 4 event counters and the cycle counter).
 * NOPERF=1: no perf events (they reprogram the cycle counter at every switch, which breaks the
 * kernel's sched_prof), only the ping-pong and its time per switch.
 */
#include <linux/perf_event.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int ROUNDS = 20000;

static int tp[4];

static void *pong(void *x)
{
	char c;

	while (read(tp[0], &c, 1) == 1 && write(tp[3], &c, 1) == 1)
		;
	return NULL;
}

/* ARMv7 events: raw numbers from the Cortex-A8 TRM, PMU chapter */
struct ev { const char *name; __u32 type; __u64 config; int unused; };

static const struct ev pass[2][5] = {
	{ { "cycles", PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES, 0 },
	  { "instructions", PERF_TYPE_RAW, 0x08, 0 },
	  { "branch mispredicts", PERF_TYPE_RAW, 0x10, 0 },
	  { "L1 I refills", PERF_TYPE_RAW, 0x01, 0 },
	  { "I TLB refills", PERF_TYPE_RAW, 0x02, 0 } },
	{ { "cycles", PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES, 0 },
	  { "exceptions taken", PERF_TYPE_RAW, 0x09, 0 },
	  { "L1 D refills", PERF_TYPE_RAW, 0x03, 0 },
	  { "D TLB refills", PERF_TYPE_RAW, 0x05, 0 },
	  { "L2 refills", PERF_TYPE_RAW, 0x44, 0 } },
};

static void run(int process)
{
	char c = 0;
	int i;

	if (pipe(tp) || pipe(tp + 2))
		exit(1);
	if (process) {
		if (!fork()) {
			close(tp[1]);	/* else no EOF when the parent is done */
			close(tp[2]);
			while (read(tp[0], &c, 1) == 1 && write(tp[3], &c, 1) == 1)
				;
			_exit(0);
		}
	} else {
		pthread_t th;

		if (pthread_create(&th, NULL, pong, NULL))
			exit(1);
	}
	for (i = 0; i < ROUNDS; i++)
		if (write(tp[1], &c, 1) != 1 || read(tp[2], &c, 1) != 1)
			break;
	close(tp[1]);
	/* inherited counts reach the parent's counters when the child or thread exits */
	if (process)
		wait(NULL);
	else
		usleep(100000);
	close(tp[0]);
	close(tp[2]);
	close(tp[3]);
}

int main(int argc, char **argv)
{
	int process = argc > 1 && !strcmp(argv[1], "process");
	int p, n;

	if (argc > 2)
		ROUNDS = atoi(argv[2]);
	if (getenv("NOPERF")) {
		struct timespec a, b;

		clock_gettime(CLOCK_MONOTONIC, &a);
		run(process);
		clock_gettime(CLOCK_MONOTONIC, &b);
		/* includes the fork or thread start and the final wait or 100 ms sleep */
		printf("%.2f us per switch\n", ((b.tv_sec - a.tv_sec) * 1e6 + (b.tv_nsec - a.tv_nsec) / 1e3
		       - (process ? 0 : 100000)) / (2.0 * ROUNDS));
		return 0;
	}

	for (p = 0; p < 2; p++) {
		int fd[5];

		for (n = 0; n < 5 && pass[p][n].name; n++) {
			struct perf_event_attr a;

			memset(&a, 0, sizeof(a));
			a.size = sizeof(a);
			a.type = pass[p][n].type;
			a.config = pass[p][n].config;
			a.disabled = 1;
			a.inherit = 1;
			a.read_format = PERF_FORMAT_TOTAL_TIME_ENABLED | PERF_FORMAT_TOTAL_TIME_RUNNING;
			fd[n] = syscall(__NR_perf_event_open, &a, 0, -1, -1, 0);
			if (fd[n] < 0) {
				perror(pass[p][n].name);
				return 1;
			}
		}
		for (int k = 0; k < n; k++)
			ioctl(fd[k], PERF_EVENT_IOC_ENABLE, 0);
		run(process);
		for (int k = 0; k < n; k++) {
			unsigned long long v[3] = { 0 };

			ioctl(fd[k], PERF_EVENT_IOC_DISABLE, 0);
			if (read(fd[k], v, sizeof(v)) != sizeof(v))
				return 1;
			/* scaled if the counter was multiplexed; running 0 = never scheduled */
			printf("%-24s %9.1f per switch (counted %llu%% of the time)\n", pass[p][k].name,
			       v[2] ? v[0] * (double)v[1] / v[2] / (2.0 * ROUNDS) : 0.0,
			       v[1] ? v[2] * 100 / v[1] : 0);
			close(fd[k]);
		}
	}
	return 0;
}
