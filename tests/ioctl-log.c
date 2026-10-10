/*
 * ioctl-log.so: LD_PRELOAD shim logging the DSP bridge's ioctls (magic 0xDB) of a process to stderr:
 * time, cmd, the first words of the argument block (the message for put/get message, the path
 * for register), return value and errno. For comparing gst-dsp
 * on stock Harmattan and on the test kernel, e.g.
 *   LD_PRELOAD=/tmp/ioctl-log.so /tmp/gst-test 'uridecodebin uri=... ! fakesink' 2> ioctl.txt
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/*
 * The same words read from DRAM (an O_SYNC /dev/mem mapping is non-cacheable on ARM; root only, the
 * PFN from /proc/self/pagemap): tells a stale CPU cache line from data the DSP never wrote
 */
static void dump_dram(const void *va, unsigned int len)
{
	static int pm = -1, mem = -1;
	uintptr_t a = (uintptr_t)va;
	uint64_t e;
	volatile unsigned int *w;
	void *p;
	unsigned int i;

	if (pm < 0)
		pm = open("/proc/self/pagemap", O_RDONLY);
	if (mem < 0)
		mem = open("/dev/mem", O_RDONLY | O_SYNC);
	if (pm < 0 || mem < 0 || pread(pm, &e, 8, (a >> 12) * 8) != 8 || !(e >> 63))
		return;
	p = mmap(NULL, 4096, PROT_READ, MAP_SHARED, mem, (off_t)(e & ((1ULL << 55) - 1)) << 12);
	if (p == MAP_FAILED)
		return;
	w = (volatile unsigned int *)((char *)p + (a & 4095));
	fprintf(stderr, "  dram %08x+%x:", (unsigned int)a, len);
	for (i = 0; i < len / 4; i++)
		fprintf(stderr, " %08x", w[i]);
	fprintf(stderr, "\n");
	munmap(p, 4096);
}

/* PROC_MAPMEMORY table: user address <-> DSP address, to follow the DSP addresses in messages */
static struct { unsigned int user, size, da; } maps[4096];

static void *user_of(unsigned int da)
{
	unsigned int i;

	for (i = 0; i < 4096; i++)
		if (maps[i].size && da >= maps[i].da && da < maps[i].da + maps[i].size)
			return (void *)(uintptr_t)(maps[i].user + da - maps[i].da);
	return NULL;
}

/* 64 bytes of DRAM (non-cacheable /dev/mem view) at a user address, 0 if unavailable */
static int dram64(const void *va, unsigned int *out)
{
	static int pm = -1, mem = -1;
	uintptr_t a = (uintptr_t)va;
	uint64_t e;
	void *p;
	unsigned int i;

	if (pm < 0)
		pm = open("/proc/self/pagemap", O_RDONLY);
	if (mem < 0)
		mem = open("/dev/mem", O_RDONLY | O_SYNC);
	if (pm < 0 || mem < 0 || (a & 4095) > 4096 - 64 ||
	    pread(pm, &e, 8, (a >> 12) * 8) != 8 || !(e >> 63))
		return 0;
	p = mmap(NULL, 4096, PROT_READ, MAP_SHARED, mem, (off_t)(e & ((1ULL << 55) - 1)) << 12);
	if (p == MAP_FAILED)
		return 0;
	for (i = 0; i < 16; i++)
		out[i] = ((volatile unsigned int *)((char *)p + (a & 4095)))[i];
	munmap(p, 4096);
	return 1;
}

/* time inside each bridge call, per command; IOCTL_LOG=sum prints only this table at exit */
static struct { unsigned long cmd; unsigned int n; double us; } prof[64];
static double first, last;

static double now_us(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1e6 + t.tv_nsec / 1e3;
}

__attribute__((destructor)) static void prof_dump(void)
{
	double in = 0;
	int i;

	for (i = 0; i < 64 && prof[i].cmd; i++) {
		fprintf(stderr, "prof %08lx n %5u total %9.0f us avg %7.1f us\n", prof[i].cmd, prof[i].n,
			prof[i].us, prof[i].us / prof[i].n);
		in += prof[i].us;
	}
	if (last > first)
		fprintf(stderr, "prof span %.0f us, in bridge calls %.0f us\n", last - first, in);
}

static int quiet = -1;
static unsigned int last_proc;	/* the processor handle of the last map, for IOCTL_FLUSHIN */

