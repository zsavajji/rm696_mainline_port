# tests/dsp/dspref.sh: the same DSP decodes and encodes on stock and on the test kernel, as user, through
# gst-test with the bridge ioctl logger's per-command summary (tests/ioctl-log.c, IOCTL_LOG=sum).
#   stock:       scp build/gst-test build/ioctl-log.so CLIPS n9:/tmp/;  ssh n9 sh -s < tests/dsp/dspref.sh
#   test kernel: the same files to /newroot/tmp;                   build/s.sh sh -s < tests/dsp/dspref.sh
# CLIPS: 3 s of ffmpeg's testsrc2 at 1280x720, H.264 Baseline and Main (level 3.1, 800 kb/s):
#   ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30 -t 3 -c:v libx264 -profile:v baseline \
#     -level 3.1 -pix_fmt yuv420p -b:v 800k t720b.mp4   (and -profile:v main for t720m.mp4)
# Harmattan has no videotestsrc: the encoders get the DSP decoder's frames. Writes only to /tmp.
if [ -d /newroot ]; then
	run() { chroot /newroot su - user -c "$*"; }
else
	run() { sh -c "$*"; }
fi
A=/usr/share/MProgressIndicator/themes/opengl/MainAnimation_LowNoise.mp4
t() {
	echo "== $1"
	run "IOCTL_LOG=sum LD_PRELOAD=/tmp/ioctl-log.so /tmp/gst-test '$1'" 2>&1 |
		grep -E "^EOS|buffers|error|couldn|span"
}
echo "== $(uname -r)"
for c in t720b t720m; do
	t "uridecodebin uri=file:///tmp/$c.mp4 name=d d. ! video/x-raw-yuv ! identity name=out ! fakesink sync=false"
done
t "uridecodebin uri=file://$A name=d d. ! video/x-raw-yuv ! identity name=out ! fakesink sync=false"
for e in dsphdmp4venc dsphdh264enc dspjpegenc; do
	t "uridecodebin uri=file:///tmp/t720b.mp4 name=d d. ! video/x-raw-yuv ! $e ! identity name=out ! fakesink"
done
t "uridecodebin uri=file://$A name=d d. ! video/x-raw-yuv ! dsph264enc ! identity name=out ! fakesink"
