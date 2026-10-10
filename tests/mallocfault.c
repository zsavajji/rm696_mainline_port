/* mallocfault: glibc's large-chunk reuse under this kernel: N malloc+memset+free of SIZE bytes per
 * round, ROUNDS rounds; page faults and time. mallocfault [N=8] [SIZE=262144] [ROUNDS=300] [mmap] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 8, rounds = argc > 3 ? atoi(argv[3]) : 300, r, i;
	size_t size = argc > 2 ? atoi(argv[2]) : 262144;
	int use_mmap = argc > 4;
	void *(*volatile vmemset)(void *, int, size_t) = memset;	/* not optimized away */
	struct rusage r0, r1;
	struct timespec t0, t1;

	getrusage(RUSAGE_SELF, &r0);
	clock_gettime(CLOCK_MONOTONIC, &t0);
	for (r = 0; r < rounds; r++)
		for (i = 0; i < n; i++) {
			char *p = use_mmap ? mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)
					   : malloc(size);

			vmemset(p, r + i, size);
			if (use_mmap)
				munmap(p, size);
			else
				free(p);
		}
	clock_gettime(CLOCK_MONOTONIC, &t1);
	getrusage(RUSAGE_SELF, &r1);
	printf("mallocfault %s %d x %zu x %d: %.3f s, faults %ld (%.1f a round), sys %.3f s user %.3f s\n",
	       use_mmap ? "mmap" : "malloc", n, size, rounds,
	       t1.tv_sec - t0.tv_sec + (t1.tv_nsec - t0.tv_nsec) * 1e-9, r1.ru_minflt - r0.ru_minflt,
	       (double)(r1.ru_minflt - r0.ru_minflt) / rounds,
	       r1.ru_stime.tv_sec - r0.ru_stime.tv_sec + (r1.ru_stime.tv_usec - r0.ru_stime.tv_usec) * 1e-6,
	       r1.ru_utime.tv_sec - r0.ru_utime.tv_sec + (r1.ru_utime.tv_usec - r0.ru_utime.tv_usec) * 1e-6);
	return 0;
}
