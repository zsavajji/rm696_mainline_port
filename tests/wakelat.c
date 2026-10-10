/*
 * wakelat: how late a timer wakes this task, so the exit latency of the idle state the CPU woke from
 * (test kernel, root; the phone idle and unplugged). Sleeps to absolute CLOCK_MONOTONIC targets
 * 200-1000 ms apart (random, so other periodic timers don't lock to it), SCHED_FIFO, timer slack 1 ns.
 * wakelat SECONDS: one line per wake: the lateness in us, then how often each cpuidle state
 * (state0..state6 = C1..C7) was entered during that sleep.
 */
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <time.h>

#define NS 7

static void usage(long *u)
{
	char p[64];
	int i;

	for (i = 0; i < NS; i++) {
		FILE *f;

		snprintf(p, sizeof(p), "/sys/devices/system/cpu/cpu0/cpuidle/state%d/usage", i);
		f = fopen(p, "r");
		if (!f || fscanf(f, "%ld", &u[i]) != 1)
			u[i] = 0;
		if (f)
			fclose(f);
	}
}

int main(int argc, char **argv)
{
	struct sched_param sp = { .sched_priority = 50 };
	struct timespec t, w;
	long a[NS], b[NS], end;
	int i;

	if (argc != 2)
		return fprintf(stderr, "usage: wakelat SECONDS\n"), 1;
	if (sched_setscheduler(0, SCHED_FIFO, &sp))
		perror("SCHED_FIFO");
	prctl(PR_SET_TIMERSLACK, 1);
	clock_gettime(CLOCK_MONOTONIC, &t);
	srand(t.tv_nsec);
	end = t.tv_sec + atol(argv[1]);
	while (t.tv_sec < end) {
		usage(a);
		clock_gettime(CLOCK_MONOTONIC, &t);
		t.tv_nsec += 200000000 + rand() % 800000000;
		t.tv_sec += t.tv_nsec / 1000000000;
		t.tv_nsec %= 1000000000;
		clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &t, NULL);
		clock_gettime(CLOCK_MONOTONIC, &w);
		usage(b);
		printf("%ld", (w.tv_sec - t.tv_sec) * 1000000 + (w.tv_nsec - t.tv_nsec) / 1000);
		for (i = 0; i < NS; i++)
			printf(" %ld", b[i] - a[i]);
		printf("\n");
		fflush(stdout);
	}
	return 0;
}
