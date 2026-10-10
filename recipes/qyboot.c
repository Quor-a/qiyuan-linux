/*
 * qyboot.c — 澜岫开机动画 v2（品牌重新美术）
 * 直接写 /dev/fb0 (DRM fbdev emulation 提供)：
 *   深蓝渐变背景 + 品牌动画（白色山脊浮现 / 橙色涟漪扩散 / 橙色三角上升）
 *   + 底部橙色增长进度条
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

/* 画圆环（用于涟漪） */
static void circle(int cx, int cy, int rad, int th, uint8_t r, uint8_t g, uint8_t b)
{
    if (rad < 0) return;
    int r1 = rad - th, r2 = rad + th;
    for (int y = -r2; y <= r2; y++)
        for (int x = -r2; x <= r2; x++) {
            int d = x * x + y * y;
            if (d >= r1 * r1 && d <= r2 * r2)
                px(cx + x, cy + y, r, g, b);
        }
}

/* 画粗线 */
static void line(int x0, int y0, int x1, int y1, int w, uint8_t r, uint8_t g, uint8_t b)
{
    int dx = x1 - x0, dy = y1 - y0;
    int steps = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
    if (steps == 0) steps = 1;
    for (int i = 0; i <= steps; i++) {
        int x = x0 + dx * i / steps;
        int y = y0 + dy * i / steps;
        for (int j = -w / 2; j <= w / 2; j++) {
            px(x + j, y, r, g, b);
            px(x, y + j, r, g, b);
        }
    }
}

/*
 * 品牌 Logo「澜岫」：白色山脊（岫）+ 橙色涟漪（澜）+ 橙色上升三角（自由）
 * t: 0.0 ~ 1.0 动画进度
 */
static void draw_logo(int cx, int cy, int s, float t)
{
    int base = cy + s / 3;
    /* 山脊：随 t 从下向上浮现（顶点高度随 t 增长） */
    int peak = base - (int)(s * 0.9 * t);
    int left = cx - s, right = cx + s;
    line(left, base, cx - s / 3, peak, 3, 230, 233, 239);
    line(cx - s / 3, peak, cx + s / 3, base - s / 5, 3, 230, 233, 239);
    line(cx + s / 3, base - s / 5, right, base, 3, 230, 233, 239);
    /* 涟漪：两道橙色圆环从 logo 中心扩散（半径随 t） */
    int cyr = base - s / 2;
    int r1 = (int)(s * 0.10 + s * 0.95 * t);
    int r2 = (int)(s * 0.03 + s * 0.70 * t);
    circle(cx, cyr, r1, 2, 233, 84, 32);
    circle(cx, cyr, r2, 2, 233, 84, 32);
    /* 上升三角：从山脊处向上移动（y 随 t 减小） */
    int ty = (int)(base - s * 0.35 * t) - (int)(s * 0.3 * t);
    line(cx, ty - s / 2, cx - s / 3, ty + s / 3, 3, 233, 84, 32);
    line(cx - s / 3, ty + s / 3, cx + s / 3, ty + s / 3, 3, 233, 84, 32);
    line(cx + s / 3, ty + s / 3, cx, ty - s / 2, 3, 233, 84, 32);
}

int main(void)
{
    signal(SIGTERM, on_term);
    signal(SIGINT, on_term);
    fb_open();

    int cx = W / 2, cy = H / 2 - H / 14;
    int s = H / 5;

    /* 底部品牌小字条装饰线 */
    int by = H * 4 / 5;
    int bx0 = W / 4, bx1 = W * 3 / 4, byy = H * 7 / 8, bth = H / 90 + 2;

    int f = 0;
    struct timespec ts = {0, 30 * 1000 * 1000}; /* 30ms ≈ 33fps */
    while (!g_stop) {
        float t = (float)(f % 150) / 150.0f;   /* 约 4.5 秒循环 */

        /* 背景：深蓝渐变（每帧重绘，动画元素在其上） */
        for (int y = 0; y < H; y++) {
            float k = (float)y / H;
            uint8_t r = (uint8_t)(10 + 15 * k);
            uint8_t g = (uint8_t)(16 + 25 * k);
            uint8_t b = (uint8_t)(36 + 40 * k);
            for (int x = 0; x < W; x++)
                px(x, y, r, g, b);
        }

        /* 品牌 logo 动画 */
        draw_logo(cx, cy, s, t);

        /* 底部品牌装饰线 */
        rect(W / 2 - W / 8, by, W / 2 + W / 8, by + 2, 120, 140, 170);

        /* 进度条：随 t 增长（0→100%），橙色 */
        rect(bx0 - 2, byy - 2, bx1 + 2, byy + bth + 2, 60, 80, 110); /* 外框 */
        rect(bx0, byy, bx1, byy + bth, 25, 35, 55);                 /* 底槽 */
        int p = bx0 + (int)((bx1 - bx0) * t);
        if (p > bx0) rect(bx0, byy, p, byy + bth, 233, 84, 32);     /* 橙色增长条 */

        nanosleep(&ts, NULL);
        f++;
    }

    /* 淡出: 40 帧叠加变黑 */
    for (int d = 0; d < 40; d++) {
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