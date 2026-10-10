/*
 * devmem: read or write a physical address on the phone (Harmattan's and the initramfs's busybox have
 * none). devmem ADDRESS [8|16|32 [VALUE]]; devmem ADDRESS dump LENGTH writes the raw bytes to stdout
 * (for no-map memory such as the DSP pool, which read() on /dev/mem refuses)
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	unsigned long addr, page = sysconf(_SC_PAGESIZE);
	int width = argc > 2 ? atoi(argv[2]) : 32, fd;
	volatile uint8_t *p;

	if (argc < 2)
		return fprintf(stderr, "usage: devmem ADDRESS [8|16|32 [VALUE]]\n"), 1;
	addr = strtoul(argv[1], NULL, 0);
	if (argc == 4 && argv[2][0] == 'd') {
		unsigned long len = strtoul(argv[3], NULL, 0), off = addr & (page - 1);

		fd = open("/dev/mem", O_RDONLY | O_SYNC);
		if (fd < 0)
			return perror("/dev/mem"), 1;
		p = mmap(NULL, off + len, PROT_READ, MAP_SHARED, fd, addr - off);
		if (p == MAP_FAILED)
			return perror("mmap"), 1;
		return fwrite((const void *)(p + off), 1, len, stdout) != len;
	}
	fd = open("/dev/mem", argc > 3 ? O_RDWR | O_SYNC : O_RDONLY | O_SYNC);
	if (fd < 0)
		return perror("/dev/mem"), 1;
	p = mmap(NULL, page, argc > 3 ? PROT_READ | PROT_WRITE : PROT_READ, MAP_SHARED, fd,
		 addr & ~(page - 1));
	if (p == MAP_FAILED)
		return perror("mmap"), 1;
	p += addr & (page - 1);
	if (argc > 3) {
		unsigned long v = strtoul(argv[3], NULL, 0);

		if (width == 8)
			*p = v;
		else if (width == 16)
			*(volatile uint16_t *)p = v;
		else
			*(volatile uint32_t *)p = v;
	}
	if (width == 8)
		printf("0x%02x\n", *p);
	else if (width == 16)
		printf("0x%04x\n", *(volatile uint16_t *)p);
	else
		printf("0x%08x\n", *(volatile uint32_t *)p);
	return 0;
}
