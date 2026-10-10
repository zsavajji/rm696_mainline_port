/*
 * gst-test: run a GStreamer 0.10 pipeline on Harmattan (it ships no gst-launch), for the DSP
 * (gst-dsp). Prints the bus's errors and warnings, the time to EOS and the buffers through an element
 * named "out" (an identity before the sink) and into every fakesink (also playbin2's), e.g.
 *   gst-test 'videotestsrc num-buffers=300 ! video/x-raw-yuv,format=(fourcc)UYVY,width=640,height=480,framerate=30/1 ! dsph264enc ! identity name=out ! fakesink'
 */
#include <gst/gst.h>
#include <stdio.h>
#include <string.h>

static guint buffers, sink_buffers[8];
static GstElement *sinks[8];
static int nsinks;

static gboolean count(GstPad *pad, GstBuffer *buf, gpointer data)
{
	(*(guint *)data)++;
	return TRUE;
}

/* fakesinks show up as playbin2/uridecodebin build their chains: count into each */
static void added(GstBin *bin, GstElement *e, gpointer data)
{
	GstElementFactory *f = gst_element_get_factory(e);

	if (GST_IS_BIN(e))
		g_signal_connect(e, "element-added", G_CALLBACK(added), NULL);
	if (f && !strcmp(GST_PLUGIN_FEATURE_NAME(f), "fakesink") && nsinks < 8) {
		GstPad *pad = gst_element_get_static_pad(e, "sink");

		sinks[nsinks] = e;
		gst_pad_add_buffer_probe(pad, G_CALLBACK(count), &sink_buffers[nsinks++]);
		gst_object_unref(pad);
	}
}

static void print_sinks(void)
{
	int i;

	for (i = 0; i < nsinks; i++)
		printf("  %s: %u buffers\n", GST_OBJECT_NAME(sinks[i]), sink_buffers[i]);
}

int main(int argc, char **argv)
{
	GstElement *pipeline, *out;
	GError *err = NULL;
	GstBus *bus;
	GTimer *timer;
	int ret = 1;

	gst_init(&argc, &argv);
	if (argc != 2)
		return fprintf(stderr, "usage: gst-test 'PIPELINE'\n"), 2;
	pipeline = gst_parse_launch(argv[1], &err);
	if (!pipeline)
		return fprintf(stderr, "parse: %s\n", err->message), 2;
	out = gst_bin_get_by_name(GST_BIN(pipeline), "out");
	if (out) {
		GstPad *pad = gst_element_get_static_pad(out, "src");

		gst_pad_add_buffer_probe(pad, G_CALLBACK(count), &buffers);
	}
	if (GST_IS_BIN(pipeline)) {
		GstIterator *it = gst_bin_iterate_recurse(GST_BIN(pipeline));
		gpointer e;

		g_signal_connect(pipeline, "element-added", G_CALLBACK(added), NULL);
		while (gst_iterator_next(it, &e) == GST_ITERATOR_OK) {
			added(NULL, e, NULL);
			gst_object_unref(e);
		}
		gst_iterator_free(it);
	}
	bus = gst_element_get_bus(pipeline);
	timer = g_timer_new();
	gst_element_set_state(pipeline, GST_STATE_PLAYING);
	for (;;) {
		GstMessage *msg = gst_bus_timed_pop(bus, 60 * GST_SECOND);
		gchar *dbg = NULL;

		if (!msg) {
			printf("timeout after %.1f s, %u buffers\n", g_timer_elapsed(timer, NULL), buffers);
			print_sinks();
			break;
		}
		switch (GST_MESSAGE_TYPE(msg)) {
		case GST_MESSAGE_ERROR:
			gst_message_parse_error(msg, &err, &dbg);
			printf("error from %s: %s (%s)\n", GST_OBJECT_NAME(msg->src), err->message,
			       dbg ? dbg : "");
			gst_message_unref(msg);
			goto done;
		case GST_MESSAGE_WARNING:
			gst_message_parse_warning(msg, &err, &dbg);
			printf("warning from %s: %s (%s)\n", GST_OBJECT_NAME(msg->src), err->message,
			       dbg ? dbg : "");
			break;
		case GST_MESSAGE_EOS:
			printf("EOS after %.2f s, %u buffers\n", g_timer_elapsed(timer, NULL), buffers);
			print_sinks();
			ret = 0;
			gst_message_unref(msg);
			goto done;
		default:
			break;
		}
		g_free(dbg);
		gst_message_unref(msg);
	}
done:
	gst_element_set_state(pipeline, GST_STATE_NULL);
	return ret;
}
