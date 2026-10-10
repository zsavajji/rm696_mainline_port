/* membench: random dependent-load latency per working set, then 8 MB sequential read / write / copy
   bandwidth (best of 5). Static, runs as any user. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static double lat(int kb)
{
	size_t n = kb * 1024 / 64, j; void **m = aligned_alloc(64, n * 64), **p; size_t *o = malloc(n * sizeof(*o));
	for (j = 0; j < n; j++) o[j] = j;
	for (j = n - 1; j > 0; j--) { size_t r = rand() % (j + 1), t = o[j]; o[j] = o[r]; o[r] = t; }
	for (j = 0; j < n; j++) m[o[j] * 8] = &m[o[(j + 1) % n] * 8];
	long loads = 3000000; p = &m[o[0] * 8];
	for (j = 0; j < n; j++) p = *p;
	double t0 = now(); for (long k = 0; k < loads; k++) p = *p; double dt = now() - t0;
	free(m); free(o); return p ? dt * 1e9 / loads : 0;
}
int main(void)
{
	static const int kb[] = { 16, 128, 512, 2048, 8192, 32768 };
	for (unsigned i = 0; i < sizeof(kb) / sizeof(kb[0]); i++) printf("lat %5d KB: %6.1f ns\n", kb[i], lat(kb[i]));
	size_t sz = 8 << 20; unsigned *a = aligned_alloc(64, sz), *b = aligned_alloc(64, sz); memset(a, 1, sz); memset(b, 2, sz);
	double rd = 1e9, wr = 1e9, cp = 1e9; volatile unsigned sink = 0;
	for (int r = 0; r < 5; r++) {
		double t0 = now(); unsigned s0 = 0, s1 = 0, s2 = 0, s3 = 0;
		for (size_t j = 0; j < sz / 4; j += 4) { s0 += a[j]; s1 += a[j + 1]; s2 += a[j + 2]; s3 += a[j + 3]; }
		sink += s0 + s1 + s2 + s3; double t = now() - t0; if (t < rd) rd = t;
		t0 = now(); memset(b, r, sz); __asm__ volatile("" : : "r"(b) : "memory"); t = now() - t0; if (t < wr) wr = t;
		t0 = now(); memcpy(b, a, sz); __asm__ volatile("" : : "r"(b) : "memory"); t = now() - t0; if (t < cp) cp = t;
		sink += b[r * 1000];
	}
	printf("read %.0f MB/s, write %.0f MB/s, copy %.0f MB/s%s\n", sz / rd / 1e6, sz / wr / 1e6, sz / cp / 1e6, sink == 1 ? " " : "");
	return 0;
}
