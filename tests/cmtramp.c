/*
 * cmtramp: the call-audio path to the modem without a call (no SIM). Talks to /dev/cmt_speech as
 * Harmattan's libcmtspeechdata 2.1.1 does (same ioctls, buffer layout, wake line handling and
 * messages: HANDOFF-CALL.md), in two parts:
 *  - control: SSI_CONFIG_REQ on, then off, each waiting for the modem's SSI_CONFIG_RESP (what the
 *    library sends at every call's start and end);
 *  - data: the library's TEST_RAMP_PING (the N9's modem has it): the modem answers each ping with its
 *    own TEST_RAMP_PING, asking for an uplink ramp (sent), and one downlink frame on the speech data
 *    channel holding a byte ramp, which is checked; with PAIR=1 then two pings back to back, timing
 *    the second write() (with "HSI: cmt_speech: wait for a pending control write" it waits for the
 *    first to go out instead of failing with EBUSY).
 * The modem's own TEST_RAMP_PING and RESET_CONN_REQ are answered as the library does; nothing else
 * is sent on the data channel.
 *   cmtramp [PINGS [WORDS...]]   default: 3 pings each of 81 words (8 kHz frame) and 160 (16 kHz)
 * Environment: GAP_MS=n waits n ms between pings (default 20, a call's frame rate; with 0 the modem
 * stops taking frames after 3-4 pings and resets itself, on stock too: boot 281), NOUL=1 leaves the
 * modem's pings unanswered, PAIR=1 adds the back-to-back pair, ULX=n XORs the uplink ramp's bytes
 * with n (does the downlink echo it?).
 * The data part stops at the first ping left unanswered and prints the SSI port's registers (debugfs).
 * PulseAudio holds the device: `initctl stop pulseaudio` first (tests/cmtramp.sh does it all).
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* include/uapi/linux/hsi/cs-protocol.h */
struct cs_buffer_config { uint32_t rx_bufs, tx_bufs, buf_size, flags, reserved[4]; };
struct cs_mmap_config_block {
	uint32_t reserved1, buf_size, rx_bufs, tx_bufs, reserved2;
	uint32_t rx_offsets[16], tx_offsets[16], rx_ptr, rx_ptr_boundary, reserved3[2], ts_sec, ts_nsec;
};
#define CS_SET_WAKELINE		_IOW('C', 23, unsigned int)
#define CS_GET_IF_VERSION	_IOR('C', 30, unsigned int)
#define CS_CONFIG_BUFS		_IOW('C', 31, struct cs_buffer_config)
/* command words: type in bits 31-28, domain 27-24 (0 driver, 1 control, 2 data), 3 parameter bytes */
#define TYPE(w)		((w) >> 28)
#define DOMAIN(w)	(((w) >> 24) & 0xf)
#define RESET_CONN_REQ	0x01000000
#define RESET_CONN_RESP	0x11000000
#define SSI_CONFIG_REQ	0x21000202	/* layout 2 (in order, LE), protocol version 1; | 1 = on */
#define SSI_CONFIG_RESP	6
#define TEST_RAMP_PING	0xc
#define RX_DATA		2		/* driver: CS_RX_DATA_RECEIVED | rx pointer */

static int fd;
static volatile struct cs_mmap_config_block *cfg;
static uint8_t *base;
static int noul, ulx;

static double now_us(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1e6 + t.tv_nsec / 1e3;
}

/* write() one command word; how long the write() took in us, -1 when it failed */
static double put(uint32_t w)
{
	double t = now_us();

	if (write(fd, &w, 4) != 4)
		return printf("write %08x: %s\n", w, strerror(errno)), -1;
	return now_us() - t;
}

static void wakeline(unsigned int on)
{
	struct timespec wait = { 0, 500000 };	/* the library's wait after raising the line */

	if (ioctl(fd, CS_SET_WAKELINE, &on) < 0)
		printf("CS_SET_WAKELINE %u: %s\n", on, strerror(errno));
	if (on)
		nanosleep(&wait, NULL);
}

