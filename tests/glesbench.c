/*
 * glesbench: GLES2 through Harmattan's EGL on X (DRI2, Nokia's X driver), the same binary on stock and
 * on the test kernel (tests/build.sh builds it; run as user with DISPLAY=:0, the display on and
 * unlocked). Frames per second and the CPU time of the process and of Xorg for one of:
 *   fill N     N full-screen alpha-blended quads a frame (the GPU's fill rate: equal hardware)
 *   draws N    N small triangles a frame, a glDrawArrays and a uniform each (the blob's and the
 *              kernel's per-draw cost)
 *   tex N S    N RGBA textures of SxS respecified (glTexImage2D) and drawn a frame (allocation,
 *              mapping, cache maintenance: the kernel driver's memory paths)
 *   swap       clear and swap only (the flip path)
 * glesbench MODE [N [S]] [-f FRAMES]: FRAMES (300) measured after 10 warm-up frames.
 */
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>

#define W 854
#define H 480

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec * 1e-9;
}

static double tv(struct timeval *t)
{
	return t->tv_sec + t->tv_usec * 1e-6;
}

/* utime + stime ticks of the processes whose stat line holds name, e.g. "(Xorg)" */
static long ticks_of(const char *name)
{
	DIR *d = opendir("/proc");
	struct dirent *e;
	long total = 0;

	if (!d)
		return -1;
	while ((e = readdir(d))) {
		char path[64], buf[512], *p;
		FILE *f;
		long ut, st;

		if (e->d_name[0] < '0' || e->d_name[0] > '9')
			continue;
		snprintf(path, sizeof(path), "/proc/%s/stat", e->d_name);
		f = fopen(path, "r");
		if (!f)
			continue;
		if (!fgets(buf, sizeof(buf), f)) {
			fclose(f);
			continue;
		}
		fclose(f);
		p = strrchr(buf, ')');
		if (!p || !strstr(buf, name))
			continue;
		/* after ')': state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt utime stime */
		if (sscanf(p + 1, " %*c %*d %*d %*d %*d %*d %*u %*u %*u %*u %*u %ld %ld", &ut, &st) == 2)
			total += ut + st;
	}
	closedir(d);
	return total;
}

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	GLint ok;

	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		printf("FAIL shader compile\n");
		exit(1);
	}
	return s;
}

static GLuint program(const char *fs)
{
	GLuint prog = glCreateProgram();
	GLint ok;

	glAttachShader(prog, shader(GL_VERTEX_SHADER,
		"attribute vec2 p; attribute vec2 t; uniform vec2 o; varying vec2 v;\n"
		"void main() { v = t; gl_Position = vec4(p + o, 0.0, 1.0); }"));
	glAttachShader(prog, shader(GL_FRAGMENT_SHADER, fs));
	glBindAttribLocation(prog, 0, "p");
	glBindAttribLocation(prog, 1, "t");
	glLinkProgram(prog);
	glGetProgramiv(prog, GL_LINK_STATUS, &ok);
	if (!ok) {
		printf("FAIL program link\n");
		exit(1);
	}
	return prog;
}

