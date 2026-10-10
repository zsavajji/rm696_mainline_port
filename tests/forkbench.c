/*
 * forkbench: the pieces of a process start, each alone, to compare kernels primitive by primitive (as
 * user, same binary on stock and the test kernel; build it static too for a parent with few VMAs):
 * fork+exit, its cost per extra VMA, a copy-on-write fault, the minor fault that marks a page young
 * after fork (ARM has no hardware access flag), mmap+munmap of a file, a fault-around fault, a fork of
 * a process shaped like Harmattan's app boosters (~600 VMAs, file and anonymous), and system calls
 * ohmd and ld.so make (path walks, /proc/<pid>/stat, mprotect).
 * forkbench [ROUNDS]
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static double forkexit(int n)
{
	double t = now();
	int i;

	for (i = 0; i < n; i++) {
		pid_t p = fork();

		if (!p)
			_exit(0);
		waitpid(p, NULL, 0);
	}
	return (now() - t) / n * 1e6;
}

/* the child touches PAGES pages of BUF (write: copy-on-write; read: young-bit faults), times it */
static double child_touch(char *buf, int pages, int wr, int n)
{
	double sum = 0;
	int i, p[2];

	for (i = 0; i < n; i++) {
		double t;

		if (pipe(p))
			return -1;
		if (!fork()) {
			volatile char *b = buf;
			int k;
			char c = 0;

			t = now();
			for (k = 0; k < pages; k++)
				if (wr)
					b[k * 4096] = 1;
				else
					c += b[k * 4096];
			t = now() - t + c * 0;
			write(p[1], &t, sizeof(t));
			_exit(0);
		}
		read(p[0], &t, sizeof(t));
		close(p[0]);
		close(p[1]);
		wait(NULL);
		sum += t;
	}
	return sum / n / pages * 1e6;
}

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 300, i, fd;
	char *buf = malloc(256 * 4096 + 4096), *b;
	double t, base;
	char **vmas;

	buf = (char *)(((unsigned long)buf + 4095) & ~4095UL);
	memset(buf, 1, 256 * 4096);
	printf("fork+exit                  %7.1f us\n", base = forkexit(n));
	printf("copy-on-write fault        %7.2f us a page (child writes 256)\n", child_touch(buf, 256, 1, n / 10));
	printf("young-bit fault after fork %7.2f us a page (child reads 256)\n", child_touch(buf, 256, 0, n / 10));

	/* 200 extra one-page VMAs, alternating protections so none merge, each touched once */
	vmas = malloc(200 * sizeof(*vmas));
	for (i = 0; i < 200; i++) {
		vmas[i] = mmap(NULL, 4096, i & 1 ? PROT_READ | PROT_WRITE : PROT_READ | PROT_WRITE | PROT_EXEC,
			       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		vmas[i][0] = 1;
	}
	t = forkexit(n);
	printf("fork+exit, +200 VMAs       %7.1f us: %.2f us a VMA\n", t, (t - base) / 200);
	for (i = 0; i < 200; i++)
		munmap(vmas[i], 4096);

	fd = open("/lib/libc.so.6", O_RDONLY);
	if (fd >= 0) {
		t = now();
		for (i = 0; i < n * 10; i++)
			munmap(mmap(NULL, 65536, PROT_READ, MAP_PRIVATE, fd, 0), 65536);
		printf("mmap+munmap of a file      %7.2f us\n", (now() - t) / (n * 10) * 1e6);
		t = now();
		for (i = 0; i < n * 10; i++) {
			b = mmap(NULL, 65536, PROT_READ, MAP_PRIVATE, fd, 0);
			(void)*(volatile char *)b;
			munmap(b, 65536);
		}
		printf("  the same + one read fault %7.2f us\n", (now() - t) / (n * 10) * 1e6);
		t = now();
		for (i = 0; i < n * 10; i++) {
			int k;

			b = mmap(NULL, 65536, PROT_READ, MAP_PRIVATE, fd, 0);
			for (k = 0; k < 16; k++)
				(void)*(volatile char *)(b + k * 4096);
			munmap(b, 65536);
		}
		printf("  the same, 16 pages read  %7.2f us\n", (now() - t) / (n * 10) * 1e6);
		close(fd);
	}
	t = now();
	for (i = 0; i < n * 10; i++) {
		b = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		b[0] = 1;
		munmap(b, 4096);
	}
	printf("anon mmap+fault+munmap     %7.2f us\n", (now() - t) / (n * 10) * 1e6);

	/* system calls (each n*10 times) */
	{
		char path[64], buf[1024];
		struct stat st;
		int m = n * 10;

		t = now();
		for (i = 0; i < m; i++)
			stat("/usr/lib/libQtGui.so.4", &st);
		printf("stat /usr/lib/libQtGui.so.4 %6.2f us\n", (now() - t) / m * 1e6);
		t = now();
		for (i = 0; i < m; i++)
			close(open("/lib/libc.so.6", O_RDONLY));
		printf("open+close /lib/libc.so.6  %7.2f us\n", (now() - t) / m * 1e6);
		t = now();
		for (i = 0; i < m; i++)
			readlink("/proc/self/exe", buf, sizeof(buf));
		printf("readlink /proc/self/exe    %7.2f us\n", (now() - t) / m * 1e6);
		snprintf(path, sizeof(path), "/proc/%d/stat", getpid());
		t = now();
		for (i = 0; i < m; i++) {
			fd = open(path, O_RDONLY);
			read(fd, buf, sizeof(buf));
			close(fd);
		}
		printf("open+read+close own stat   %7.2f us\n", (now() - t) / m * 1e6);
		fd = open(path, O_RDONLY);
		t = now();
		for (i = 0; i < m; i++)
			pread(fd, buf, sizeof(buf), 0);
		printf("pread own /proc stat       %7.2f us\n", (now() - t) / m * 1e6);
		close(fd);
		b = mmap(NULL, 65536, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		t = now();
		for (i = 0; i < m; i++) {
			mprotect(b + 32768, 32768, PROT_READ);
			mprotect(b + 32768, 32768, PROT_READ | PROT_WRITE);
		}
		printf("mprotect split+merge       %7.2f us\n", (now() - t) / m / 2 * 1e6);
		munmap(b, 65536);
	}

	/* a booster-like parent: 190 file mappings (code of libraries), 400 anonymous ones, all touched */
	{
		int fds[3] = { open("/lib/libc.so.6", O_RDONLY), open("/usr/lib/libQtGui.so.4", O_RDONLY),
			       open("/usr/lib/libQtCore.so.4", O_RDONLY) };

		for (i = 0; i < 190; i++) {
			b = mmap(NULL, 4096, PROT_READ | (i & 1 ? 0 : PROT_EXEC), MAP_PRIVATE, fds[i % 3], (off_t)(i / 3) * 4096);
			if (b != MAP_FAILED)
				(void)*(volatile char *)b;
		}
		for (i = 0; i < 400; i++) {
			b = mmap(NULL, 4096, i & 1 ? PROT_READ | PROT_WRITE : PROT_READ | PROT_WRITE | PROT_EXEC,
				 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
			b[0] = 1;
		}
		t = forkexit(n / 3);
		printf("fork+exit, booster-like    %7.1f us (+190 file, +400 anon VMAs)\n", t);
	}
	return 0;
}