static int config(unsigned int words)
{
	struct cs_buffer_config c = { 3, 2, words ? 4 + words * 4 : 0, words ? 3 : 0, { 0 } };

	if (ioctl(fd, CS_CONFIG_BUFS, &c) < 0)
		return printf("CS_CONFIG_BUFS %u bytes: %s\n", c.buf_size, strerror(errno)), -1;
	if (words)
		printf("buffers: %u bytes, rx at %u %u %u, tx at %u %u, rx_ptr %u of %u\n", cfg->buf_size,
		       cfg->rx_offsets[0], cfg->rx_offsets[1], cfg->rx_offsets[2], cfg->tx_offsets[0],
		       cfg->tx_offsets[1], cfg->rx_ptr, cfg->rx_ptr_boundary);
	return 0;
}

/* the modem's TEST_RAMP_PING: an uplink ramp in TX slot 0, header as the library's */
static void answer_ping(uint32_t w)
{
	uint8_t start = w >> 8, words = w, *p;
	uint32_t hdr = 0xff000000 | words << 16 | 0x8000 | 1;

	printf("modem TEST_RAMP_PING: start 0x%02x, %u words: %s\n", start, words,
	       noul ? "left unanswered (NOUL)" : "sending the uplink ramp");
	/* as the library: the buffers are set up again only for another frame size */
	if (noul || (cfg->buf_size != 4 + words * 4u && config(words)))
		return;
	p = base + cfg->tx_offsets[0];
	memcpy(p, &hdr, 4);
	for (int i = 0; i < words * 4; i++)
		p[4 + i] = (start + i) ^ ulx;
	put(0x30000000);	/* CS_TX_DATA_READY, slot 0 */
}

/* a downlink frame: 1 when it holds the ramp from start */
static int frame_ok(uint32_t e, uint8_t start, double t0)
{
	unsigned int slot = (e & 0xffffff) % cfg->rx_bufs, n = cfg->buf_size - 4, plain = 0, swapped = 0;
	uint8_t *d = base + cfg->rx_offsets[slot];

	for (unsigned int i = 0; i < n; i++) {
		plain += d[4 + i] == (uint8_t)(start + i);
		swapped += d[4 + (i ^ 1)] == (uint8_t)(start + i);
	}
	printf("  downlink frame after %.0f us: slot %u, header %02x%02x%02x%02x, data %02x %02x %02x %02x..., "
	       "%u/%u bytes of the ramp from 0x%02x in order (%u halfword-swapped)\n", now_us() - t0, slot,
	       d[3], d[2], d[1], d[0], d[4], d[5], d[6], d[7], plain, n, start, swapped);
	return plain == n || swapped == n;
}

/* the next event within ms (0 if none), answering the modem's pings and resets on the way */
static uint32_t next(double t0, int ms)
{
	struct pollfd p = { fd, POLLIN, 0 };
	uint32_t e;

	while (poll(&p, 1, ms) == 1) {
		if (read(fd, &e, 4) != 4)
			return printf("read: %s\n", strerror(errno)), 0;
		if (e == RESET_CONN_REQ) {
			printf("  modem RESET_CONN_REQ: answering\n");
			put(RESET_CONN_RESP);
		} else if (DOMAIN(e) == 1 && TYPE(e) == TEST_RAMP_PING) {
			answer_ping(e);
		} else {
			if (DOMAIN(e) || TYPE(e) != RX_DATA)	/* CS_ERROR is 1xxxxxxx */
				printf("  event %08x after %.0f us\n", e, now_us() - t0);
			return e;
		}
	}
	return printf("  nothing within %d ms\n", ms), 0;
}

static void dump_regs(void)
{
	char line[128];
	FILE *f = fopen("/sys/kernel/debug/ssi0/port0/regs", "r");

	if (!f)
		return;
	while (fgets(line, sizeof(line), f))
		if (strstr(line, "WAKE") || strstr(line, "MPU_") || strstr(line, "STATE") || strstr(line, "ERROR") ||
		    strstr(line, "BUFFER"))
			printf("  regs %s", line);
	fclose(f);
}

