/*
 * Minimal capture through the N9's ISP, with Harmattan's kernel ABI (Nokia's 'M' media ioctls: its
 * kernel's media.h; the subdev structs as its binaries use them, newer than its SDK's headers): sensor -> CSI2a -> CCDC -> preview -> resizer -> "OMAP3 ISP resizer output", as
 * Harmattan's primary viewfinder pipeline, MMAP buffers, no 3A. For bisecting camera problems.
 * Usage: ispcap [frames [width height [sensor-width sensor-height [prv]]]]   (defaults 300 640 480 1776 1008;
 * "prv": capture from "OMAP3 ISP preview output", without the resizer; ISPCAP_SAVE=file keeps the
 * last frame; ISPCAP_FRONT=1 the front camera through CCP2)
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>
#include <linux/videodev2.h>
#include "nokia-media.h"

/* Harmattan's subdev format ABI (VIDIOC_SUBDEV_S_FMT 0xc0585605, as libgstcamera2 issues it) */
struct mbus_fmt { __u32 width, height, code, field, colorspace, reserved[7]; };
struct subdev_format { __u32 which, pad; struct mbus_fmt format; __u32 reserved[8]; };
#define VIDIOC_SUBDEV_G_FMT	_IOWR('V', 4, struct subdev_format)
#define VIDIOC_SUBDEV_S_FMT	_IOWR('V', 5, struct subdev_format)
#define V4L2_SUBDEV_FORMAT_ACTIVE	1
#define V4L2_MBUS_FMT_SGRBG10_1X10	0x300a
#define V4L2_MBUS_FMT_UYVY8_1X16	0x200f

#define MAXE 64
static struct media_entity_desc ents[MAXE];
static int nents, mfd;

#define die(...) do { fprintf(stderr, __VA_ARGS__); fprintf(stderr, " (%s)\n", strerror(errno)); exit(1); } while (0)

static int ent(const char *prefix)
{
	for (int i = 0; i < nents; i++)
		if (!strncmp(ents[i].name, prefix, strlen(prefix)))
			return i;
	fprintf(stderr, "no entity %s\n", prefix);
	exit(1);
}

static int node(int i)	/* open an entity's device node, found as Harmattan does: /sys/dev/char */
{
	char p[64], l[256];
	snprintf(p, sizeof(p), "/sys/dev/char/%u:%u", ents[i].v4l.major, ents[i].v4l.minor);
	ssize_t n = readlink(p, l, sizeof(l) - 1);
	if (n < 0)
		die("readlink %s", p);
	l[n] = 0;
	snprintf(p, sizeof(p), "/dev/%s", strrchr(l, '/') + 1);
	int fd = open(p, O_RDWR);
	if (fd < 0)
		die("open %s", p);
	return fd;
}

static void link_(int src, int sp, int snk, int kp, int on)
{
	struct media_link_desc l;
	memset(&l, 0, sizeof(l));
	l.source.entity = ents[src].id; l.source.index = sp;
	l.sink.entity = ents[snk].id; l.sink.index = kp;
	l.flags = on ? MEDIA_LNK_FL_ENABLED : 0;
	if (ioctl(mfd, MEDIA_IOC_SETUP_LINK, &l)) {
		/* an immutable link only "changes" to its own flags */
		l.flags |= MEDIA_LNK_FL_IMMUTABLE;
		if (ioctl(mfd, MEDIA_IOC_SETUP_LINK, &l))
			die("link %s:%d -> %s:%d", ents[src].name, sp, ents[snk].name, kp);
	}
}

/* Set a pad's format; returns what the subdev made of it */
static struct mbus_fmt fmt(int fd, int pad, unsigned code, unsigned w, unsigned h, const char *what)
{
	struct subdev_format f;
	memset(&f, 0, sizeof(f));
	f.which = V4L2_SUBDEV_FORMAT_ACTIVE; f.pad = pad;
	f.format.code = code; f.format.width = w; f.format.height = h; f.format.field = V4L2_FIELD_NONE;
	if (ioctl(fd, VIDIOC_SUBDEV_S_FMT, &f))
		die("S_FMT %s", what);
	printf("%s pad %d: %ux%u code %04x\n", what, pad, f.format.width, f.format.height, f.format.code);
	return f.format;
}

