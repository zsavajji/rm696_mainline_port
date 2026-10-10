/*
 * kbench: kernel basics to compare stock Harmattan and the test kernel on the same phone: a syscall
 * (getppid), sched_yield, a pipe without switching, context switches between threads and processes
 * (pipe ping-pong), a page fault on fresh anonymous memory (touch one byte per page, zero-fill included),
 * a file-backed fault (a library in the page cache), fork+exec+exit, memset and memcpy bandwidth. Run with the CPU at a fixed frequency for comparable numbers:
 * kbench [CGROUP_TASKS_FILE] (it prints the cgroup it ran in; ohmd moves new processes).
 */
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <pthread.h>
#include <sched.h>
#include <sys/wait.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static int tp[4];

static void print_cgroup(const char *when)
{
	char l[256];
	FILE *f = fopen("/proc/self/cgroup", "r");

	while (f && fgets(l, sizeof(l), f))
		if (strstr(l, "cpu"))	/* "cpu,cpuacct,..." here, "freezer,memory,cpu" on stock */
			printf("cgroup    %s %s", when, strchr(strchr(l, ':') + 1, ':') + 1);
	if (f)
		fclose(f);
	fflush(stdout);
}

static void *pong(void *x)
{
	char c;

	while (read(tp[0], &c, 1) == 1 && write(tp[3], &c, 1) == 1)
		;
	return NULL;
}

int main(int argc, char **argv)
{
	const size_t sz = 64 << 20, bw = 16 << 20;
	volatile char *p;
	char *a, *b;
	double t;
	size_t i;
	int r;

	int ab[2], ba[2];
	char c = 0;

	/*
	 * Where Harmattan's policy (ohmd) put us: it moves new processes into its cgroups. With an
	 * argument (a cgroup's tasks file) we move ourselves there after it, to compare cgroup depths
	 */
	usleep(100000);
	if (argc > 1) {
		FILE *f = fopen(argv[1], "w");

		if (!f || fprintf(f, "%d\n", getpid()) < 0 || fclose(f))
			return perror(argv[1]), 1;
	}
	print_cgroup("start");
	t = now();
	for (i = 0; i < 200000; i++)
		getppid();
	printf("syscall   %6.2f us\n", (now() - t) / 200000 * 1e6);

	/* a syscall that reads the clocksource (the 32k counter on both kernels, also sched_clock's) */
	t = now();
	for (i = 0; i < 100000; i++)
		now();
	printf("gettime   %6.2f us\n", (now() - t) / 100000 * 1e6);

	t = now();
	for (i = 0; i < 200000; i++)
		sched_yield();
	printf("yield     %6.2f us\n", (now() - t) / 200000 * 1e6);

	/* a pipe write and read in one process: the pipe's cost without a switch */
	if (pipe(ab))
		return 1;
	t = now();
	for (i = 0; i < 100000; i++)
		if (write(ab[1], &c, 1) != 1 || read(ab[0], &c, 1) != 1)
			break;
	printf("pipe      %6.2f us\n", (now() - t) / 100000 * 1e6);
	close(ab[0]);
	close(ab[1]);

	/* two threads ping-ponging: switches without an address space change */
	{
		pthread_t th;

		if (pipe(tp) || pipe(tp + 2) || pthread_create(&th, NULL, pong, NULL))
			return 1;
		t = now();
		for (i = 0; i < 20000; i++)
			if (write(tp[1], &c, 1) != 1 || read(tp[2], &c, 1) != 1)
				break;
		printf("threadsw  %6.2f us\n", (now() - t) / 20000 / 2 * 1e6);
		close(tp[1]);
	}

	/* two processes ping-ponging a byte through pipes: two context switches a round */
	if (pipe(ab) || pipe(ba))
		return 1;
	fflush(stdout);	/* else the child prints our buffer again */
	if (!fork()) {
		/* only its own ends: EOF when the parent is done, else it outlives it holding stdout */
		close(ab[1]);
		close(ba[0]);
		print_cgroup("child");
		while (read(ab[0], &c, 1) == 1 && write(ba[1], &c, 1) == 1)
			;
		_exit(0);
	}
	t = now();
	for (i = 0; i < 20000; i++)
		if (write(ab[1], &c, 1) != 1 || read(ba[0], &c, 1) != 1)
			break;
	printf("ctxswitch %6.2f us\n", (now() - t) / 20000 / 2 * 1e6);
	close(ab[1]);
	wait(NULL);

	for (r = 0; r < 3; r++) {
		p = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		t = now();
		for (i = 0; i < sz; i += 4096)
			p[i] = 1;
		printf("pagefault %6.2f us\n", (now() - t) / (sz / 4096) * 1e6);
		munmap((void *)p, sz);
	}

	/* a file-backed fault, as starting an app takes: a big library in the page cache, a read a page */
	r = open("/usr/lib/libQtGui.so.4", O_RDONLY);
	if (r >= 0) {
		struct stat st;
		int k;

		fstat(r, &st);
		for (k = 0; k < 2; k++) {	/* the first one may still read the file */
			volatile char *q = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, r, 0);

			t = now();
			for (i = 0; i < (size_t)st.st_size; i += 4096)
				c += q[i];
			printf("filefault %6.2f us\n", (now() - t) / (st.st_size / 4096) * 1e6);
			munmap((void *)q, st.st_size);
		}
		close(r);
	}

	/* process creation: fork, exec /bin/true, exit, wait */
	t = now();
	for (i = 0; i < 200; i++) {
		pid_t pid = fork();

		if (!pid) {
			execl("/bin/true", "true", (char *)NULL);
			_exit(1);
		}
		waitpid(pid, NULL, 0);
	}
	printf("spawn     %6.0f us\n", (now() - t) / 200 * 1e6);

	a = mmap(NULL, bw, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	b = mmap(NULL, bw, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	memset(a, 1, bw);
	memset(b, 2, bw);
	t = now();
	for (r = 0; r < 8; r++) {
		memset(a, r, bw);
		asm volatile("" : : "r"(a) : "memory");	/* each pass is a real one */
	}
	printf("memset    %6.0f MB/s\n", 8 * (bw >> 20) / (now() - t));
	t = now();
	for (r = 0; r < 8; r++) {
		memcpy(b, a, bw);
		asm volatile("" : : "r"(b) : "memory");
	}
	printf("memcpy    %6.0f MB/s\n", 8 * (bw >> 20) / (now() - t));
	print_cgroup("end");
	return a[bw / 2] + b[bw / 3] == 255;	/* keep the buffers observable */
}