/* SSI_CONFIG_REQ on or off: 1 when the modem answers it with success */
static int ssi_config(unsigned int on)
{
	double t0 = now_us(), w = put(SSI_CONFIG_REQ | on);
	uint32_t e;

	printf("SSI_CONFIG_REQ %s (write %.0f us)\n", on ? "on" : "off", w);
	if (w < 0)
		return 0;
	do
		e = next(t0, 300);
	while (e && !(DOMAIN(e) == 1 && TYPE(e) == SSI_CONFIG_RESP));
	return e && (e & 3) == 0;
}

int main(int argc, char **argv)
{
	unsigned int ver = 0, pings = argc > 1 ? atoi(argv[1]) : 3, sizes[] = { 81, 160 };
	unsigned int nsizes = argc > 2 ? argc - 2 : 2, ok = 0, n = 0, ctl, failed = 0;
	unsigned int gap = getenv("GAP_MS") ? atoi(getenv("GAP_MS")) : 20, pair = getenv("PAIR") != NULL;
	struct timespec gap_ts = { gap / 1000, gap % 1000 * 1000000L };
	uint8_t start = 0xaa;

	noul = getenv("NOUL") != NULL;
	ulx = getenv("ULX") ? strtol(getenv("ULX"), NULL, 0) : 0;
	fd = open("/dev/cmt_speech", O_RDWR);
	if (fd < 0)
		return printf("/dev/cmt_speech: %s%s\n", strerror(errno),
			      errno == EBUSY ? " (PulseAudio holds it: initctl stop pulseaudio)" : ""), 2;
	if (ioctl(fd, CS_GET_IF_VERSION, &ver) < 0)
		printf("CS_GET_IF_VERSION: %s\n", strerror(errno));
	base = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (base == MAP_FAILED)
		return printf("mmap: %s\n", strerror(errno)), 2;
	cfg = (void *)base;
	printf("interface version %u\n== control\n", ver);
	wakeline(1);
	ctl = ssi_config(1);
	ctl += ssi_config(0);
	wakeline(0);
	printf("== data (TEST_RAMP_PING)\n");
	for (unsigned int s = 0; s < nsizes && !failed; s++) {
		unsigned int words = argc > 2 ? atoi(argv[2 + s]) : sizes[s];
		double t0, w;
		uint32_t e;

		if (config(words))
			continue;
		wakeline(1);
		for (unsigned int i = 0; i < pings + pair && !failed; i++) {
			uint8_t a = start++, b = start++;

			if (gap)
				nanosleep(&gap_ts, NULL);
			t0 = now_us();
			if (i < pings) {	/* one ping */
				int good;

				w = put((uint32_t)TEST_RAMP_PING << 28 | 1 << 24 | 2 << 16 | a << 8 | words);
				printf("ping 0x%02x, %u words (write %.0f us)\n", a, words, w);
				e = w < 0 ? 0 : next(t0, 100);	/* replies come within 2 ms */
				good = e && !DOMAIN(e) && TYPE(e) == RX_DATA && frame_ok(e, a, t0);
				n++, ok += good;
				if (!good) {
					dump_regs();
					failed = 1;
				}
				continue;
			}
			/* two back to back */
			put((uint32_t)TEST_RAMP_PING << 28 | 1 << 24 | 2 << 16 | a << 8 | words);
			w = put((uint32_t)TEST_RAMP_PING << 28 | 1 << 24 | 2 << 16 | b << 8 | words);
			printf("pings 0x%02x and 0x%02x back to back: the second write took %.0f us\n", a, b, w);
			for (int k = 0; k < 2; k++) {
				e = next(t0, 100);
				n++, ok += e && !DOMAIN(e) && TYPE(e) == RX_DATA && frame_ok(e, k ? b : a, t0);
			}
		}
		wakeline(0);
	}
	config(0);
	munmap(base, 4096);
	close(fd);
	printf("control: %u of 2 SSI_CONFIG_REQ answered with success; data: %u of %u pings answered with the ramp\n",
	       ctl, ok, n);
	return ctl == 2 && ok == n && n ? 0 : 1;
}
