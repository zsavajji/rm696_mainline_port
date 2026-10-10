/*
 * copypage: 4 KiB page copies the way a copy-on-write fault does them (a source the process touched
 * recently, a destination page fresh from the allocator), with the kernel's arch/arm/lib/copy_page.S
 * loop and NEON variants, to pick the fastest for the Cortex-A8. copypage [ROUNDS]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

#define PAGE 4096
#define NPAGES 2048	/* 8 MiB each side: well past the 256 KiB L2 */

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

/* arch/arm/lib/copy_page.S as built for the N9 (L1_CACHE_BYTES 64, PLD 2-3 lines ahead) */
void copy_page_kernel(void *to, const void *from);
asm(".text\n.arm\n.globl copy_page_kernel\ncopy_page_kernel:\n"
    "	stmfd	sp!, {r4, lr}\n"
    "	pld	[r1, #0]\n"
    "	pld	[r1, #64]\n"
    "	mov	r2, #(4096 / 128 - 1)\n"
    "	ldmia	r1!, {r3, r4, ip, lr}\n"
    "1:	pld	[r1, #128]\n"
    "	pld	[r1, #192]\n"
    "2:\n"
    "	.rept	7\n"
    "	stmia	r0!, {r3, r4, ip, lr}\n"
    "	ldmia	r1!, {r3, r4, ip, lr}\n"
    "	.endr\n"
    "	subs	r2, r2, #1\n"
    "	stmia	r0!, {r3, r4, ip, lr}\n"
    "	ldmiagt	r1!, {r3, r4, ip, lr}\n"
    "	bgt	1b\n"
    "	ldmiaeq	r1!, {r3, r4, ip, lr}\n"
    "	beq	2b\n"
    "	ldmfd	sp!, {r4, pc}\n");

/* NEON, 64 bytes an iteration, PLD 4 lines ahead */
void copy_page_neon(void *to, const void *from);
asm(".text\n.arm\n.fpu neon\n.globl copy_page_neon\ncopy_page_neon:\n"
    "	pld	[r1, #0]\n"
    "	pld	[r1, #64]\n"
    "	pld	[r1, #128]\n"
    "	pld	[r1, #192]\n"
    "	mov	r2, #64\n"
    "1:	pld	[r1, #256]\n"
    "	vld1.8	{d0-d3}, [r1]!\n"
    "	vld1.8	{d4-d7}, [r1]!\n"
    "	subs	r2, r2, #1\n"
    "	vst1.8	{d0-d3}, [r0]!\n"
    "	vst1.8	{d4-d7}, [r0]!\n"
    "	bgt	1b\n"
    "	bx	lr\n");

/* NEON with aligned hints, 128 bytes an iteration, PLD 5 lines ahead */
void copy_page_neon128(void *to, const void *from);
asm(".text\n.arm\n.fpu neon\n.globl copy_page_neon128\ncopy_page_neon128:\n"
    "	vpush	{d8-d15}\n"
    "	pld	[r1, #0]\n"
    "	pld	[r1, #64]\n"
    "	pld	[r1, #128]\n"
    "	pld	[r1, #192]\n"
    "	pld	[r1, #256]\n"
    "	mov	r2, #32\n"
    "1:	pld	[r1, #320]\n"
    "	pld	[r1, #384]\n"
    "	vld1.64	{d0-d3}, [r1:128]!\n"
    "	vld1.64	{d4-d7}, [r1:128]!\n"
    "	vld1.64	{d8-d11}, [r1:128]!\n"
    "	vld1.64	{d12-d15}, [r1:128]!\n"
    "	subs	r2, r2, #1\n"
    "	vst1.64	{d0-d3}, [r0:128]!\n"
    "	vst1.64	{d4-d7}, [r0:128]!\n"
    "	vst1.64	{d8-d11}, [r0:128]!\n"
    "	vst1.64	{d12-d15}, [r0:128]!\n"
    "	bgt	1b\n"
    "	vpop	{d8-d15}\n"
    "	bx	lr\n");

/* ldm/stm 32 bytes at a time with PLD 4-5 lines ahead */
void copy_page_ldm8(void *to, const void *from);
asm(".text\n.arm\n.globl copy_page_ldm8\ncopy_page_ldm8:\n"
    "	stmfd	sp!, {r4-r10, lr}\n"
    "	pld	[r1, #0]\n"
    "	pld	[r1, #64]\n"
    "	pld	[r1, #128]\n"
    "	pld	[r1, #192]\n"
    "	mov	r2, #64\n"
    "1:	pld	[r1, #256]\n"
    "	ldmia	r1!, {r3-r10}\n"
    "	stmia	r0!, {r3-r10}\n"
    "	ldmia	r1!, {r3-r10}\n"
    "	subs	r2, r2, #1\n"
    "	stmia	r0!, {r3-r10}\n"
    "	bgt	1b\n"
    "	ldmfd	sp!, {r4-r10, pc}\n");

static void memcpy_page(void *to, const void *from) { memcpy(to, from, PAGE); }

static char *src, *dst;

static double bench(void (*fn)(void *, const void *), int hot, int rounds)
{
	double t = 0, t0;
	volatile char sink = 0;
	int r, i, j;

	for (r = 0; r < rounds; r++)
		for (i = 0; i < NPAGES; i++) {
			char *s = src + (size_t)i * PAGE, *d = dst + (size_t)((i * 977) % NPAGES) * PAGE;

			if (hot)	/* the process just used its page: in L1/L2 */
				for (j = 0; j < PAGE; j += 64)
					sink += s[j];
			t0 = now();
			fn(d, s);
			t += now() - t0;
		}
	return t / ((double)rounds * NPAGES) * 1e6;
}

int main(int argc, char **argv)
{
	int rounds = argc > 1 ? atoi(argv[1]) : 3, hot;
	struct { const char *name; void (*fn)(void *, const void *); } v[] = {
		{ "kernel copy_page.S", copy_page_kernel }, { "ldm/stm 32 B, pld +256", copy_page_ldm8 },
		{ "neon 64 B, pld +256", copy_page_neon }, { "neon 128 B, pld +384", copy_page_neon128 },
		{ "libc memcpy", memcpy_page },
	};
	size_t k;

	src = mmap(NULL, (size_t)NPAGES * PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	dst = mmap(NULL, (size_t)NPAGES * PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	memset(src, 1, (size_t)NPAGES * PAGE);
	memset(dst, 2, (size_t)NPAGES * PAGE);
	for (hot = 1; hot >= 0; hot--)
		for (k = 0; k < sizeof(v) / sizeof(v[0]); k++) {
			v[k].fn(dst, src);
			if (memcmp(dst, src, PAGE))
				return printf("%s: wrong copy\n", v[k].name), 1;
			printf("%-26s source %s  %5.2f us a page\n", v[k].name, hot ? "hot " : "cold",
			       bench(v[k].fn, hot, rounds));
		}
	return 0;
}
