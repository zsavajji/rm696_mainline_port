/*
 * mmiolat: what one read of a device register costs, per interconnect, from user space through
 * /dev/mem (root, test kernel). Only modules whose clocks are on: reading a gated one aborts.
 * mmiolat [ADDR...]: 10000 reads each, ns per read.
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1e9 + t.tv_nsec;
}

int main(int argc, char **argv)
{
	int fd = open("/dev/mem", O_RDONLY | O_SYNC), i, a;

	if (fd < 0)
		return perror("/dev/mem"), 1;
	for (a = 1; a < argc; a++) {
		unsigned long addr = strtoul(argv[a], NULL, 0);
		volatile uint32_t *p = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, addr & ~4095UL);
		uint32_t v = 0;
		double t;

		if (p == MAP_FAILED)
			return perror("mmap"), 1;
		p += (addr & 4095) / 4;
		t = now();
		for (i = 0; i < 10000; i++)
			v += *p;
		printf("0x%08lx: %6.0f ns per read (%08x)\n", addr, (now() - t) / 10000, (unsigned)*p);
	}
	return 0;
}
