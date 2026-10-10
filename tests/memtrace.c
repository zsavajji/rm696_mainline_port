/*
 * memtrace.so: LD_PRELOAD counter of a process's memory syscalls and large mallocs (the GPU blob's
 * per-frame allocation pattern on stock against the test kernel). Prints at exit to stderr:
 * counts and total bytes of mmap/mmap64 (anonymous and file-backed apart), munmap, mremap, brk,
 * madvise, malloc >= 64 KiB and free, ioctl. MEMTRACE_EVERY=N also prints every N mmaps with the
 * caller's address (to map to the blob with its symbols).
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static long n_mmap_anon, b_mmap_anon, n_mmap_file, b_mmap_file, n_munmap, b_munmap, n_mremap,
	n_brk, n_madvise, n_malloc_big, b_malloc_big, n_free, n_ioctl, every;
static int inited;

static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t);
static int (*real_munmap)(void *, size_t);
static void *(*real_mremap)(void *, size_t, size_t, int, ...);
static int (*real_brk)(void *);
static void *(*real_sbrk)(intptr_t);
static int (*real_madvise)(void *, size_t, int);
static void *(*real_malloc)(size_t);
static void (*real_free)(void *);
static int (*real_ioctl)(int, unsigned long, ...);

static void init(void)
{
	if (inited)
		return;
	inited = 1;
	real_mmap = dlsym(RTLD_NEXT, "mmap");
	real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
	real_munmap = dlsym(RTLD_NEXT, "munmap");
	real_mremap = dlsym(RTLD_NEXT, "mremap");
	real_brk = dlsym(RTLD_NEXT, "brk");
	real_sbrk = dlsym(RTLD_NEXT, "sbrk");
	real_madvise = dlsym(RTLD_NEXT, "madvise");
	real_malloc = dlsym(RTLD_NEXT, "malloc");
	real_free = dlsym(RTLD_NEXT, "free");
	real_ioctl = dlsym(RTLD_NEXT, "ioctl");
	every = getenv("MEMTRACE_EVERY") ? atol(getenv("MEMTRACE_EVERY")) : 0;
}

static void report(void)
{
	fprintf(stderr, "memtrace: mmap anon %ld (%ld KiB) file/dev %ld (%ld KiB), munmap %ld (%ld KiB), "
		"mremap %ld, brk/sbrk %ld, madvise %ld, malloc>=64K %ld (%ld KiB), free %ld, ioctl %ld\n",
		n_mmap_anon, b_mmap_anon >> 10, n_mmap_file, b_mmap_file >> 10, n_munmap, b_munmap >> 10,
		n_mremap, n_brk, n_madvise, n_malloc_big, b_malloc_big >> 10, n_free, n_ioctl);
}

__attribute__((destructor)) static void fini(void)
{
	report();
}

static void count_mmap(size_t len, int flags, int fd)
{
	if (flags & MAP_ANONYMOUS) {
		n_mmap_anon++;
		b_mmap_anon += len;
	} else {
		n_mmap_file++;
		b_mmap_file += len;
	}
	if (every && (n_mmap_anon + n_mmap_file) % every == 0)
		fprintf(stderr, "memtrace: mmap #%ld len %zu flags 0x%x fd %d from %p\n",
			n_mmap_anon + n_mmap_file, len, flags, fd, __builtin_return_address(1));
}

void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off)
{
	init();
	count_mmap(len, flags, fd);
	return real_mmap(addr, len, prot, flags, fd, off);
}

void *mmap64(void *addr, size_t len, int prot, int flags, int fd, off64_t off)
{
	init();
	count_mmap(len, flags, fd);
	return real_mmap64(addr, len, prot, flags, fd, off);
}

int munmap(void *addr, size_t len)
{
	init();
	n_munmap++;
	b_munmap += len;
	return real_munmap(addr, len);
}

void *mremap(void *old, size_t old_size, size_t new_size, int flags, ...)
{
	va_list ap;
	void *new_addr = NULL;

	init();
	n_mremap++;
	if (flags & MREMAP_FIXED) {
		va_start(ap, flags);
		new_addr = va_arg(ap, void *);
		va_end(ap);
		return real_mremap(old, old_size, new_size, flags, new_addr);
	}
	return real_mremap(old, old_size, new_size, flags);
}

int brk(void *addr)
{
	init();
	n_brk++;
	return real_brk(addr);
}

void *sbrk(intptr_t inc)
{
	init();
	n_brk++;
	return real_sbrk(inc);
}

int madvise(void *addr, size_t len, int advice)
{
	init();
	n_madvise++;
	return real_madvise(addr, len, advice);
}

void *malloc(size_t size)
{
	static char boot[4096];	/* dlsym's own malloc before real_malloc is known */
	static size_t used;

	if (!real_malloc) {
		void *p;

		if (inited) {
			p = boot + used;
			used += (size + 7) & ~7;
			return used <= sizeof(boot) ? p : NULL;
		}
		init();
	}
	if (size >= 65536) {
		n_malloc_big++;
		b_malloc_big += size;
	}
	return real_malloc(size);
}

void free(void *p)
{
	init();
	n_free++;
	if (p && (char *)p >= (char *)fini && (char *)p < (char *)fini + 1)	/* never: silences -Wunused */
		return;
	real_free(p);
}

int ioctl(int fd, unsigned long req, ...)
{
	va_list ap;
	void *arg;

	init();
	n_ioctl++;
	va_start(ap, req);
	arg = va_arg(ap, void *);
	va_end(ap);
	return real_ioctl(fd, req, arg);
}
