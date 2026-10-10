/*
 * zerobench: how fast the Cortex-A8 zeroes 4 KiB pages it hasn't touched lately (as a page fault
 * does), by method: memset, an 8-register stm loop (as a kernel clear_page could), strd, NEON.
 * Cycles through 32 MiB so every page is cold. zerobench [ROUNDS]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define SZ (32 << 20)

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static void z_stm8(void *p)
{
	asm volatile(
	"	mov	r2, #0\n	mov	r3, #0\n	mov	r4, #0\n	mov	r5, #0\n"
	"	mov	r6, #0\n	mov	r7, #0\n	mov	r8, #0\n	mov	r9, #0\n"
	"	mov	r1, #64\n"
	"1:	stmia	%0!, {r2-r9}\n	stmia	%0!, {r2-r9}\n	subs	r1, r1, #1\n	bne	1b\n"
	: "+r" (p) : : "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9", "memory", "cc");
}

static void z_strd(void *p)
{
	asm volatile(
	"	mov	r2, #0\n	mov	r3, #0\n	mov	r1, #128\n"
	"1:	strd	r2, r3, [%0], #8\n	strd	r2, r3, [%0], #8\n"
	"	strd	r2, r3, [%0], #8\n	strd	r2, r3, [%0], #8\n	subs	r1, r1, #1\n	bne	1b\n"
	: "+r" (p) : : "r1", "r2", "r3", "memory", "cc");
}

static void z_neon(void *p)
{
	asm volatile(
	"	vmov.i8	q0, #0\n	vmov.i8	q1, #0\n	mov	r1, #64\n"
	"1:	vst1.64	{d0-d3}, [%0:128]!\n	vst1.64	{d0-d3}, [%0:128]!\n	subs	r1, r1, #1\n	bne	1b\n"
	: "+r" (p) : : "r1", "d0", "d1", "d2", "d3", "memory", "cc");
}

static void z_memset(void *p)
{
	memset(p, 0, 4096);
}

int main(int argc, char **argv)
{
	int rounds = argc > 1 ? atoi(argv[1]) : 3, r, m;
	char *buf;
	void (*f[])(void *) = { z_memset, z_stm8, z_strd, z_neon };
	const char *name[] = { "memset", "stm 8 regs", "strd", "NEON vst1" };

	if (posix_memalign((void **)&buf, 4096, SZ))
		return 1;
	memset(buf, 1, SZ);	/* faulted in */
	for (m = 0; m < 4; m++)
		for (r = 0; r < rounds; r++) {
			double t = now();
			size_t o;

			for (o = 0; o < SZ; o += 4096)
				f[m](buf + o);
			t = now() - t;
			printf("%-11s %5.0f MB/s, %.2f us per 4 KiB page\n", name[m], SZ / t / 1e6, t / (SZ / 4096) * 1e6);
		}
	return 0;
}
