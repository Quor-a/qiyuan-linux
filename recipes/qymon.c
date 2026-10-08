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
#include <sys/statvfs.h>

#define NHIST 120   /* 曲线历史点数 */

static void add_class(GtkWidget *w, const char *cls) {
    gtk_style_context_add_class(gtk_widget_get_style_context(w), cls);
}

static double cpu_hist[NHIST];  /* 0..1 */
static double mem_hist[NHIST];  /* 0..1 */
static double disk_hist[NHIST]; /* 0..1 */
static double net_hist[NHIST];  /* 0..1 (KB/s / 1024 归一化) */
static int hist_n = 0;
static char line_buf[256];
static long prev_total = 0, prev_idle = 0;
static unsigned long mem_total_kb = 1;
static GtkWidget *cpu_label = NULL, *mem_label = NULL, *info_label = NULL;
static GtkWidget *title_label = NULL;
static GtkWidget *disk_label = NULL;
static GtkWidget *proc_label = NULL;   /* 内存占用 TOP 5 进程列表 */
static unsigned long net_rx_prev = 0, net_tx_prev = 0;   /* 网络速率 */
static gint64 net_time_prev = 0;

/* 读取当前 CPU 频率 (MHz) */
static double read_cpu_mhz(void) {
    FILE *f = fopen("/proc/cpuinfo", "r");
    if (!f) return 0;
    char buf[256];
    double mhz = 0;
    while (fgets(buf, sizeof buf, f)) {
        if (strncmp(buf, "cpu MHz", 7) == 0) {
            char *c = strchr(buf, ':');
            if (c) { mhz = atof(c + 1); break; }
        }
    }
    fclose(f);
    return mhz;
}

