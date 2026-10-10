/*
 * The N9's WLAN calibration to stdout: CAL's "wlan-nvs-t1", as Harmattan's wl1271-cal reads it with
 * libcal. Nokia's wl12xx took it by an nl80211 testmode push; mainline wlcore loads it at probe from
 * ti-connectivity/wl1271-nvs.bin, and takes the MAC address from it. Run from the wl1271-cal job
 * before the driver loads (ramboot/harmattan.patch). Exit 0 = a wl127x-sized block (912 bytes).
 */
#include <stdio.h>

struct cal;
/* libcal.so.1 (no header in the SDK): the calls wl1271-cal makes */
int cal_init_ro(struct cal **cal);
int cal_read_block(struct cal *cal, const char *name, void **data, unsigned long *len,
		   unsigned long flags);
void cal_finish(struct cal *cal);

int main(void)
{
	struct cal *cal;
	void *data;
	unsigned long len;

	if (cal_init_ro(&cal) < 0) {
		fprintf(stderr, "wlan-nvs: no CAL\n");
		return 1;
	}
	if (cal_read_block(cal, "wlan-nvs-t1", &data, &len, 0) < 0) {
		fprintf(stderr, "wlan-nvs: no wlan-nvs-t1 in CAL\n");
		cal_finish(cal);
		return 1;
	}
	fwrite(data, 1, len, stdout);
	cal_finish(cal);
	if (len != 912) {
		fprintf(stderr, "wlan-nvs: %lu bytes, not a wl127x NVS (912)\n", len);
		return 1;
	}
	return 0;
}
