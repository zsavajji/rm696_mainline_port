/*
 * tlbbench: what a TLB miss costs (the Cortex-A8 has 32-entry I and D TLBs): read one word in each of
 * N pages, round after round. Up to ~32 pages every access hits the TLB; past it each one walks the
 * page tables, and the jump is the walk's cost. Each page's word is on its own cache line, so the
 * data stays in the caches. Same binary on stock and the test kernel, as any user, CPU pinned.
 */
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

int main(void)
{
	static const int sizes[] = { 8, 16, 24, 32, 40, 48, 64, 96, 128, 256 };
	const int pages = 256, accesses = 4 << 20;
	volatile unsigned int *p = mmap(NULL, pages * 4096, PROT_READ | PROT_WRITE,
					MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	unsigned int sum = 0;
	int s, i, k;

	if (p == MAP_FAILED)
		return 1;
	for (i = 0; i < pages; i++)
		p[i * 1024 + (i * 16) % 1024] = i;	/* fault them in; line i % 64 of each page */
	for (s = 0; s < (int)(sizeof(sizes) / sizeof(sizes[0])); s++) {
		int n = sizes[s];
		double t = now();

		for (k = 0; k < accesses / n; k++)
			for (i = 0; i < n; i++)
				sum += p[i * 1024 + (i * 16) % 1024];
		printf("%4d pages %6.2f ns/access\n", n, (now() - t) / (accesses / n * n) * 1e9);
	}
	return sum == 1;
}
