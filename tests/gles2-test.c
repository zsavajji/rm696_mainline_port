/*
 * 3D on the SGX under the 6.18 driver, as Harmattan's apps do it: EGL on an X window (Nokia's X
 * driver, DRI2), GLES2. Clears to blue, draws an orange triangle over the centre, reads two pixels
 * back and leaves the frame on screen for 10 s. Run in a chroot of Harmattan's rootfs with Xorg up
 * (DISPLAY=:0). Exit 0 = the pixels are right.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>

#define W 854
#define H 480

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	GLint ok;

	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok)
		printf("FAIL shader compile\n");
	return s;
}

/* Is the pixel at (x, y) about (r, g, b)? RGB565 rounds */
static int pixel_is(int x, int y, int r, int g, int b)
{
	unsigned char p[4];

	glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p);
	printf("  pixel %d,%d: %d %d %d\n", x, y, p[0], p[1], p[2]);
	return abs(p[0] - r) < 16 && abs(p[1] - g) < 16 && abs(p[2] - b) < 16;
}

int main(void)
{
	static const EGLint cfg_attrs[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 5, EGL_GREEN_SIZE, 6,
		EGL_BLUE_SIZE, 5, EGL_NONE };
	static const EGLint ctx_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	static const GLfloat tri[] = { -0.5f, -0.5f, 0.5f, -0.5f, 0.0f, 0.5f };
	Display *dpy;
	Window win;
	EGLDisplay ed;
	EGLConfig cfg;
	EGLSurface surf;
	EGLContext ctx;
	EGLint n;
	GLuint prog;
	int ok;

	dpy = XOpenDisplay(NULL);
	if (!dpy) {
		printf("FAIL XOpenDisplay\n");
		return 1;
	}
	ed = eglGetDisplay((EGLNativeDisplayType)dpy);
	if (!eglInitialize(ed, NULL, NULL) || !eglChooseConfig(ed, cfg_attrs, &cfg, 1, &n) || n < 1) {
		printf("FAIL EGL init/config: 0x%x\n", eglGetError());
		return 1;
	}

	/* The window in the X visual of the EGL config */
	{
		XSetWindowAttributes wa = { 0 };
		XVisualInfo tmpl, *vi;
		EGLint vid, bufsize;
		int nvi;

		eglGetConfigAttrib(ed, cfg, EGL_NATIVE_VISUAL_ID, &vid);
		eglGetConfigAttrib(ed, cfg, EGL_BUFFER_SIZE, &bufsize);
		tmpl.visualid = vid;
		vi = XGetVisualInfo(dpy, VisualIDMask, &tmpl, &nvi);
		if (!vi) {
			printf("FAIL no X visual 0x%x for the EGL config\n", vid);
			return 1;
		}
		printf("EGL config: %d bits, X visual 0x%x depth %d\n", bufsize, vid, vi->depth);
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
	if (surf == EGL_NO_SURFACE) {
		printf("FAIL eglCreateWindowSurface: 0x%x\n", eglGetError());
		return 1;
	}
	ctx = eglCreateContext(ed, cfg, EGL_NO_CONTEXT, ctx_attrs);
	if (ctx == EGL_NO_CONTEXT) {
		printf("FAIL eglCreateContext: 0x%x\n", eglGetError());
		return 1;
	}
	if (!eglMakeCurrent(ed, surf, surf, ctx)) {
		printf("FAIL eglMakeCurrent: 0x%x\n", eglGetError());
		return 1;
	}
	printf("EGL_VENDOR  %s\nEGL_VERSION %s\n", eglQueryString(ed, EGL_VENDOR),
	       eglQueryString(ed, EGL_VERSION));
	printf("GL_VENDOR   %s\nGL_RENDERER %s\nGL_VERSION  %s\n", glGetString(GL_VENDOR),
	       glGetString(GL_RENDERER), glGetString(GL_VERSION));

	prog = glCreateProgram();
	glAttachShader(prog, shader(GL_VERTEX_SHADER,
		"attribute vec4 p; void main() { gl_Position = p; }"));
	glAttachShader(prog, shader(GL_FRAGMENT_SHADER,
		"precision mediump float; void main() { gl_FragColor = vec4(1.0, 0.5, 0.0, 1.0); }"));
	glBindAttribLocation(prog, 0, "p");
	glLinkProgram(prog);
	glUseProgram(prog);

	glViewport(0, 0, W, H);
	glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, tri);
	glEnableVertexAttribArray(0);
	glDrawArrays(GL_TRIANGLES, 0, 3);
	glFinish();

	ok = pixel_is(W / 2, H / 2, 255, 128, 0);	/* the triangle: orange */
	ok &= pixel_is(10, 10, 0, 0, 255);		/* a corner: the blue clear */
	eglSwapBuffers(ed, surf);
	printf("%s\n", ok ? "PASSED" : "FAILED");
	sleep(10);
	return !ok;
}
