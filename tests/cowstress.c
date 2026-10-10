/*
 * cowstress: rmap under memory pressure, for the anon_vma sharing at fork. A parent fills
 * MB megabytes with a pattern and forks CHILDREN; each child rewrites every other page with its
 * own pattern (copy-on-write) and, like the parent, checks every page in a loop while a hog
 * (HOG megabytes, touched over and over) pushes pages out to zram and back. Reclaim and
 * migration find each page's mappings through the anon_vmas: a missed mapping would show as a
 * wrong byte. cowstress [MB] [CHILDREN] [HOG] [SECONDS]; prints errors (0 expected) per process.
 */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define PG 4096

static unsigned char val(int who, long page, long off)
{
	return (unsigned char)(who * 131 + page * 7 + off);
}

static long check(unsigned char *m, long pages, int me, int child)
{
	long p, o, err = 0;

	for (p = 0; p < pages; p++) {
		int who = child && (p & 1) ? me : 0;

		for (o = 0; o < PG; o += 61)
			if (m[p * PG + o] != val(who, p, o))
				err++;
	}
	return err;
}

int main(int argc, char **argv)
{
	long mb = argc > 1 ? atol(argv[1]) : 64, hog = argc > 3 ? atol(argv[3]) : 256;
	int kids = argc > 2 ? atoi(argv[2]) : 4, secs = argc > 4 ? atoi(argv[4]) : 60, i;
	long pages = mb * 256, p, o, err = 0, rounds = 0;
	unsigned char *m = mmap(NULL, pages * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	pid_t pid[64], h;
	time_t end;

	if (m == MAP_FAILED)
		return perror("mmap"), 1;
	for (p = 0; p < pages; p++)
		for (o = 0; o < PG; o++)
			m[p * PG + o] = val(0, p, o);
	for (i = 0; i < kids; i++) {
		pid[i] = fork();
		if (!pid[i]) {
			int me = i + 1;

			for (p = 1; p < pages; p += 2)
				for (o = 0; o < PG; o++)
					m[p * PG + o] = val(me, p, o);
			for (end = time(NULL) + secs; time(NULL) < end; rounds++)
				err += check(m, pages, me, 1);
			printf("child %d: %ld errors in %ld rounds\n", me, err, rounds);
			fflush(stdout);
			_exit(err != 0);
		}
	}
	h = fork();
	if (!h) {	/* the hog: touch HOG MB over and over */
		unsigned char *b = mmap(NULL, hog << 20, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

		if (b == MAP_FAILED)
			_exit(2);
		for (;;)
			for (p = 0; p < (hog << 20); p += PG)
				b[p]++;
	}
	for (end = time(NULL) + secs; time(NULL) < end; rounds++)
		err += check(m, pages, 0, 0);
	printf("parent: %ld errors in %ld rounds\n", err, rounds);
	kill(h, SIGKILL);
	for (i = 0; i < kids; i++) {
		int st;

		waitpid(pid[i], &st, 0);
		if (!WIFEXITED(st) || WEXITSTATUS(st))
			err++;
	}
	waitpid(h, NULL, 0);
	printf("%s\n", err ? "FAIL" : "ok");
	return err != 0;
}
