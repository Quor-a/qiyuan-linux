/* qysw-x11.c — 窗口切换器 X11 辅助程序
 * 用法:
 *   qysw-x11          枚举根窗口子窗口, 输出 "id|name" 每行
 *   qysw-x11 -a <id>  激活指定窗口 (XRaiseWindow + XSetInputFocus)
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void list_windows(Display *dpy) {
    Window root = DefaultRootWindow(dpy);
    Window root_ret, parent_ret;
    Window *children = NULL;
    unsigned int n = 0;
    if (XQueryTree(dpy, root, &root_ret, &parent_ret, &children, &n) && children) {
        for (unsigned int i = 0; i < n; i++) {
            char *name = NULL;
            if (XFetchName(dpy, children[i], &name) && name) {
                printf("0x%lx|%s\n", (unsigned long)children[i], name);
                XFree(name);
            }
        }
        XFree(children);
    }
}

static void activate_window(Display *dpy, unsigned long id) {
    Window w = (Window)id;
    XRaiseWindow(dpy, w);
    XSetInputFocus(dpy, w, RevertToParent, CurrentTime);
    XMapRaised(dpy, w);
    XFlush(dpy);
}

int main(int argc, char **argv) {
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "qysw-x11: cannot open display\n");
        return 1;
    }
    if (argc >= 3 && strcmp(argv[1], "-a") == 0) {
        activate_window(dpy, strtoul(argv[2], NULL, 0));
    } else {
        list_windows(dpy);
    }
    XCloseDisplay(dpy);
    return 0;
}