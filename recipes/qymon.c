/* qymon — 启元系统监视器 v1
 * 数据源: /proc/stat (CPU), /proc/meminfo (内存), /proc/loadavg, /proc/uptime
 * UI: GTK3 + GtkDrawingArea 实时曲线 (cairo), 1s 定时刷新
 * 架构: 单文件, 与 qyfiles 同款编译方式 (gcc + pkg-config gtk+-3.0)
 */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define NHIST 120   /* 曲线历史点数 */

static double cpu_hist[NHIST];  /* 0..1 */
static double mem_hist[NHIST];  /* 0..1 */
static int hist_n = 0;
static char line_buf[256];
static long prev_total = 0, prev_idle = 0;
static unsigned long mem_total_kb = 1;

static gboolean tick(gpointer ud) {
    /* --- CPU: /proc/stat 首行 cpu  user nice system idle iowait irq softirq steal --- */
    FILE *f = fopen("/proc/stat", "r");
    if (f) {
        long u, n, s, idle, iow, irq, sirq, steal, total;
        if (fscanf(f, "cpu %ld %ld %ld %ld %ld %ld %ld %ld",
                   &u, &n, &s, &idle, &iow, &irq, &sirq, &steal) == 8) {
            total = u + n + s + idle + iow + irq + sirq + steal;
            long dtotal = total - prev_total;
            long didle = (idle + iow) - prev_idle;
            double usage = dtotal > 0 ? 1.0 - (double)didle / (double)dtotal : 0.0;
            if (usage < 0) usage = 0; if (usage > 1) usage = 1;
            prev_total = total; prev_idle = idle + iow;
            if (hist_n < NHIST) {
                cpu_hist[hist_n] = usage; mem_hist[hist_n] = -1; hist_n++;
            } else {
                memmove(cpu_hist, cpu_hist + 1, sizeof(double) * (NHIST - 1));
                memmove(mem_hist, mem_hist + 1, sizeof(double) * (NHIST - 1));
                cpu_hist[NHIST - 1] = usage;
            }
        }
        fclose(f);
    }
    /* --- 内存: /proc/meminfo MemTotal / MemAvailable --- */
    f = fopen("/proc/meminfo", "r");
    if (f) {
        unsigned long avail = 0; char key[64]; unsigned long val; char unit[16];
        int got_total = 0, got_avail = 0;
        while (fgets(line_buf, sizeof line_buf, f)) {
            if (sscanf(line_buf, "%63s %lu %15s", key, &val, unit) >= 2) {
                if (!strcmp(key, "MemTotal:")) { mem_total_kb = val; got_total = 1; }
                else if (!strcmp(key, "MemAvailable:")) { avail = val; got_avail = 1; }
                if (got_total && got_avail) break;
            }
        }
        fclose(f);
        double used = 1.0 - (double)avail / (double)(mem_total_kb ? mem_total_kb : 1);
        if (used < 0) used = 0; if (used > 1) used = 1;
        if (hist_n > 0) mem_hist[hist_n - 1] = used;
    }
    gtk_widget_queue_draw(GTK_WIDGET(ud));
    return G_SOURCE_CONTINUE;
}

static void draw_series(cairo_t *cr, double *hist, int n, double r, double g, double b,
                        int w, int h) {
    cairo_set_source_rgb(cr, r, g, b);
    cairo_set_line_width(cr, 1.5);
    int started = 0;
    for (int i = 0; i < n; i++) {
        if (hist[i] < 0) continue;
        double x = (double)i / (double)(NHIST - 1) * w;
        double y = h - hist[i] * (h - 8) - 2;
        if (!started) { cairo_move_to(cr, x, y); started = 1; }
        else cairo_line_to(cr, x, y);
    }
    cairo_stroke(cr);
}

static gboolean on_draw(GtkWidget *da, cairo_t *cr, gpointer ud) {
    GtkAllocation a;
    gtk_widget_get_allocation(da, &a);
    int w = a.width, h = a.height;
    /* 背景 */
    cairo_set_source_rgb(cr, 0.13, 0.14, 0.16);
    cairo_paint(cr);
    /* 25%/50%/75% 参考线 */
    cairo_set_source_rgb(cr, 0.25, 0.26, 0.28);
    cairo_set_line_width(cr, 1);
    for (int i = 1; i <= 3; i++) {
        double y = h - (double)i / 4.0 * (h - 8) - 2;
        cairo_move_to(cr, 0, y); cairo_line_to(cr, w, y);
    }
    cairo_stroke(cr);
    if (hist_n > 1) {
        draw_series(cr, cpu_hist, hist_n, 0.95, 0.55, 0.15, w, h / 2 - 4);   /* CPU 橙 */
        draw_series(cr, mem_hist, hist_n, 0.45, 0.65, 0.95, w, h / 2 - 4);   /* MEM 蓝 */
    }
    /* 图例文字 */
    cairo_set_source_rgb(cr, 0.9, 0.9, 0.9);
    cairo_select_font_face(cr, "sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 12);
    double last_cpu = hist_n ? cpu_hist[hist_n - 1] : 0;
    double last_mem = hist_n ? mem_hist[hist_n - 1] : 0;
    cairo_move_to(cr, 8, 18);
    cairo_show_text(cr, g_strdup_printf("CPU %3.0f%%", last_cpu * 100));
    cairo_move_to(cr, 8, h / 2.0 + 14);
    cairo_show_text(cr, g_strdup_printf("MEM %3.0f%% of %lu MB", last_mem * 100, mem_total_kb / 1024));
    return FALSE;
}

static void activate(GtkApplication *app, gpointer ud) {
    qy_load_theme();
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元系统监视器"));
    gtk_window_set_default_size(GTK_WINDOW(win), 520, 340);
    GtkWidget *da = gtk_drawing_area_new();
    gtk_container_add(GTK_CONTAINER(win), da);
    g_signal_connect(da, "draw", G_CALLBACK(on_draw), NULL);
    gtk_widget_show_all(win);
    g_timeout_add_seconds(1, tick, da);
    /* 首帧立即采样 */
    tick(da);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.mon", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    char *own_argv[2] = { argv[0], NULL };
    int rc = g_application_run(G_APPLICATION(app), 1, own_argv);
    g_object_unref(app);
    return rc;
}
