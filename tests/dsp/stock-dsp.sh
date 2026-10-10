# Run on stock Harmattan as user (ssh n9), read-only apart from /tmp (tmpfs): the same DSP decode
# commands as on the test kernel, on Nokia's own clips. Reference results for the bridge port.
T=/tmp/gst-test
uname -r; lsmod | grep -i bridge; ls -la /dev/DspBridge
for u in /usr/share/MProgressIndicator/themes/opengl/MainAnimation_LowNoise.mp4 \
	 /usr/share/userguide/contents/images/remove_an_application_en.mp4; do
	echo "== $u"
	echo "-- uridecodebin ! identity ! fakesink sync=false"
	$T "uridecodebin uri=file://$u name=d d. ! video/x-raw-yuv ! identity name=out ! fakesink sync=false" 2>&1 | tail -4
	echo "-- filesrc ! qtdemux ! queue ! dspvdec ! identity ! fakesink"
	$T "filesrc location=$u ! qtdemux ! queue ! dspvdec ! identity name=out ! fakesink sync=false" 2>&1 | tail -4
	echo "-- playbin2 fakesinks"
	$T "playbin2 uri=file://$u video-sink=fakesink audio-sink=fakesink" 2>&1 | tail -4
done
