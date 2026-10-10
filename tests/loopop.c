/*
 * loopop: one system call pattern in a loop, to profile it (kprof) and time it:
 * loopop MODE SECONDS, MODE one of mmap (file mmap+munmap, PROT_READ), mmapx (the same, PROT_EXEC),
 * anon (anonymous mmap+write+munmap), open (open+close /lib/libc.so.6), stat (/usr/lib/libQtGui.so.4),
 * mprotect (split and merge), fork200 (fork+exit with 200 extra anonymous VMAs), split (file mmap and
 * munmap timed apart, clock_gettime's own cost taken off), amap (anonymous mmap+munmap, no fault),
 * fixed / afixed (file / anonymous mmap at a fixed free address + munmap), unmap0 (munmap of nothing),
 * mmaponly (file mmap with MAP_FIXED over the same mapping: no munmap). LOOPOP_FILE and
 * LOOPOP_STAT change the file mapped/opened and the path stat'ed.
 */
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

int main(int argc, char **argv)
{
	const char *m = argc > 1 ? argv[1] : "mmap";
	double secs = argc > 2 ? atof(argv[2]) : 5, t0 = now();
	const char *file = getenv("LOOPOP_FILE") ? getenv("LOOPOP_FILE") : "/lib/libc.so.6";
	const char *spath = getenv("LOOPOP_STAT") ? getenv("LOOPOP_STAT") : "/usr/lib/libQtGui.so.4";
	int fd = open(file, O_RDONLY), i;
	long n = 0;
	struct stat st;
	char *b = mmap(NULL, 65536, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

	if (!strcmp(m, "fork200"))
		for (i = 0; i < 200; i++) {
			char *v = mmap(NULL, 4096, i & 1 ? PROT_READ | PROT_WRITE : PROT_READ | PROT_WRITE | PROT_EXEC,
				       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
			v[0] = 1;
		}
	char *fx = mmap(NULL, 65536, PROT_READ, MAP_PRIVATE, fd, 0);

	munmap(fx, 65536);
	if (!strcmp(m, "mmaponly"))
		mmap(fx, 65536, PROT_READ, MAP_PRIVATE, fd, 0);
	if (!strcmp(m, "split")) {
		double tm = 0, tu = 0, tc = 0, a, c;
		void *v;

		for (n = 0; now() - t0 < secs; n++) {
			a = now();
			c = now();
			tc += c - a;
			v = mmap(NULL, 65536, PROT_READ, MAP_PRIVATE, fd, 0);
			a = now();
			tm += a - c;
			munmap(v, 65536);
			tu += now() - a;
		}
		printf("mmap %.2f us, munmap %.2f us (clock_gettime %.2f us taken off)\n",
		       (tm - tc) / n * 1e6, (tu - tc) / n * 1e6, tc / n * 1e6);
		return 0;
	}
	while (now() - t0 < secs) {
		for (i = 0; i < 100; i++, n++) {
			if (!strcmp(m, "mmap"))
				munmap(mmap(NULL, 65536, PROT_READ, MAP_PRIVATE, fd, 0), 65536);
			else if (!strcmp(m, "amap"))
				munmap(mmap(NULL, 65536, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0), 65536);
			else if (!strcmp(m, "fixed"))
				munmap(mmap(fx, 65536, PROT_READ, MAP_PRIVATE | MAP_FIXED, fd, 0), 65536);
			else if (!strcmp(m, "afixed"))
				munmap(mmap(fx, 65536, PROT_READ, MAP_PRIVATE | MAP_FIXED | MAP_ANONYMOUS, -1, 0), 65536);
			else if (!strcmp(m, "unmap0"))
				munmap(fx, 65536);
			else if (!strcmp(m, "mmaponly"))
				mmap(fx, 65536, PROT_READ, MAP_PRIVATE | MAP_FIXED, fd, 0);
			else if (!strcmp(m, "mmapx"))
				munmap(mmap(NULL, 65536, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0), 65536);
			else if (!strcmp(m, "anon")) {
				char *a = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

				a[0] = 1;
				munmap(a, 4096);
			} else if (!strcmp(m, "open"))
				close(open(file, O_RDONLY));
			else if (!strcmp(m, "stat"))
				stat(spath, &st);
			else if (!strcmp(m, "mprotect")) {
				mprotect(b + 32768, 32768, PROT_READ);
				mprotect(b + 32768, 32768, PROT_READ | PROT_WRITE);
			} else if (!strcmp(m, "fork200")) {
				pid_t p = fork();

				if (!p)
					_exit(0);
				waitpid(p, NULL, 0);
				if (i == 9) {	/* forks are slow: 10 a round */
					n++;
					break;
				}
			}
		}
	}
	printf("%s: %.2f us each\n", m, (now() - t0) / n * 1e6);
	return 0;
}
