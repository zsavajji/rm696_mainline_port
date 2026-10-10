/*
 * migbench: the cost of a cgroup (v1) migration as Harmattan's ohmd does them: a runnable process
 * moved by writing its pid to a tasks file, back and forth between two cgroups (as root).
 * migbench TASKS_A TASKS_B [ROUNDS] [sleep]: with "sleep" the moved process sleeps instead of spinning.
 */
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	int n = argc > 3 ? atoi(argv[3]) : 2000, i, fd[2], len;
	pid_t pid = fork();
	char buf[16];
	double t;

	if (!pid) {
		if (argc > 4)
			for (;;)
				pause();
		for (;;)
			;
	}
	fd[0] = open(argv[1], O_WRONLY);
	fd[1] = open(argv[2], O_WRONLY);
	if (fd[0] < 0 || fd[1] < 0)
		return perror("tasks"), kill(pid, SIGKILL), 1;
	len = snprintf(buf, sizeof(buf), "%d", pid);
	t = now();
	for (i = 0; i < n; i++)
		if (write(fd[i & 1], buf, len) != len)
			return perror("write"), kill(pid, SIGKILL), 1;
	t = now() - t;
	printf("migration (%s target) %6.1f us\n", argc > 4 ? "sleeping" : "runnable", t / n * 1e6);
	kill(pid, SIGKILL);
	return 0;
}
