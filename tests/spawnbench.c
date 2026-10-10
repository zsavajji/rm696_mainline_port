/*
 * spawnbench: where a process start goes, by phase, the same on stock and the test kernel (as user):
 * fork+exit, fork+exec+exit of a tiny static program (tinyexit: the kernel's exec alone) and of
 * /bin/true (dynamic: ld.so and libc too), vfork+exec (no address space copy), fork from a parent with
 * a large heap, the page faults per spawn (/proc/vmstat), and what Harmattan's ohmd does for each new
 * process: readlink /proc/<new pid>/exe. spawnbench [TINYEXIT_PATH] [ROUNDS] [PHASE: 0-7, default all]
 * Phase 7 replays ohmd's kernel work for each new process from the spawner (run as root, ohmd stopped):
 * SPAWNBENCH_PROC=1 readlink /proc/<pid>/exe and read its stat twice, SPAWNBENCH_CG=<tasks file> move it.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/times.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static long vmstat(const char *key)
{
	char name[64];
	long v, r = -1;
	FILE *f = fopen("/proc/vmstat", "r");

	while (f && fscanf(f, "%63s %ld", name, &v) == 2)
		if (!strcmp(name, key))
			r = v;
	if (f)
		fclose(f);
	return r;
}

static const char *prog;

static void child(int mode)
{
	if (mode == 0)
		_exit(0);
	execl(prog, prog, (char *)NULL);
	_exit(1);
}

static const char *cg;
static int procwork;
static double opt[6];	/* readlink, open, read, close (both stats), tasks write, its open+close */
static const char *opname[6] = { "readlink exe", "open stat", "read stat", "close stat", "cgroup write", "cgroup open+close" };

#define TIMED(i, call) do { double _t = now(); call; opt[i] += now() - _t; } while (0)

/* what Harmattan's ohmd does on a new process's exec event (from a trace of its system calls) */
static void ohmd_work(pid_t pid)
{
	char path[64], buf[512];
	int fd, k;

	if (procwork) {
		snprintf(path, sizeof(path), "/proc/%d/exe", pid);
		TIMED(0, readlink(path, buf, sizeof(buf)));
		for (k = 0; k < 2; k++) {
			snprintf(path, sizeof(path), "/proc/%d/stat", pid);
			TIMED(1, fd = open(path, O_RDONLY));
			if (fd >= 0) {
				TIMED(2, read(fd, buf, sizeof(buf)));
				TIMED(3, close(fd));
			}
		}
	}
	if (cg) {
		TIMED(5, fd = open(cg, O_WRONLY));
		if (fd >= 0) {
			k = snprintf(buf, sizeof(buf), "%d", pid);
			TIMED(4, write(fd, buf, k));
			TIMED(5, close(fd));
		}
	}
}

static void run(const char *what, int mode, int use_vfork, int n)
{
	long f0 = vmstat("pgfault"), a0 = vmstat("pgalloc_normal"), hz = sysconf(_SC_CLK_TCK);
	struct tms m0, m1;
	double t;
	int i;

	times(&m0);
	t = now();

	for (i = 0; i < n; i++) {
		pid_t pid = use_vfork ? vfork() : fork();

		if (!pid)
			child(mode);
		if (mode == 2)
			ohmd_work(pid);
		waitpid(pid, NULL, 0);
	}
	t = now() - t;
	times(&m1);
	/* tick-sampled: the children's user (ld.so, libc init) and system time, the parent's (fork, wait) */
	printf("%-30s %6.0f us   %5.1f faults %5.1f pages/spawn   child user %4.0f sys %4.0f, parent user %3.0f sys %4.0f us\n",
	       what, t / n * 1e6, (double)(vmstat("pgfault") - f0) / n, (double)(vmstat("pgalloc_normal") - a0) / n,
	       (m1.tms_cutime - m0.tms_cutime) * 1e6 / hz / n, (m1.tms_cstime - m0.tms_cstime) * 1e6 / hz / n,
	       (m1.tms_utime - m0.tms_utime) * 1e6 / hz / n, (m1.tms_stime - m0.tms_stime) * 1e6 / hz / n);
}

/* ohmd's lookup of a process it hasn't seen: /proc/<pid> and its exe are new dentries and inodes */
static void readlink_new(int n)
{
	double t = 0, t0;
	char path[32], buf[256];
	int i, p[2];

	for (i = 0; i < n; i++) {
		pid_t pid;

		if (pipe(p))
			return;
		pid = fork();
		if (!pid) {
			close(p[1]);
			read(p[0], buf, 1);	/* until the parent closes its end */
			_exit(0);
		}
		close(p[0]);
		snprintf(path, sizeof(path), "/proc/%d/exe", pid);
		t0 = now();
		if (readlink(path, buf, sizeof(buf)) < 0)
			perror(path);
		t += now() - t0;
		close(p[1]);
		waitpid(pid, NULL, 0);
	}
	printf("%-30s %6.1f us\n", "readlink /proc/<new pid>/exe", t / n * 1e6);
}

int main(int argc, char **argv)
{
	const char *tiny = argc > 1 ? argv[1] : "/tmp/tinyexit";
	int n = argc > 2 ? atoi(argv[2]) : 300, ph = argc > 3 ? atoi(argv[3]) : -1;
	char *heap;

	if (getenv("SPAWNBENCH_MAPS")) {	/* to place fault addresses from a trace */
		char cmd[48];

		snprintf(cmd, sizeof(cmd), "cat /proc/%d/maps >&2", getpid());
		system(cmd);
	}
	if (ph < 0 || ph == 0)
		run("fork+exit", 0, 0, n);
	prog = tiny;
	if (ph < 0 || ph == 1)
		run("fork+exec tinyexit", 1, 0, n);
	if (ph < 0 || ph == 2)
		run("vfork+exec tinyexit", 1, 1, n);
	prog = "/bin/true";
	if (ph < 0 || ph == 3)
		run("fork+exec /bin/true", 1, 0, n);
	if (ph < 0 || ph == 4)
		run("vfork+exec /bin/true", 1, 1, n);
	if (ph < 0 || ph == 5) {
		heap = malloc(8 << 20);
		memset(heap, 1, 8 << 20);	/* 2048 pages to copy-on-write */
		run("fork+exit, 8 MiB heap", 0, 0, ph < 0 ? n / 3 : n);
		free(heap);
	}
	if (ph < 0 || ph == 6)
		readlink_new(n);
	cg = getenv("SPAWNBENCH_CG");
	procwork = getenv("SPAWNBENCH_PROC") != NULL;
	prog = tiny;
	if (ph == 7) {
		int i;

		run("vfork+exec tinyexit + ohmd's work", 2, 1, n);
		for (i = 0; i < 6; i++)
			if (opt[i] > 0)
				printf("  %-18s %6.1f us a spawn\n", opname[i], opt[i] / n * 1e6);
	}
	return 0;
}
