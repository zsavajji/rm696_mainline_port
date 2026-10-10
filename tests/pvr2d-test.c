/*
 * Does the SGX execute work under the 6.18 driver? Through Harmattan's own libpvr2d (as its X driver
 * uses it): a GPU fill into one buffer, a GPU copy into another, every pixel checked from the CPU;
 * then colour bars into the display class's framebuffer (/dev/fb0), for a dump to look at.
 * Run in a chroot of Harmattan's rootfs after pvrsrvkm, omaplfb and pvrsrvinit_r125. Exit 0 = pass.
 */
#include <stdio.h>
#include <string.h>
#include "pvr2d.h"

#define W 256
#define H 256
#define FILL 0xff336699u

static int fails;

#define TRY(call) do { PVR2DERROR e_ = (call); \
	if (e_ != PVR2D_OK) { printf("FAIL %s: %d\n", #call, e_); return 1; } } while (0)

/* Pixels of an ARGB8888 W x H buffer that aren't v; after one cache invalidate if some aren't */
static unsigned bad_pixels(PVR2DCONTEXTHANDLE ctx, PVR2DMEMINFO *m, unsigned v)
{
	const unsigned *p = m->pBase;
	unsigned i, n = 0;

	for (i = 0; i < W * H; i++)
		n += p[i] != v;
	if (n) {
		printf("  %u pixels differ (first 0x%08x), invalidating the CPU cache\n", n, p[0]);
		PVR2DCacheFlushDRI(ctx, PVR2D_CFLUSH_FROM_GPU, (long)m->pBase, W * H * 4);
		for (i = n = 0; i < W * H; i++)
			n += p[i] != v;
	}
	return n;
}

static void check(const char *what, unsigned bad)
{
	printf("%s %s", bad ? "FAIL" : "ok  ", what);
	if (bad)
		printf(" (%u of %u pixels wrong)", bad, W * H);
	printf("\n");
	fails += bad != 0;
}

int main(void)
{
	PVR2DDEVICEINFO dev[4];
	PVR2DCONTEXTHANDLE ctx;
	PVR2DDISPLAYINFO di;
	PVR2DMEMINFO *a, *b, *fb;
	PVR2DBLTINFO blt;
	int n, i;

	n = PVR2DEnumerateDevices(NULL);
	if (n < 1 || n > 4) {
		printf("FAIL PVR2DEnumerateDevices: %d devices\n", n);
		return 1;
	}
	PVR2DEnumerateDevices(dev);
	printf("device %lu: %s\n", dev[0].ulDevID, dev[0].szDeviceName);
	TRY(PVR2DCreateDeviceContext(dev[0].ulDevID, &ctx, 0));
	TRY(PVR2DGetDeviceInfo(ctx, &di));
	printf("display: %lux%lu stride %ld format %d\n", di.ulWidth, di.ulHeight, di.lStride, di.eFormat);

	TRY(PVR2DMemAlloc(ctx, W * H * 4, 4096, 0, &a));
	TRY(PVR2DMemAlloc(ctx, W * H * 4, 4096, 0, &b));
	printf("buffers: a at dev 0x%08lx, b at dev 0x%08lx\n", a->ui32DevAddr, b->ui32DevAddr);
	memset(a->pBase, 0, W * H * 4);
	memset(b->pBase, 0, W * H * 4);
	PVR2DCacheFlushDRI(ctx, PVR2D_CFLUSH_TO_GPU, (long)a->pBase, W * H * 4);
	PVR2DCacheFlushDRI(ctx, PVR2D_CFLUSH_TO_GPU, (long)b->pBase, W * H * 4);

	/* GPU fill of a */
	memset(&blt, 0, sizeof(blt));
	blt.CopyCode = PVR2DPATROPcopy;
	blt.Colour = FILL;
	blt.pDstMemInfo = a;
	blt.DstStride = W * 4;
	blt.DSizeX = W;
	blt.DSizeY = H;
	blt.DstFormat = PVR2D_ARGB8888;
	blt.DstSurfWidth = W;
	blt.DstSurfHeight = H;
	TRY(PVR2DBlt(ctx, &blt));
	TRY(PVR2DQueryBlitsComplete(ctx, a, 1));
	check("GPU fill", bad_pixels(ctx, a, FILL));

	/* GPU copy a -> b */
	blt.CopyCode = PVR2DROPcopy;
	blt.pDstMemInfo = b;
	blt.pSrcMemInfo = a;
	blt.SrcStride = W * 4;
	blt.SizeX = W;
	blt.SizeY = H;
	blt.SrcFormat = PVR2D_ARGB8888;
	blt.SrcSurfWidth = W;
	blt.SrcSurfHeight = H;
	TRY(PVR2DBlt(ctx, &blt));
	TRY(PVR2DQueryBlitsComplete(ctx, b, 1));
	check("GPU copy", bad_pixels(ctx, b, FILL));

	/* Colour bars into the framebuffer: red, green, blue, white, black. PVR2D's fill colour is ARGB8888
	 * whatever the target's format (the GPU converts it). */
	TRY(PVR2DGetFrameBuffer(ctx, PVR2D_FB_PRIMARY_SURFACE, &fb));
	for (i = 0; i < 5; i++) {
		static const unsigned bars[] = { 0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff, 0xff000000 };

		memset(&blt, 0, sizeof(blt));
		blt.CopyCode = PVR2DPATROPcopy;
		blt.Colour = bars[i];
		blt.pDstMemInfo = fb;
		blt.DstStride = di.lStride;
		blt.DstX = i * di.ulWidth / 5;
		blt.DSizeX = (i + 1) * di.ulWidth / 5 - blt.DstX;
		blt.DSizeY = di.ulHeight;
		blt.DstFormat = di.eFormat;
		blt.DstSurfWidth = di.ulWidth;
		blt.DstSurfHeight = di.ulHeight;
		TRY(PVR2DBlt(ctx, &blt));
	}
	/* Orientation markers: yellow at the top-left, magenta at the top-right */
	for (i = 0; i < 2; i++) {
		memset(&blt, 0, sizeof(blt));
		blt.CopyCode = PVR2DPATROPcopy;
		blt.Colour = i ? 0xffff00ff : 0xffffff00;
		blt.pDstMemInfo = fb;
		blt.DstStride = di.lStride;
		blt.DstX = i ? di.ulWidth - 80 : 0;
		blt.DSizeX = 80;
		blt.DSizeY = 80;
		blt.DstFormat = di.eFormat;
		blt.DstSurfWidth = di.ulWidth;
		blt.DstSurfHeight = di.ulHeight;
		TRY(PVR2DBlt(ctx, &blt));
	}
	TRY(PVR2DQueryBlitsComplete(ctx, fb, 1));
	printf("ok   colour bars drawn into the framebuffer, yellow square top-left, magenta top-right\n");

	PVR2DMemFree(ctx, a);
	PVR2DMemFree(ctx, b);
	PVR2DDestroyDeviceContext(ctx);
	printf("%s\n", fails ? "FAILED" : "PASSED");
	return fails != 0;
}