/* 读取首个非 lo 接口的收发速率 (KB/s), 与上次调用差分 */
static gboolean read_net_speed(double *rx_kbs, double *tx_kbs) {
    FILE *f = fopen("/proc/net/dev", "r");
    if (!f) return FALSE;
    char line[512];
    fgets(line, sizeof line, f);   /* 表头1 */
    fgets(line, sizeof line, f);   /* 表头2 */
    unsigned long rx = 0, tx = 0;
    gboolean found = FALSE;
    while (fgets(line, sizeof line, f)) {
        char ifname[64];
        if (sscanf(line, " %63[^:]: %lu %*lu %*lu %*lu %*lu %*lu %*lu %*lu %lu",
                   ifname, &rx, &tx) >= 3) {
            if (strcmp(ifname, "lo") != 0) { found = TRUE; break; }
        }
    }
    fclose(f);
    if (!found) return FALSE;
    gint64 now = g_get_monotonic_time();
    if (net_time_prev == 0) {
        net_rx_prev = rx; net_tx_prev = tx; net_time_prev = now;
        *rx_kbs = 0; *tx_kbs = 0;
        return TRUE;
    }
    double dt = (double)(now - net_time_prev) / 1000000.0;
    if (dt <= 0) dt = 1.0;
    *rx_kbs = (rx - net_rx_prev) / dt / 1024.0;
    *tx_kbs = (tx - net_tx_prev) / dt / 1024.0;
    if (*rx_kbs < 0) *rx_kbs = 0;
    if (*tx_kbs < 0) *tx_kbs = 0;
    net_rx_prev = rx; net_tx_prev = tx; net_time_prev = now;
    return TRUE;
}

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
                cpu_hist[hist_n] = usage; mem_hist[hist_n] = -1;
                disk_hist[hist_n] = -1; net_hist[hist_n] = -1; hist_n++;
            } else {
                memmove(cpu_hist, cpu_hist + 1, sizeof(double) * (NHIST - 1));
                memmove(mem_hist, mem_hist + 1, sizeof(double) * (NHIST - 1));
                memmove(disk_hist, disk_hist + 1, sizeof(double) * (NHIST - 1));
                memmove(net_hist, net_hist + 1, sizeof(double) * (NHIST - 1));
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
    /* --- uptime & loadavg: 信息栏 --- */
    FILE *f2 = fopen("/proc/uptime", "r");
    if (f2) {
        double up = 0;
        fscanf(f2, "%lf", &up);
        fclose(f2);
        double l1 = 0, l5 = 0, l15 = 0;
        long run = 0, total = 0;
        f2 = fopen("/proc/loadavg", "r");
        if (f2) {
            fscanf(f2, "%lf %lf %lf %ld/%ld", &l1, &l5, &l15, &run, &total);
            fclose(f2);
        }
        int d = (int)up;
        char info[256];
        double mhz = read_cpu_mhz();
        char freq[32] = "";
        if (mhz >= 1000) g_snprintf(freq, sizeof freq, "%.2f GHz", mhz / 1000.0);
        else if (mhz > 0) g_snprintf(freq, sizeof freq, "%d MHz", (int)mhz);
        g_snprintf(info, sizeof info,
                    TR("运行 %d天 %02d:%02d · 负载 %.2f %.2f %.2f · 进程 %ld/%ld"),
                    d / 86400, (d % 86400) / 3600, (d % 3600) / 60, l1, l5, l15, run, total);
        if (freq[0]) {
            size_t L = strlen(info);
            g_snprintf(info + L, sizeof info - L, " · CPU %s", freq);
        }
        double rx = 0, tx = 0;
        if (read_net_speed(&rx, &tx)) {
            double net_kbs = rx + tx;
            if (net_kbs > 1024) net_kbs = 1024;
            if (hist_n > 0) net_hist[hist_n - 1] = net_kbs / 1024.0;
            size_t L = strlen(info);
            g_snprintf(info + L, sizeof info - L, " · ↓%.0fKB/s ↑%.0fKB/s", rx, tx);
        }
        if (info_label) gtk_label_set_text(GTK_LABEL(info_label), info);
    }
    /* --- 内存占用 TOP 5 进程列表 --- */
    {
        typedef struct { char name[64]; long rss; } ProcEnt;
        ProcEnt procs[256];
        int np = 0;
        GDir *dir = g_dir_open("/proc", 0, NULL);
        if (dir) {
            const char *pn;
            while ((pn = g_dir_read_name(dir)) && np < 256) {
                if (!g_ascii_isdigit(pn[0])) continue;
                char path[64], line[256];
                g_snprintf(path, sizeof path, "/proc/%s/comm", pn);
                FILE *f = fopen(path, "r");
                if (f) {
                    if (fgets(line, sizeof line, f)) {
                        char *nl = strchr(line, '\n');
                        if (nl) *nl = 0;
                        g_strlcpy(procs[np].name, line, sizeof procs[np].name);
                    }
                    fclose(f);
                } else {
                    g_strlcpy(procs[np].name, "?", sizeof procs[np].name);
                }
                long rss = 0;
                g_snprintf(path, sizeof path, "/proc/%s/status", pn);
                f = fopen(path, "r");
                if (f) {
                    while (fgets(line, sizeof line, f)) {
                        if (!strncmp(line, "VmRSS:", 6)) { rss = atol(line + 6); break; }
                    }
                    fclose(f);
                }
                procs[np].rss = rss;
                np++;
            }
            g_dir_close(dir);
        }
        for (int i = 0; i < np && i < 5; i++) {
            int best = i;
            for (int j = i + 1; j < np; j++)
                if (procs[j].rss > procs[best].rss) best = j;
            ProcEnt t = procs[i]; procs[i] = procs[best]; procs[best] = t;
        }
        GString *s = g_string_new(NULL);
        g_string_append_printf(s, "<b>%s</b>\n", TR("内存占用 TOP 5"));
        for (int i = 0; i < np && i < 5; i++) {
            g_string_append_printf(s, "%s   %ld MB\n",
                                   procs[i].name, (procs[i].rss + 512) / 1024);
        }
        if (proc_label) gtk_label_set_markup(GTK_LABEL(proc_label), s->str);
        g_string_free(s, TRUE);
    }
    /* --- 大数字百分比标签 --- */
    double last_cpu = hist_n ? cpu_hist[hist_n - 1] : 0;
    double last_mem = hist_n ? mem_hist[hist_n - 1] : 0;
    char big[96];
    g_snprintf(big, sizeof big, "CPU %d%%", (int)(last_cpu * 100 + 0.5));
    if (cpu_label) gtk_label_set_text(GTK_LABEL(cpu_label), big);
    g_snprintf(big, sizeof big, TR("内存 %d%%"), (int)(last_mem * 100 + 0.5));
    if (mem_label) gtk_label_set_text(GTK_LABEL(mem_label), big);
    /* 磁盘使用率: statvfs("/") */
    struct statvfs sv;
    double disk = 0.0;
    if (statvfs("/", &sv) == 0 && sv.f_blocks > 0) {
        disk = 1.0 - (double)sv.f_bavail / (double)sv.f_blocks;
        if (disk < 0) disk = 0; if (disk > 1) disk = 1;
        if (hist_n > 0) disk_hist[hist_n - 1] = disk;
    }
    g_snprintf(big, sizeof big, TR("磁盘 %d%%"), (int)(disk * 100 + 0.5));
    if (disk_label) gtk_label_set_text(GTK_LABEL(disk_label), big);
    /* 窗口标题实时显示 CPU 使用率 */
    GtkWidget *win = gtk_widget_get_toplevel(GTK_WIDGET(ud));
    if (win && GTK_IS_WINDOW(win)) {
        gchar *ttl = g_strdup_printf("%s — CPU %d%%", TR("启元系统监视器"),
                                     (int)(last_cpu * 100 + 0.5));
        gtk_window_set_title(GTK_WINDOW(win), ttl);
        if (title_label) gtk_label_set_text(GTK_LABEL(title_label), ttl);
        g_free(ttl);
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
        draw_series(cr, disk_hist, hist_n, 0.20, 0.83, 0.60, w, h / 2 - 4); /* DISK 绿 */
        draw_series(cr, net_hist, hist_n, 0.72, 0.38, 0.95, w, h / 2 - 4); /* NET 紫 */
    }
    /* 图例文字（带彩色方块） */
    cairo_set_font_size(cr, 12);
    double last_cpu = hist_n ? cpu_hist[hist_n - 1] : 0;
    double last_mem = hist_n ? mem_hist[hist_n - 1] : 0;
    double last_disk = hist_n ? disk_hist[hist_n - 1] : 0;
    /* CPU 橙方块 + 文字 */
    cairo_set_source_rgb(cr, 0.95, 0.55, 0.15);
    cairo_rectangle(cr, 8, 8, 10, 10);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.9, 0.9, 0.9);
    cairo_move_to(cr, 24, 18);
    cairo_show_text(cr, g_strdup_printf("CPU %3.0f%%", last_cpu * 100));
    /* NET 紫方块 + 文字 (KB/s) */
    double last_net = hist_n ? net_hist[hist_n - 1] : 0;
    cairo_set_source_rgb(cr, 0.72, 0.38, 0.95);
    cairo_rectangle(cr, w - 190, 8, 10, 10);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.9, 0.9, 0.9);
    cairo_move_to(cr, w - 176, 18);
    cairo_show_text(cr, g_strdup_printf("NET %3.0f KB/s", last_net * 1024));
    /* MEM 蓝方块 + 文字 */
    cairo_set_source_rgb(cr, 0.45, 0.65, 0.95);
    cairo_rectangle(cr, 8, h / 2.0 + 4, 10, 10);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.9, 0.9, 0.9);
    cairo_move_to(cr, 24, h / 2.0 + 14);
    cairo_show_text(cr, g_strdup_printf("MEM %3.0f%% of %lu MB", last_mem * 100, mem_total_kb / 1024));
    /* DISK 绿方块 + 文字 */
    cairo_set_source_rgb(cr, 0.20, 0.83, 0.60);
    cairo_rectangle(cr, w - 140, h / 2.0 + 4, 10, 10);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.9, 0.9, 0.9);
    cairo_move_to(cr, w - 126, h / 2.0 + 14);
    cairo_show_text(cr, g_strdup_printf("DISK %3.0f%%", last_disk * 100));
    return FALSE;
}

