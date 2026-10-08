/* qyshot-capture.c — 纯 X11 屏幕截图辅助程序
 * 用 XGetImage 抓取根窗口，输出 24-bit BMP（gdk-pixbuf 可直接加载）。
 * 用法: qyshot-capture <输出.bmp> [宽度x高度]   (省略则全屏)
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int write_bmp(const char *path, XImage *img, int w, int h) {
    FILE *f = fopen(path, "wb");
    if (!f) return 0;
    int row_size = (w * 3 + 3) & ~3;      /* 每行 4 字节对齐 */
    int data_size = row_size * h;
    int file_size = 54 + data_size;
    /* BITMAPFILEHEADER (14) */
    unsigned char hdr[14] = { 'B', 'M', 0,0,0,0, 0,0, 0,0, 54,0,0,0 };
    hdr[2] = file_size & 0xff; hdr[3] = (file_size >> 8) & 0xff;
    hdr[4] = (file_size >> 16) & 0xff; hdr[5] = (file_size >> 24) & 0xff;
    fwrite(hdr, 1, 14, f);
    /* BITMAPINFOHEADER (40) */
    unsigned char ih[40] = { 0 };
    ih[0] = 40;
    ih[4] = w & 0xff; ih[5] = (w >> 8) & 0xff; ih[6] = (w >> 16) & 0xff; ih[7] = (w >> 24) & 0xff;
    ih[8] = h & 0xff; ih[9] = (h >> 8) & 0xff; ih[10] = (h >> 16) & 0xff; ih[11] = (h >> 24) & 0xff;
    ih[12] = 1;  /* planes */
    ih[14] = 24; /* bpp */
    ih[20] = data_size & 0xff; ih[21] = (data_size >> 8) & 0xff;
    ih[22] = (data_size >> 16) & 0xff; ih[23] = (data_size >> 24) & 0xff;
    fwrite(ih, 1, 40, f);
    /* 像素数据: 自底向上, BGR */
    unsigned char *rowbuf = malloc(row_size);
    if (!rowbuf) { fclose(f); return 0; }
    for (int y = h - 1; y >= 0; y--) {
        memset(rowbuf, 0, row_size);
        for (int x = 0; x < w; x++) {
            unsigned long px = XGetPixel(img, x, y);
            rowbuf[x * 3]     = px & 0xff;            /* B */
            rowbuf[x * 3 + 1] = (px >> 8) & 0xff;     /* G */
            rowbuf[x * 3 + 2] = (px >> 16) & 0xff;    /* R */
        }
        fwrite(rowbuf, 1, row_size, f);
    }
    free(rowbuf);
    fclose(f);
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: qyshot-capture <out.bmp> [WxH]\n");
        return 1;
    }
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "qyshot-capture: cannot open display\n");
        return 1;
    }
    int scr = DefaultScreen(dpy);
    int w = DisplayWidth(dpy, scr);
    int h = DisplayHeight(dpy, scr);
    if (argc >= 3) {
        unsigned long ww = strtoul(argv[2], NULL, 10);
        const char *x = strchr(argv[2], 'x');
        unsigned long hh = x ? strtoul(x + 1, NULL, 10) : 0;
        if (ww > 0 && ww < 20000) w = (int)ww;
        if (hh > 0 && hh < 20000) h = (int)hh;
    }
    Window root = DefaultRootWindow(dpy);
    XImage *img = XGetImage(dpy, root, 0, 0, w, h, AllPlanes, ZPixmap);
    if (!img) {
        fprintf(stderr, "qyshot-capture: XGetImage failed\n");
        XCloseDisplay(dpy);
        return 1;
    }
    int ok = write_bmp(argv[1], img, w, h);
    XDestroyImage(img);
    XCloseDisplay(dpy);
    fprintf(stderr, "qyshot-capture: %s %dx%d %s\n", argv[1], w, h, ok ? "OK" : "FAIL");
    return ok ? 0 : 1;
}