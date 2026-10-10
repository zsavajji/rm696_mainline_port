/*
 * dsprestart [N]: stop, reload and start the DSP N times (default 1) through the bridge's ioctls, the
 * steps of its recovery (proc_auto_start(): stop, load the base image, start). Root, test kernel only;
 * nothing else may be using the DSP. Each start logs to the kernel log (proc_start, any L3 error).
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define DB_PROC(n, dir) dir(0xDB, 0x20 | (n), unsigned long)
#define PROC_ATTACH	DB_PROC(0, _IOWR)
#define PROC_DETACH	DB_PROC(2, _IOR)
#define PROC_LOAD	DB_PROC(7, _IOW)
#define PROC_START	DB_PROC(9, _IOW)
#define PROC_STOP	DB_PROC(15, _IOWR)

/* the kernel copies a whole union trapped_args: pass a zeroed block that size or larger */
static unsigned long args[16];

static int call(int fd, unsigned long cmd, const char *what)
{
	int r = ioctl(fd, cmd, args);

	if (r < 0)
		perror(what);
	return r;
}

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 1, fd, i;
	char *image[] = { "/lib/dsp/baseimage.dof", NULL };
	void *proc = NULL;

	fd = open("/dev/DspBridge", O_RDWR);
	if (fd < 0) {
		perror("/dev/DspBridge");
		return 1;
	}
	memset(args, 0, sizeof(args));
	args[0] = 0;			/* processor 0, default attributes */
	args[2] = (unsigned long)&proc;
	if (call(fd, PROC_ATTACH, "attach"))
		return 1;
	for (i = 0; i < n; i++) {
		memset(args, 0, sizeof(args));
		args[0] = (unsigned long)proc;
		if (call(fd, PROC_STOP, "stop"))
			break;
		args[1] = 1;		/* argc */
		args[2] = (unsigned long)image;
		if (call(fd, PROC_LOAD, "load"))
			break;
		if (call(fd, PROC_START, "start"))
			break;
		printf("start %d done\n", i + 1);
		fflush(stdout);
		sleep(1);
	}
	memset(args, 0, sizeof(args));
	args[0] = (unsigned long)proc;
	call(fd, PROC_DETACH, "detach");
	close(fd);
	return i == n ? 0 : 1;
}
