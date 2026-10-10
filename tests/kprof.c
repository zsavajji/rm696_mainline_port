/*
 * kprof: a system-wide sampling profiler for the phone (Harmattan has no perf). CPU-clock samples
 * through perf_event_open for SECONDS; kernel addresses resolved with /proc/kallsyms (top symbols),
 * user samples counted per process. Run as root: kprof [SECONDS] [HZ]
 * KPROF_PID=n: kernel symbols of that process (its threads) only.
 * KPROF_TASKS=n: sample only that process's threads (one event per thread, as its owner, no root:
 * also on stock): its CPU time split into user and kernel, and its kernel symbols.
 * KPROF_CHAIN=1 (system-wide mode): also kernel call chains, for each symbol's inclusive share (the
 * samples it was on the stack for, itself or its callees). KPROF_CALLERS=sym: with KPROF_CHAIN, who
 * called sym (the frame above its first one in each chain).
 */
#include <dirent.h>
#include <linux/perf_event.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define NR_perf_event_open 364	/* ARM EABI */
#define PAGES 64		/* ring buffer data pages (power of two) */

struct sym { uint32_t addr; char name[64]; long n, inc, callers; int seen; };
struct proc { uint32_t pid; long n; };

static struct sym *syms;
static int nsyms;
static struct proc procs[4096];
static int nprocs;
static long total, kernel, idle_pid0;

static int load_kallsyms(void)
{
	FILE *f = fopen("/proc/kallsyms", "r");
	char line[256], type, name[128];
	unsigned long addr;
	int cap = 0;

	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f)) {
		if (sscanf(line, "%lx %c %127s", &addr, &type, name) != 3 || !addr)
			continue;
		if (type != 't' && type != 'T')
			continue;
		if (nsyms == cap) {
			cap = cap ? cap * 2 : 65536;
			syms = realloc(syms, cap * sizeof(*syms));
		}
		syms[nsyms].addr = addr;
		snprintf(syms[nsyms].name, sizeof(syms[nsyms].name), "%s", name);
		syms[nsyms].inc = syms[nsyms].callers = syms[nsyms].seen = 0;
		syms[nsyms++].n = 0;
	}
	fclose(f);
	return nsyms ? 0 : -1;
}

static int by_addr(const void *a, const void *b)
{
	uint32_t x = ((const struct sym *)a)->addr, y = ((const struct sym *)b)->addr;

	return x < y ? -1 : x > y;
}

static int by_count(const void *a, const void *b)
{
	return ((const struct sym *)b)->n - ((const struct sym *)a)->n;
}

static int proc_by_count(const void *a, const void *b)
{
	return ((const struct proc *)b)->n - ((const struct proc *)a)->n;
}

static int by_inc(const void *a, const void *b)
{
	return ((const struct sym *)b)->inc - ((const struct sym *)a)->inc;
}

static int by_callers(const void *a, const void *b)
{
	return ((const struct sym *)b)->callers - ((const struct sym *)a)->callers;
}

static int sym_index(uint32_t ip)
{
	int lo = 0, hi = nsyms - 1;

	while (lo < hi) {	/* last symbol at or below ip */
		int mid = (lo + hi + 1) / 2;

		if (syms[mid].addr <= ip)
			lo = mid;
		else
			hi = mid - 1;
	}
	return nsyms && syms[lo].addr <= ip ? lo : -1;
}

static void kernel_sample(uint32_t ip)
{
	int i = sym_index(ip);

	if (i >= 0)
		syms[i].n++;
}

/* a sample's kernel call chain (u64 nr, then nr addresses with context markers): each symbol once */
static long chains, called;
static int target = -1;	/* KPROF_CALLERS's symbol */
static void chain_sample(const char *p)
{
	static int idx[256];
	uint64_t nr, ip;
	int i, n = 0, k, found = 0;

	memcpy(&nr, p, 8);
	for (i = 0; i < (int)nr && n < 256; i++) {
		memcpy(&ip, p + 8 + 8 * i, 8);
		if (ip == (uint64_t)-512)	/* PERF_CONTEXT_USER: the user part follows */
			break;
		if (ip >= (uint64_t)-4095)	/* PERF_CONTEXT_KERNEL... */
			continue;
		k = sym_index(ip);
		if (found == 1 && k != target && k >= 0) {
			syms[k].callers++;
			called++;
			found = 2;
		}
		if (k == target && target >= 0 && !found)
			found = 1;
		if (k >= 0 && !syms[k].seen) {
			syms[k].seen = 1;
			idx[n++] = k;
		}
	}
	for (i = 0; i < n; i++) {
		syms[idx[i]].inc++;
		syms[idx[i]].seen = 0;
	}
	chains++;
}