static void activate(GtkApplication *app, gpointer ud) {
    qy_load_theme();
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元系统监视器"));
    gtk_window_set_default_size(GTK_WINDOW(win), 560, 480);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_widget_set_margin_start(vbox, 12);
    gtk_widget_set_margin_end(vbox, 12);
    gtk_widget_set_margin_top(vbox, 10);
    gtk_widget_set_margin_bottom(vbox, 8);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 顶部标题: 启元系统监视器 — CPU xx% */
    title_label = gtk_label_new(NULL);
    add_class(title_label, "qy-mon-title");
    gtk_label_set_xalign(GTK_LABEL(title_label), 0.0);
    gtk_box_pack_start(GTK_BOX(vbox), title_label, FALSE, FALSE, 0);

    /* 顶部大数字: CPU / 内存 / 磁盘 */
    GtkWidget *hrow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 24);
    cpu_label = gtk_label_new("CPU 0%");
    add_class(cpu_label, "qy-mon-cpu");
    char lbl[64];
    g_snprintf(lbl, sizeof lbl, "%s 0%%", TR("内存"));
    mem_label = gtk_label_new(lbl);
    add_class(mem_label, "qy-mon-mem");
    g_snprintf(lbl, sizeof lbl, "%s 0%%", TR("磁盘"));
    disk_label = gtk_label_new(lbl);
    add_class(disk_label, "qy-mon-disk");
    gtk_box_pack_start(GTK_BOX(hrow), cpu_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hrow), mem_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hrow), disk_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), hrow, FALSE, FALSE, 0);

    /* 实时曲线区 */
    GtkWidget *da = gtk_drawing_area_new();
    gtk_widget_set_size_request(da, -1, 160);
    g_signal_connect(da, "draw", G_CALLBACK(on_draw), NULL);
    gtk_box_pack_start(GTK_BOX(vbox), da, TRUE, TRUE, 0);

    /* 内存占用 TOP 5 进程列表 */
    proc_label = gtk_label_new(NULL);
    add_class(proc_label, "qy-mon-proc");
    gtk_label_set_xalign(GTK_LABEL(proc_label), 0.0);
    gtk_box_pack_start(GTK_BOX(vbox), proc_label, FALSE, FALSE, 0);

    /* 底部信息栏: 运行时间 / 负载 / 进程 */
    info_label = gtk_label_new("");
    add_class(info_label, "qy-mon-info");
    gtk_widget_set_halign(info_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), info_label, FALSE, FALSE, 0);

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