int ioctl(int fd, unsigned long cmd, ...)
{
	double t0;
	static int (*real)(int, unsigned long, ...);
	unsigned int *a;
	struct timespec t;
	va_list ap;
	int ret, err;

	va_start(ap, cmd);
	a = va_arg(ap, unsigned int *);
	va_end(ap);
	if (!real)
		real = dlsym(RTLD_NEXT, "ioctl");
	/* NODE_PUTMESSAGE of a buffer (0x600 in, 0x601 out): is the data the DSP will read in DRAM? */
	if (a && cmd == 0x4004db4a && a[1] && ((unsigned int *)a[1])[0] == 0x600) {
		unsigned int *desc = user_of(((unsigned int *)a[1])[1]), *data, d[16], i, diff = 0;

		if (!real)
			real = dlsym(RTLD_NEXT, "ioctl");
		data = desc ? user_of(desc[0]) : NULL;
		/*
		 * IOCTL_DUMP=PREFIX: write each input buffer of 64 KiB or more, as the CPU sees it, to
		 * PREFIX-N.raw; IOCTL_FLUSHIN=1: write it back (PROC_FLUSHMEMORY) before the DSP gets it
		 */
		if (data && desc[4] >= 0x10000 && getenv("IOCTL_DUMP")) {
			static int n;
			char name[256];
			FILE *f;

			snprintf(name, sizeof(name), "%s-%d.raw", getenv("IOCTL_DUMP"), n++);
			f = fopen(name, "w");
			if (f) {
				fwrite(data, 1, desc[4], f);
				fclose(f);
			}
			fprintf(stderr, "  dump %s: %08x+%x\n", name, (unsigned int)(uintptr_t)data, desc[4]);
		}
		if (data && desc[4] >= 0x10000 && getenv("IOCTL_FLUSHIN")) {
			unsigned int f[16] = { last_proc, (unsigned int)(uintptr_t)data, desc[4], 0 };

			fprintf(stderr, "  flushin %08x+%x = %d\n", f[1], f[2], real(fd, 0x4004db2e, f));
		}
		if (data && dram64(data, d)) {
			for (i = 0; i < 16; i++)
				diff += d[i] != data[i];
			fprintf(stderr, "  input %08x (dsp %08x, %x bytes): %s %08x %08x | dram %08x %08x\n",
				(unsigned int)(uintptr_t)data, desc[0], desc[4], diff ? "STALE" : "ok",
				data[0], data[1], d[0], d[1]);
		}
	}
	if (quiet < 0)
		quiet = getenv("IOCTL_LOG") && !strcmp(getenv("IOCTL_LOG"), "sum");
	t0 = now_us();
	ret = real(fd, cmd, a);
	err = errno;
	/*
	 * IOCTL_V4L2=1: the pipeline's formats, links and streaming (subdev S_FMT: which, pad,
	 * width, height, code; video S_FMT: type, width, height, fourcc, bytesperline)
	 */
	if (a && getenv("IOCTL_V4L2") && (((cmd >> 8) & 0xff) == 'V' || ((cmd >> 8) & 0xff) == 'M') &&
	    (cmd == 0xc0585605 || cmd == 0xc0cc5605 || cmd == 0x40045612 || cmd == 0x40045613 ||
	     cmd == 0xc0344d03 || cmd == 0xc0345603)) {
		char p[64], l[64];
		ssize_t n;

		snprintf(p, sizeof(p), "/proc/self/fd/%d", fd);
		n = readlink(p, l, sizeof(l) - 1);
		l[n > 0 ? n : 0] = 0;
		clock_gettime(CLOCK_MONOTONIC, &t);
		fprintf(stderr, "%ld.%03ld v4l2 %s %08lx %08x %08x %08x %08x %08x %08x = %d\n",
			(long)t.tv_sec, t.tv_nsec / 1000000, l, cmd, a[0], a[1], a[2], a[3], a[4], a[5], ret);
	}
	/*
	 * IOCTL_UNMAP=N, a DSP MMU fault test: unmap the Nth mapping of 1 MiB or more (a frame
	 * buffer) right after it's made, so the DSP writes to an address its MMU can't translate
	 */
	if (a && cmd == 0xc004db2c && ret >= 0 && a[2] >= 0x100000 && getenv("IOCTL_UNMAP")) {
		static int n;

		if (++n == atoi(getenv("IOCTL_UNMAP"))) {
			/* PROC_UNMAPMEMORY: proc, size, DSP address (the kernel reads a whole union) */
			unsigned int u[16] = { a[0], a[2], *(unsigned int *)(uintptr_t)a[4] };

			fprintf(stderr, "IOCTL_UNMAP: unmapped %08x = %d\n", u[2], real(fd, 0x8004db2d, u));
		}
	}
	if (((cmd >> 8) & 0xff) == 0xdb) {
		double t1 = now_us();
		int i;

		for (i = 0; i < 63 && prof[i].cmd && prof[i].cmd != cmd; i++)
			;
		prof[i].cmd = cmd;
		prof[i].n++;
		prof[i].us += t1 - t0;
		if (!first)
			first = t0;
		last = t1;
		if (quiet) {
			errno = err;
			return ret;
		}
	}
	if (a && cmd == 0xc004db2c && ret >= 0) {	/* PROC_MAPMEMORY: proc, user, size, DSP address */
		unsigned int i;

		last_proc = a[0];
		for (i = 0; i < 4096 && maps[i].size && maps[i].da != (a[3] & ~4095u) + (a[1] & 4095); i++)
			;
		if (i < 4096) {
			maps[i].user = a[1];
			maps[i].size = a[2];
			maps[i].da = (a[3] & ~4095u) + (a[1] & 4095);
		}
	}
	if (((cmd >> 8) & 0xff) == 0xdb) {
		clock_gettime(CLOCK_MONOTONIC, &t);
		if (a && cmd == 0xc004db02 && a[2])	/* MGR_REGISTEROBJECT: uuid, type, path */
			fprintf(stderr, "%ld.%03ld %08lx type %u %s = %d (%d)\n", (long)t.tv_sec,
				t.tv_nsec / 1000000, cmd, a[1], (char *)a[2], ret, ret < 0 ? err : 0);
		else if (a && (cmd == 0x4004db4a || cmd == 0xc004db48) && a[1])
			/* NODE_PUTMESSAGE / NODE_GETMESSAGE: node, struct dsp_msg {cmd, arg1, arg2} */
			fprintf(stderr, "%ld.%03ld %08lx msg %08x %08x %08x = %d (%d)\n", (long)t.tv_sec,
				t.tv_nsec / 1000000, cmd, ((unsigned int *)a[1])[0],
				((unsigned int *)a[1])[1], ((unsigned int *)a[1])[2], ret, ret < 0 ? err : 0);
		else if (a)
			fprintf(stderr, "%ld.%03ld %08lx %08x %08x %08x %08x = %d (%d)\n", (long)t.tv_sec,
				t.tv_nsec / 1000000, cmd, a[0], a[1], a[2], a[3], ret, ret < 0 ? err : 0);
		else
			fprintf(stderr, "%ld.%03ld %08lx = %d (%d)\n", (long)t.tv_sec, t.tv_nsec / 1000000,
				cmd, ret, ret < 0 ? err : 0);
	}
	/* PROC_FLUSHMEMORY: does DRAM now hold what the process wrote? (first 64 bytes, root only) */
	if (a && cmd == 0x4004db2e && ret >= 0 && a[2] >= 64) {
		static int pm = -1, mem = -1;
		uintptr_t v = a[1];
		uint64_t e;
		void *p;

		if (pm < 0)
			pm = open("/proc/self/pagemap", O_RDONLY);
		if (mem < 0)
			mem = open("/dev/mem", O_RDONLY | O_SYNC);
		if (pm >= 0 && mem >= 0 && pread(pm, &e, 8, (v >> 12) * 8) == 8 && (e >> 63) &&
		    (v & 4095) <= 4096 - 64) {
			p = mmap(NULL, 4096, PROT_READ, MAP_SHARED, mem,
				 (off_t)(e & ((1ULL << 55) - 1)) << 12);
			if (p != MAP_FAILED) {
				volatile unsigned int *d = (volatile unsigned int *)((char *)p + (v & 4095));
				unsigned int *c = (unsigned int *)v, i, diff = 0;

				for (i = 0; i < 16; i++)
					diff += c[i] != d[i];
				fprintf(stderr, "  flush %08x+%x: %s %08x %08x %08x %08x | dram %08x %08x %08x %08x\n",
					a[1], a[2], diff ? "STALE" : "ok", c[0], c[1], c[2], c[3], d[0], d[1], d[2], d[3]);
				munmap(p, 4096);
			}
		}
	}
	/* PROC_INVALIDATEMEMORY of a small block (the codecs' parameter blocks): what the host reads now */
	if (a && cmd == 0x4004db30 && a[2] <= 0x40 && ret >= 0) {
		unsigned int *w = (unsigned int *)a[1], i;

		fprintf(stderr, "   inv %08x+%x:", a[1], a[2]);
		for (i = 0; i < a[2] / 4; i++)
			fprintf(stderr, " %08x", w[i]);
		fprintf(stderr, "\n");
		dump_dram(w, a[2]);
	}
	errno = err;
	return ret;
}
