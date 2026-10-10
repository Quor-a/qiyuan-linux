/*
 * qyboot.c — 澜岫开机动画
 * 直接写 /dev/fb0 (DRM fbdev emulation 提供)：深蓝渐变背景 + 澜岫 Logo 圆角块 + 进度条
 * 由 qyinit 最先启动 (qyboot.unit)，qydesktop 起来后向其发 SIGTERM，动画淡出退出
 * gcc --sysroot=<sysroot> qyboot.c -o qyboot -O2
 */
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>
#include <time.h>

static volatile sig_atomic_t g_stop = 0;
static void on_term(int s) { (void)s; g_stop = 1; }

static uint32_t *g_fb;
static int g_fd = -1;
static int W, H, LW;
static struct fb_var_screeninfo g_vi;

static void fb_open(void)
{
    g_fd = open("/dev/fb0", O_RDWR);
    if (g_fd < 0) _exit(0);
    if (ioctl(g_fd, FBIOGET_VSCREENINFO, &g_vi) < 0) _exit(0);
    struct fb_fix_screeninfo fi;
    ioctl(g_fd, FBIOGET_FSCREENINFO, &fi);
    W = g_vi.xres; H = g_vi.yres; LW = fi.line_length / 4;
    size_t sz = (size_t)fi.line_length * g_vi.yres;
    g_fb = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, g_fd, 0);
    if (g_fb == MAP_FAILED) _exit(0);
}

static inline void px(int x, int y, uint8_t r, uint8_t g, uint8_t b)
{
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    uint32_t o = (uint32_t)y * LW + x;
    g_fb[o] = (uint32_t)r << g_vi.red.offset |
              (uint32_t)g << g_vi.green.offset |
              (uint32_t)b << g_vi.blue.offset;
}

static void rect(int x0, int y0, int x1, int y1, uint8_t r, uint8_t g, uint8_t b)
{
    for (int y = y0; y <= y1; y++)
        for (int x = x0; x <= x1; x++)
            px(x, y, r, g, b);
}

/* 简化: 用几何图形画 "启" 的象形 — 外框 + 内横竖 */
static void draw_logo(int cx, int cy, int s)
{
    int h = s / 2;
    /* 圆角方块 Logo (青蓝渐变) */
    for (int y = -h; y <= h; y++)
        for (int x = -h; x <= h; x++) {
            int d = x * x + y * y;
            if (d <= h * h) {
                float t = (float)(y + h) / (2 * h);
                px(cx + x, cy + y,
                   (uint8_t)(30 + 20 * t),
                   (uint8_t)(90 + 60 * t),
                   (uint8_t)(160 + 60 * t));
            }
        }
    /* 白色 "启" 简化图形: 门框 + 口 */
    int bw = s / 10;
    /* 左竖 右竖 上横 下横 */
    rect(cx - s/3, cy - s/3, cx - s/3 + bw, cy + s/3, 255, 255, 255);
    rect(cx + s/3 - bw, cy - s/3, cx + s/3, cy + s/3, 255, 255, 255);
    rect(cx - s/3, cy - s/3, cx + s/3, cy - s/3 + bw, 255, 255, 255);
    /* 内部 "口" */
    rect(cx - s/8, cy - s/12, cx + s/8, cy + s/12, 255, 255, 255);
}

int main(void)
{
    signal(SIGTERM, on_term);
    signal(SIGINT, on_term);
    fb_open();

    /* 背景: 深蓝渐变 */
    for (int y = 0; y < H; y++) {
        float t = (float)y / H;
        uint8_t r = (uint8_t)(10 + 15 * t);
        uint8_t g = (uint8_t)(16 + 25 * t);
        uint8_t b = (uint8_t)(36 + 40 * t);
        for (int x = 0; x < W; x++)
            px(x, y, r, g, b);
    }
    draw_logo(W / 2, H / 2 - H / 12, H / 5);

    /* 底部小字条: "LANXIU Linux" 简化为横线装饰 */
    int by = H * 4 / 5;
    rect(W/2 - W/8, by, W/2 + W/8, by + 2, 120, 140, 170);

    /* 进度条动画 (底 1/4 处), 收到 SIGTERM 后快速填满并淡出 */
    int bx0 = W / 4, bx1 = W * 3 / 4, byy = H * 7 / 8, bth = H / 90 + 2;
    rect(bx0 - 2, byy - 2, bx1 + 2, byy + bth + 2, 60, 80, 110);      /* 外框 */
    rect(bx0, byy, bx1, byy + bth, 25, 35, 55);                        /* 底槽 */

    int pos = bx0;
    int dir = 1;
    struct timespec ts = {0, 30 * 1000 * 1000}; /* 30ms */
    while (!g_stop) {
        /* 来回滑块 */
        rect(bx0, byy, bx1, byy + bth, 25, 35, 55);
        rect(pos, byy, pos + W / 40, byy + bth, 70, 150, 230);
        pos += dir * (W / 200);
        if (pos + W / 40 >= bx1) dir = -1;
        if (pos <= bx0) dir = 1;
        nanosleep(&ts, NULL);
    }

    /* 淡出: 40 帧叠加变黑 */
    for (int f = 0; f < 40; f++) {
        for (int y = 0; y < H; y += 1)
            for (int x = 0; x < W; x += 2) {
                uint32_t o = (uint32_t)y * LW + x;
                uint32_t v = g_fb[o];
                uint32_t r = (v >> g_vi.red.offset) & 0xff;
                uint32_t g = (v >> g_vi.green.offset) & 0xff;
                uint32_t b = (v >> g_vi.blue.offset) & 0xff;
                r = r * 19 / 20; g = g * 19 / 20; b = b * 19 / 20;
                g_fb[o] = r << g_vi.red.offset | g << g_vi.green.offset | b << g_vi.blue.offset;
            }
        nanosleep(&ts, NULL);
    }
    return 0;
}