static void user_sample(uint32_t pid)
{
	int i;

	for (i = 0; i < nprocs; i++)
		if (procs[i].pid == pid)
			break;
	if (i == nprocs) {
		if (nprocs == 4096)
			return;
		procs[nprocs++] = (struct proc){ pid, 0 };
	}
	procs[i].n++;
}

static void comm(uint32_t pid, char *buf, size_t len)
{
	char path[64];
	FILE *f;

	snprintf(path, sizeof(path), "/proc/%u/comm", pid);
	f = fopen(path, "r");
	if (!f || !fgets(buf, len, f))
		snprintf(buf, len, "(%u)", pid);
	if (f)
		fclose(f);
	buf[strcspn(buf, "\n")] = 0;
}

/* one CPU-clock event per thread of a process, small buffers (perf's mlock limit for users) */
#define TPAGES 2
static int per_task(int pid, int secs, int hz)
{
	long page = sysconf(_SC_PAGESIZE);
	struct perf_event_attr attr;
	struct perf_event_mmap_page *meta[256];
	long user = 0, n = 0;
	char path[64];
	struct dirent *d;
	DIR *dir;
	time_t end;
	int i;

	snprintf(path, sizeof(path), "/proc/%d/task", pid);
	if (!(dir = opendir(path)))
		return perror(path), 1;
	memset(&attr, 0, sizeof(attr));
	attr.size = sizeof(attr);
	attr.type = PERF_TYPE_SOFTWARE;
	attr.config = PERF_COUNT_SW_CPU_CLOCK;
	attr.freq = 1;
	attr.sample_freq = hz;
	attr.sample_type = PERF_SAMPLE_IP | PERF_SAMPLE_TID;
	while ((d = readdir(dir)) && n < 256) {
		int fd, tid = atoi(d->d_name);

		if (tid <= 0)
			continue;
		if ((fd = syscall(NR_perf_event_open, &attr, tid, -1, -1, 0)) < 0) {
			if (!n)
				perror("perf_event_open");
			continue;
		}
		meta[n] = mmap(NULL, (TPAGES + 1) * page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		if (meta[n] == MAP_FAILED)
			return perror("mmap"), 1;
		n++;
	}
	closedir(dir);
	printf("%ld threads\n", n);
	for (end = time(NULL) + secs; time(NULL) < end; usleep(10000))
		for (i = 0; i < n; i++) {
			char *data = (char *)meta[i] + page;
			uint64_t head = meta[i]->data_head, tail = meta[i]->data_tail;

			__sync_synchronize();
			while (tail < head) {
				struct perf_event_header h;
				uint64_t off = tail % (TPAGES * page);
				char rec[64];
				size_t k;

				memcpy(&h, data + off, sizeof(h));
				for (k = 0; k < h.size && k < sizeof(rec); k++)
					rec[k] = data[(off + k) % (TPAGES * page)];
				if (h.type == PERF_RECORD_SAMPLE) {
					uint64_t ip;

					memcpy(&ip, rec + sizeof(h), 8);
					total++;
					if ((h.misc & PERF_RECORD_MISC_CPUMODE_MASK) == PERF_RECORD_MISC_KERNEL) {
						kernel++;
						kernel_sample(ip);
					} else
						user++;
				}
				tail += h.size;
			}
			meta[i]->data_tail = tail;
		}
	printf("%ld samples at %d Hz over %d s: CPU %.1f%%, user %.1f%%, kernel %.1f%%\n", total, hz, secs,
	       100.0 * total / hz / secs, 100.0 * user / hz / secs, 100.0 * kernel / hz / secs);
	qsort(syms, nsyms, sizeof(*syms), by_count);
	printf("kernel symbols (share of the process's samples):\n");
	for (i = 0; i < nsyms && i < 40 && syms[i].n; i++)
		printf("  %5.1f%%  %s\n", 100.0 * syms[i].n / total, syms[i].name);
	return 0;
}

int main(int argc, char **argv)
{
	int secs = argc > 1 ? atoi(argv[1]) : 10, hz = argc > 2 ? atoi(argv[2]) : 1000, fd, i;
	long page = sysconf(_SC_PAGESIZE);
	struct perf_event_attr attr;
	struct perf_event_mmap_page *meta;
	char *data;
	time_t end;
	uint32_t only = getenv("KPROF_PID") ? atoi(getenv("KPROF_PID")) : 0;
	int chain = getenv("KPROF_CHAIN") != NULL;
	static char rec[2048];

	if (load_kallsyms())
		return fprintf(stderr, "no /proc/kallsyms\n"), 1;
	qsort(syms, nsyms, sizeof(*syms), by_addr);
	for (i = 0; getenv("KPROF_CALLERS") && i < nsyms; i++)
		if (!strcmp(syms[i].name, getenv("KPROF_CALLERS")))
			target = i;
	if (getenv("KPROF_TASKS"))
		return per_task(atoi(getenv("KPROF_TASKS")), secs, hz);

	memset(&attr, 0, sizeof(attr));
	attr.size = sizeof(attr);
	attr.type = PERF_TYPE_SOFTWARE;
	attr.config = PERF_COUNT_SW_CPU_CLOCK;
	attr.freq = 1;
	attr.sample_freq = hz;
	attr.sample_type = PERF_SAMPLE_IP | PERF_SAMPLE_TID | (chain ? PERF_SAMPLE_CALLCHAIN : 0);
	fd = syscall(NR_perf_event_open, &attr, -1, 0, -1, 0);	/* all tasks, CPU 0 */
	if (fd < 0)
		return perror("perf_event_open"), 1;
	meta = mmap(NULL, (PAGES + 1) * page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (meta == MAP_FAILED)
		return perror("mmap"), 1;
	data = (char *)meta + page;

	for (end = time(NULL) + secs; time(NULL) < end;) {
		uint64_t head = meta->data_head, tail = meta->data_tail;

		__sync_synchronize();
		while (tail < head) {
			struct perf_event_header h;
			uint64_t off = tail % (PAGES * page);
			size_t n;

			memcpy(&h, data + off, sizeof(h));
			for (n = 0; n < h.size && n < sizeof(rec); n++)
				rec[n] = data[(off + n) % (PAGES * page)];
			if (h.type == PERF_RECORD_SAMPLE) {
				uint64_t ip;
				uint32_t pid;

				memcpy(&ip, rec + sizeof(h), 8);
				memcpy(&pid, rec + sizeof(h) + 8, 4);
				total++;
				if (pid == 0)
					idle_pid0++;
				else if ((h.misc & PERF_RECORD_MISC_CPUMODE_MASK) == PERF_RECORD_MISC_KERNEL) {
					kernel++;
					if (!only || pid == only) {
						kernel_sample(ip);
						if (chain && h.size <= sizeof(rec))
							chain_sample(rec + sizeof(h) + 16);
					}
				} else
					user_sample(pid);
			}
			tail += h.size;
		}
		meta->data_tail = tail;
		usleep(20000);
	}

	printf("%ld samples: idle %ld%%, kernel (not idle) %ld%%, user %ld%%\n", total,
	       100 * idle_pid0 / (total ? total : 1), 100 * kernel / (total ? total : 1),
	       100 * (total - kernel - idle_pid0) / (total ? total : 1));
	qsort(syms, nsyms, sizeof(*syms), by_count);
	printf("kernel symbols (share of all samples):\n");
	for (i = 0; i < nsyms && i < (getenv("KPROF_TOP") ? atoi(getenv("KPROF_TOP")) : 30) && syms[i].n; i++)
		printf("  %5.1f%%  %s\n", 100.0 * syms[i].n / total, syms[i].name);
	if (chain && target >= 0) {
		qsort(syms, nsyms, sizeof(*syms), by_callers);
		printf("callers of %s (%ld samples):\n", getenv("KPROF_CALLERS"), called);
		for (i = 0; i < nsyms && i < 20 && syms[i].callers; i++)
			printf("  %5.1f%%  %s\n", 100.0 * syms[i].callers / called, syms[i].name);
	}
	if (chain) {
		qsort(syms, nsyms, sizeof(*syms), by_inc);
		printf("inclusive (share of the %ld kernel samples with a chain):\n", chains);
		for (i = 0; i < nsyms && i < (getenv("KPROF_TOP") ? atoi(getenv("KPROF_TOP")) : 30) && syms[i].inc; i++)
			printf("  %5.1f%%  %s\n", 100.0 * syms[i].inc / chains, syms[i].name);
	}
	qsort(procs, nprocs, sizeof(*procs), proc_by_count);
	printf("user time by process:\n");
	for (i = 0; i < nprocs && i < 10; i++) {
		char name[32];

		comm(procs[i].pid, name, sizeof(name));
		printf("  %5.1f%%  %s\n", 100.0 * procs[i].n / total, name);
	}
	return 0;
}
