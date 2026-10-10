/* sdrcpwr [VALUE]: read (and with VALUE write) the OMAP3 SDRC_POWER register (0x6D000070) only */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
int main(int argc, char **argv)
{
	int fd = open("/dev/mem", argc > 1 ? O_RDWR | O_SYNC : O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile unsigned *r = mmap(0, 4096, argc > 1 ? PROT_READ | PROT_WRITE : PROT_READ, MAP_SHARED, fd, 0x6D000000);
	if (r == MAP_FAILED) { perror("mmap"); return 1; }
	printf("SDRC_POWER = 0x%08x\n", r[0x70 / 4]);
	if (argc > 1) { r[0x70 / 4] = strtoul(argv[1], 0, 0); printf("SDRC_POWER = 0x%08x (written)\n", r[0x70 / 4]); }
	return 0;
}