int main(int argc, char **argv)
{
	int frames = argc > 1 ? atoi(argv[1]) : 300;
	unsigned w = argc > 3 ? atoi(argv[2]) : 640, h = argc > 3 ? atoi(argv[3]) : 480;
	unsigned sw = argc > 5 ? atoi(argv[4]) : 1776, sh = argc > 5 ? atoi(argv[5]) : 1008;
	int prvout = argc > 6 && !strcmp(argv[6], "prv");

	mfd = open("/dev/media0", O_RDWR);
	if (mfd < 0)
		die("media0");
	for (nents = 0; nents < MAXE; nents++) {
		memset(&ents[nents], 0, sizeof(ents[0]));
		ents[nents].id = nents + 1;	/* as Harmattan's camera source: ids 1..N */
		if (ioctl(mfd, MEDIA_IOC_ENUM_ENTITIES, &ents[nents]))
			break;
	}
	printf("%d entities\n", nents);

	/* Every link that isn't immutable off, as libgstcamera2's mc_reset_links */
	for (int i = 0; i < nents; i++) {
		struct media_pad_desc pads[16];
		struct media_link_desc links[32];
		struct media_links_enum le = { .entity = ents[i].id, .pads = pads, .links = links };
		if (ioctl(mfd, MEDIA_IOC_ENUM_LINKS, &le))
			die("enum links %s", ents[i].name);
		for (int k = 0; k < ents[i].links; k++)
			if ((links[k].flags & MEDIA_LNK_FL_ENABLED) && !(links[k].flags & MEDIA_LNK_FL_IMMUTABLE)) {
				struct media_link_desc l = links[k];
				l.flags = 0;
				if (ioctl(mfd, MEDIA_IOC_SETUP_LINK, &l))
					die("reset link");
			}
	}

	/* ISPCAP_FRONT=1: the front camera, through CCP2 (sensor size 576 432) */
	int front = getenv("ISPCAP_FRONT") != NULL;
	/*
	 * ISPCAP_M2M=file: a raw SGRBG10 frame (sensor-width x sensor-height) from the file, through
	 * the CCP2 receiver's memory input, CCDC, preview and resizer: Harmattan's still processing
	 */
	const char *m2m = getenv("ISPCAP_M2M");
	int sen = ent(m2m ? "OMAP3 ISP CCP2 input" : front ? "tcm8500md" : "smiapp"),
	    csi = ent(m2m || front ? "OMAP3 ISP CCP2" : "OMAP3 ISP CSI2a"), ccdc = ent("OMAP3 ISP CCDC");
	int prv = ent("OMAP3 ISP preview"), rsz = ent("OMAP3 ISP resizer"), out = ent("OMAP3 ISP resizer output");
	/* ISPCAP_RAW=1: the sensor's raw frames straight to memory, as Harmattan's still capture */
	int raw = getenv("ISPCAP_RAW") != NULL;
	link_(sen, 0, csi, 0, 1);
	if (raw) {
		int rout = ent("OMAP3 ISP CSI2a output");
		link_(csi, 1, rout, 0, 1);
		int fs = node(sen), fc = node(csi);
		struct mbus_fmt rf = fmt(fs, 0, getenv("ISPCAP_DPCM") ? 0x3009 : V4L2_MBUS_FMT_SGRBG10_1X10,
					 sw, sh, ents[sen].name);
		rf = fmt(fc, 0, rf.code, rf.width, rf.height, "csi2 sink");
		/* ISPCAP_DPCM=2: decompressed by CSI2 to raw10 in memory */
		rf = fmt(fc, 1, getenv("ISPCAP_DPCM") && atoi(getenv("ISPCAP_DPCM")) == 2 ?
			 V4L2_MBUS_FMT_SGRBG10_1X10 : rf.code, rf.width, rf.height, "csi2 source");
		w = rf.width;
		h = rf.height;
		out = rout;
		goto video;
	}
	link_(csi, 1, ccdc, 0, 1);
	link_(ccdc, 2, prv, 0, 1);
	if (prvout) {
		out = ent("OMAP3 ISP preview output");
		link_(prv, 1, out, 0, 1);
	} else {
		link_(prv, 1, rsz, 0, 1);
		link_(rsz, 1, out, 0, 1);
	}

	int fsen = node(sen), fcsi = node(csi), fccdc = node(ccdc), fprv = node(prv), frsz = node(rsz);
	/* Each sink takes what the source before it gives (as libgstcamera2's link helper) */
	/* ISPCAP_DPCM=1: the sensor's DPCM8 modes (the 8 Mpixel ones), decompressed by CSI2 */
	struct mbus_fmt f = { .width = sw, .height = sh, .code = V4L2_MBUS_FMT_SGRBG10_1X10 };
	if (!m2m)
		f = fmt(fsen, 0, getenv("ISPCAP_DPCM") ? 0x3009 /* SGRBG10_DPCM8_1X8 */ :
			V4L2_MBUS_FMT_SGRBG10_1X10, sw, sh, ents[sen].name);
	if (m2m && getenv("ISPCAP_DPCM"))
		f.code = 0x3009;	/* SGRBG10_DPCM8_1X8 */
	f = fmt(fcsi, 0, f.code, f.width, f.height, m2m || front ? "ccp2 sink" : "csi2 sink");
	f = fmt(fcsi, 1, V4L2_MBUS_FMT_SGRBG10_1X10, f.width, f.height,
		m2m || front ? "ccp2 source" : "csi2 source");
	f = fmt(fccdc, 0, f.code, f.width, f.height, "ccdc sink");
	f = fmt(fccdc, 2, f.code, f.width, f.height, "ccdc vp");
	f = fmt(fprv, 0, f.code, f.width, f.height, "preview sink");
	f = fmt(fprv, 1, V4L2_MBUS_FMT_UYVY8_1X16, f.width, f.height, "preview source");
	if (prvout) {
		w = f.width;
		h = f.height;
	} else {
		f = fmt(frsz, 0, f.code, f.width, f.height, "resizer sink");
		fmt(frsz, 1, V4L2_MBUS_FMT_UYVY8_1X16, w, h, "resizer source");
	}

video:;
	int vfd = node(out);
	struct v4l2_format vf;
	memset(&vf, 0, sizeof(vf));
	vf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	vf.fmt.pix.width = w; vf.fmt.pix.height = h;
	vf.fmt.pix.pixelformat = raw ? (getenv("ISPCAP_DPCM") && atoi(getenv("ISPCAP_DPCM")) == 1 ?
					v4l2_fourcc('B', 'D', '1', '0') :
					v4l2_fourcc('B', 'A', '1', '0')) : V4L2_PIX_FMT_UYVY;
	vf.fmt.pix.field = V4L2_FIELD_NONE;
	if (ioctl(vfd, VIDIOC_S_FMT, &vf))
		die("video S_FMT");
	printf("video: %ux%u bpl %u size %u\n", vf.fmt.pix.width, vf.fmt.pix.height,
	       vf.fmt.pix.bytesperline, vf.fmt.pix.sizeimage);

	struct v4l2_requestbuffers rb = { .count = 4, .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP };
	if (ioctl(vfd, VIDIOC_REQBUFS, &rb))
		die("REQBUFS");
	void *mem[8];
	for (unsigned i = 0; i < rb.count && i < 8; i++) {
		struct v4l2_buffer b = { .index = i, .type = rb.type, .memory = rb.memory };
		if (ioctl(vfd, VIDIOC_QUERYBUF, &b) ||
		    (mem[i] = mmap(NULL, b.length, PROT_READ | PROT_WRITE, MAP_SHARED, vfd,
				   b.m.offset)) == MAP_FAILED ||
		    ioctl(vfd, VIDIOC_QBUF, &b))
			die("buffer %u", i);
	}
	int type = V4L2_BUF_TYPE_VIDEO_CAPTURE, otype = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	struct v4l2_buffer ib = { .index = 0, .type = otype, .memory = V4L2_MEMORY_MMAP };
	if (m2m) {
		struct v4l2_format ivf = { .type = otype };
		ivf.fmt.pix.width = sw; ivf.fmt.pix.height = sh;
		/* with ISPCAP_DPCM: a DPCM8 file (width bytes a line), decompressed by CCP2 */
		ivf.fmt.pix.pixelformat = getenv("ISPCAP_DPCM") ? v4l2_fourcc('B', 'D', '1', '0') :
					  v4l2_fourcc('B', 'A', '1', '0');
		ivf.fmt.pix.field = V4L2_FIELD_NONE;
		struct v4l2_requestbuffers irb = { .count = 1, .type = otype, .memory = V4L2_MEMORY_MMAP };
		void *imem;
		FILE *rf = fopen(m2m, "rb");
		if (!rf || ioctl(fsen, VIDIOC_S_FMT, &ivf) || ioctl(fsen, VIDIOC_REQBUFS, &irb) ||
		    ioctl(fsen, VIDIOC_QUERYBUF, &ib) ||
		    (imem = mmap(NULL, ib.length, PROT_READ | PROT_WRITE, MAP_SHARED, fsen,
				 ib.m.offset)) == MAP_FAILED)
			die("input");
		size_t got = 0;
		if (getenv("ISPCAP_DPCM"))
			for (unsigned y = 0; y < ivf.fmt.pix.height; y++)
				got += fread((char *)imem + y * ivf.fmt.pix.bytesperline, 1, sw, rf);
		else
			got = fread(imem, 1, ivf.fmt.pix.sizeimage, rf);
		printf("input: %ux%u bpl %u size %u read %zu\n", ivf.fmt.pix.width, ivf.fmt.pix.height,
		       ivf.fmt.pix.bytesperline, ivf.fmt.pix.sizeimage, got);
		fclose(rf);
		ib.bytesused = ivf.fmt.pix.sizeimage;
		if (ioctl(fsen, VIDIOC_QBUF, &ib))
			die("input QBUF");
	}
	if (ioctl(vfd, VIDIOC_STREAMON, &type))
		die("STREAMON");
	if (m2m && ioctl(fsen, VIDIOC_STREAMON, &otype))
		die("input STREAMON");
	struct timeval t0, t1;
	gettimeofday(&t0, NULL);
	int n;
	for (n = 0; n < frames; n++) {
		struct pollfd p = { .fd = vfd, .events = POLLIN };
		if (poll(&p, 1, 3000) <= 0) {
			fprintf(stderr, "frame %d: timeout\n", n);
			break;
		}
		struct v4l2_buffer b = { .type = type, .memory = V4L2_MEMORY_MMAP };
		if (ioctl(vfd, VIDIOC_DQBUF, &b))
			die("DQBUF");
		/* ISPCAP_SAVE=file: the last frame, as captured */
		const char *save = getenv("ISPCAP_SAVE");
		FILE *f;
		if (save && n == frames - 1 && (f = fopen(save, "wb"))) {
			fwrite(mem[b.index], 1, b.bytesused, f);
			fclose(f);
		}
		if (ioctl(vfd, VIDIOC_QBUF, &b))
			die("QBUF");
		if (m2m && (ioctl(fsen, VIDIOC_DQBUF, &ib) || ioctl(fsen, VIDIOC_QBUF, &ib)))
			die("input requeue");
	}
	gettimeofday(&t1, NULL);
	double s = (t1.tv_sec - t0.tv_sec) + (t1.tv_usec - t0.tv_usec) / 1e6;
	printf("%d frames in %.2f s (%.1f fps)\n", n, s, n / s);
	ioctl(vfd, VIDIOC_STREAMOFF, &type);
	if (m2m)
		ioctl(fsen, VIDIOC_STREAMOFF, &otype);
	return 0;
}