int main(int argc, char **argv)
{
	static const EGLint cfg_attrs[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 5, EGL_GREEN_SIZE, 6,
		EGL_BLUE_SIZE, 5, EGL_NONE };
	static const EGLint ctx_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	/* a full-screen quad (two triangles) with texture coordinates, and a small triangle */
	static const GLfloat quad[] = { -1, -1, 0, 0,  1, -1, 1, 0,  -1, 1, 0, 1,
					 1, -1, 1, 0,  1, 1, 1, 1,  -1, 1, 0, 1 };
	static const GLfloat tri[] = { -0.03f, -0.03f, 0, 0,  0.03f, -0.03f, 1, 0,  0.0f, 0.03f, 0.5f, 1 };
	const char *mode = argc > 1 ? argv[1] : "fill";
	int n = 0, size = 256, frames = 300, i, f;
	Display *dpy;
	Window win;
	EGLDisplay ed;
	EGLConfig cfg;
	EGLSurface surf;
	EGLContext ctx;
	EGLint ncfg;
	GLuint prog, *textures = NULL;
	GLint o_loc, c_loc;
	unsigned char *texdata = NULL;
	struct rusage r0, r1;
	long x0 = 0, x1;
	double t0 = 0, t1;

	for (i = 2; i < argc; i++) {
		if (!strcmp(argv[i], "-f") && i + 1 < argc)
			frames = atoi(argv[++i]);
		else if (!n)
			n = atoi(argv[i]);
		else
			size = atoi(argv[i]);
	}
	if (!n)
		n = !strcmp(mode, "fill") ? 20 : !strcmp(mode, "draws") ? 200 : 8;

	dpy = XOpenDisplay(NULL);
	if (!dpy) {
		printf("FAIL XOpenDisplay\n");
		return 1;
	}
	ed = eglGetDisplay((EGLNativeDisplayType)dpy);
	if (!eglInitialize(ed, NULL, NULL) || !eglChooseConfig(ed, cfg_attrs, &cfg, 1, &ncfg) || ncfg < 1) {
		printf("FAIL EGL init/config: 0x%x\n", eglGetError());
		return 1;
	}
	{
		XSetWindowAttributes wa = { 0 };
		XVisualInfo tmpl, *vi;
		EGLint vid;
		int nvi;

		eglGetConfigAttrib(ed, cfg, EGL_NATIVE_VISUAL_ID, &vid);
		tmpl.visualid = vid;
		vi = XGetVisualInfo(dpy, VisualIDMask, &tmpl, &nvi);
		if (!vi) {
			printf("FAIL no X visual 0x%x for the EGL config\n", vid);
			return 1;
		}
		wa.colormap = XCreateColormap(dpy, DefaultRootWindow(dpy), vi->visual, AllocNone);
		wa.event_mask = StructureNotifyMask;
		win = XCreateWindow(dpy, DefaultRootWindow(dpy), 0, 0, W, H, 0, vi->depth, InputOutput,
				    vi->visual, CWColormap | CWEventMask | CWBorderPixel, &wa);
	}
	XMapWindow(dpy, win);
	for (;;) {	/* DRI2 needs the window realized */
		XEvent e;

		XNextEvent(dpy, &e);
		if (e.type == MapNotify)
			break;
	}
	surf = eglCreateWindowSurface(ed, cfg, (EGLNativeWindowType)win, NULL);
	ctx = eglCreateContext(ed, cfg, EGL_NO_CONTEXT, ctx_attrs);
	if (surf == EGL_NO_SURFACE || ctx == EGL_NO_CONTEXT || !eglMakeCurrent(ed, surf, surf, ctx)) {
		printf("FAIL EGL surface/context: 0x%x\n", eglGetError());
		return 1;
	}
	eglSwapInterval(ed, 0);		/* unthrottled if the blob allows it */

	if (!strcmp(mode, "tex")) {
		prog = program("precision mediump float; uniform sampler2D s; varying vec2 v;\n"
			       "void main() { gl_FragColor = texture2D(s, v); }");
		textures = malloc(n * sizeof(*textures));
		glGenTextures(n, textures);
		texdata = malloc((size_t)size * size * 4);
		for (i = 0; i < size * size * 4; i++)
			texdata[i] = i;
	} else {
		prog = program("precision mediump float; uniform vec4 c; void main() { gl_FragColor = c; }");
	}
	glUseProgram(prog);
	o_loc = glGetUniformLocation(prog, "o");
	c_loc = glGetUniformLocation(prog, "c");
	glViewport(0, 0, W, H);
	glClearColor(0.1f, 0.1f, 0.2f, 1.0f);
	glEnableVertexAttribArray(0);
	glEnableVertexAttribArray(1);
	if (!strcmp(mode, "fill")) {
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	}
	glGetError();

	for (f = -10; f < frames; f++) {
		if (f == 0) {
			glFinish();
			getrusage(RUSAGE_SELF, &r0);
			x0 = ticks_of("(Xorg)");
			t0 = now();
		}
		glClear(GL_COLOR_BUFFER_BIT);
		glUniform2f(o_loc, 0, 0);
		if (!strcmp(mode, "fill")) {
			glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, quad);
			glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, quad + 2);
			for (i = 0; i < n; i++) {
				glUniform4f(c_loc, (i & 1) ? 0.9f : 0.2f, (i & 2) ? 0.8f : 0.3f, (i & 4) ? 0.7f : 0.4f, 0.5f);
				glDrawArrays(GL_TRIANGLES, 0, 6);
			}
		} else if (!strcmp(mode, "draws")) {
			glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, tri);
			glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, tri + 2);
			glUniform4f(c_loc, 1.0f, 0.5f, 0.0f, 1.0f);
			for (i = 0; i < n; i++) {
				glUniform2f(o_loc, -0.95f + 1.9f * (i % 20) / 20.0f, -0.95f + 1.9f * ((i / 20) % 20) / 20.0f);
				glDrawArrays(GL_TRIANGLES, 0, 3);
			}
		} else if (!strcmp(mode, "tex")) {
			glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, quad);
			glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, quad + 2);
			for (i = 0; i < n; i++) {
				texdata[0] = f + i;	/* a changed byte: a real upload each frame */
				glBindTexture(GL_TEXTURE_2D, textures[i]);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
				glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, size, size, 0, GL_RGBA, GL_UNSIGNED_BYTE, texdata);
				/* each texture on its own small quad: little fill, the upload is the work */
				glViewport((i % 8) * (W / 8), ((i / 8) % 4) * (H / 4), W / 8, H / 4);
				glDrawArrays(GL_TRIANGLES, 0, 6);
			}
			glViewport(0, 0, W, H);
		}
		eglSwapBuffers(ed, surf);
	}
	glFinish();
	t1 = now();
	getrusage(RUSAGE_SELF, &r1);
	x1 = ticks_of("(Xorg)");
	if (glGetError() != GL_NO_ERROR)
		printf("GL error during the run\n");
	printf("glesbench %s %d %d: %d frames in %.2f s = %.1f fps, %.2f ms/frame; cpu user %.2f s, sys %.2f s "
	       "(%.0f%% of wall); Xorg +%ld ticks (%.0f%% at 128 Hz); faults %ld (%.1f a frame), "
	       "switches %ld voluntary %ld involuntary\n", mode, n, size, frames, t1 - t0,
	       frames / (t1 - t0), 1000 * (t1 - t0) / frames,
	       tv(&r1.ru_utime) - tv(&r0.ru_utime), tv(&r1.ru_stime) - tv(&r0.ru_stime),
	       100 * (tv(&r1.ru_utime) - tv(&r0.ru_utime) + tv(&r1.ru_stime) - tv(&r0.ru_stime)) / (t1 - t0),
	       x1 - x0, 100.0 * (x1 - x0) / 128 / (t1 - t0),
	       r1.ru_minflt - r0.ru_minflt, (double)(r1.ru_minflt - r0.ru_minflt) / frames,
	       r1.ru_nvcsw - r0.ru_nvcsw, r1.ru_nivcsw - r0.ru_nivcsw);
	return 0;
}
