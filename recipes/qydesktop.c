/* qydesktop - 启元桌面 shell v2.0（单一全屏桌面窗口）
 *
 * v2.0 架构变化：把 顶栏 + 左侧 Dock + 壁纸桌面图标 合并进**一个全屏
 * DESKTOP 窗口**，彻底规避 Wayland 下多窗口 DOCK 定位失效（gtk_window_move
 * 在 Wayland 被忽略导致 bar/dock 错位）的问题。
 *
 * 布局（1280x800）:
 *   ┌──────────────────────────────┐ 0
 *   │ ⊞ | 窗口任务栏 …  时钟   ⏻ │ 30  顶栏
 *   ├────┬─────────────────────────┤
 *   │Dock│ 壁纸 + 桌面图标          │
 *   │  ▤ │                          │
 *   │ >_ │                          │
 *   │ ⚙  │                          │
 *   │ ▦  │                          │
 *   │ ── │                          │
 *   │ ⊞  │                          │
 *   └────┴─────────────────────────┘
 *
 * 任务栏数据源：weston 合成器补丁每 500ms 写的 /tmp/xdg/qy-windows，
 * 点击窗口按钮写 /tmp/xdg/qy-focus 让合成器激活对应窗口。
 * 主题：/usr/share/themes/qiyuan/gtk-3.0/gtk.css（GTK CSS，qytheme.css）。
 */
#include "qyl10n.h"
#include <gtk/gtk.h>
#include <time.h>
#include <string.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <dirent.h>

#define QY_WINDOWS  "/tmp/xdg/qy-windows"
#define QY_FOCUS    "/tmp/xdg/qy-focus"
#define QY_CSS      "/usr/share/themes/qiyuan/gtk-3.0/gtk.css"
#define QY_WALL     "/usr/share/backgrounds/qiyuan.png"

#define SCREEN_W  1280
#define SCREEN_H  800
#define BAR_H     30
#define DOCK_W    66

/* ---------- 应用注册表 ---------- */
typedef struct {
    const char *name;
    const char *glyph;
    const char *css;      /* 主题颜色类 */
    const char *cmdline;
    const char *exe;      /* /proc/<pid>/comm */
    int  pid;
    GtkWidget *dot;       /* 运行指示灯 */
} AppEntry;

static AppEntry apps[] = {
    { "文件",   "▤", "c-files",    "qyfiles",          "qyfiles",      0, NULL },
    { "终端",   ">_", "c-term",     "weston-terminal",  "weston-termi", 0, NULL },
    { "设置",   "⚙", "c-settings", "qysettings",       "qysettings",   0, NULL },
    { "软件中心", "▦", "c-store",    "qystore",          "qystore",      0, NULL },
    { "监视",   "▦", "c-mon",     "qymon",             "qymon",        0, NULL },
    { "回收站", "🗑", "c-trash",   "qyfiles --trash",   "qyfiles",      0, NULL },
};
#define NAPPS ((int)(sizeof apps / sizeof apps[0]))

static GtkWidget *taskbar_box   = NULL;
static guint     active_id     = 0;   /* 最近点击的任务栏窗口（本地高亮反馈） */
static long      active_until  = 0;   /* 高亮截止时间戳 */
static GtkWidget *clock_label  = NULL;
static GtkWidget *clock_btn   = NULL;  /* 顶栏时钟按钮（点击弹出日历） */
static GtkWidget *power_btn   = NULL;  /* 顶栏电源按钮（关机/重启/注销） */
static void on_clock_clicked(GtkWidget *w, gpointer ud);   /* 前向声明 */
static GtkWidget *mon_label    = NULL;  /* 顶栏 CPU/内存小部件 */
static GtkWidget *mon_draw     = NULL;  /* 顶栏 CPU/内存迷你条 (cairo) */
static double    mon_cpu = 0.0, mon_mem = 0.0;  /* 当前使用率 0~1 */
static GtkWidget *desktop_fixed = NULL;

/* ---------- 工具 ---------- */
static void launch_cmd(const char *cmd) {
    GError *err = NULL;
    gchar **argv = NULL;
    if (!g_shell_parse_argv(cmd, NULL, &argv, &err)) { if (err) g_error_free(err); return; }
    g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &err);
    if (err) { g_printerr("launch: %s\n", err->message); g_error_free(err); }
    g_strfreev(argv);
}

static int proc_running(const char *exe) {
    DIR *d = opendir("/proc");
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] < '0' || e->d_name[0] > '9') continue;
        char path[64], buf[256];
        snprintf(path, sizeof path, "/proc/%s/comm", e->d_name);
        FILE *f = fopen(path, "r");
        if (!f) continue;
        if (fgets(buf, sizeof buf, f)) {
            buf[strcspn(buf, "\n")] = 0;
            if (strcmp(buf, exe) == 0) { fclose(f); closedir(d); return atoi(e->d_name); }
        }
        fclose(f);
    }
    closedir(d);
    return 0;
}

/* ---------- 主题 ---------- */
static void load_theme(void) {
    GtkCssProvider *p = gtk_css_provider_new();
    if (gtk_css_provider_load_from_path(p, QY_CSS, NULL)) {
        gtk_style_context_add_provider_for_screen(
            gdk_screen_get_default(), GTK_STYLE_PROVIDER(p),
            GTK_STYLE_PROVIDER_PRIORITY_USER);
    }
    g_object_unref(p);
}

static void add_class(GtkWidget *w, const char *cls) {
    gtk_style_context_add_class(gtk_widget_get_style_context(w), cls);
}

/* ---------- 时钟 ---------- */
/* 顶栏迷你资源条: 87x6, 两条圆角矩形 (CPU 左 / 内存 右) */
static gboolean mon_draw_cb(GtkWidget *w, cairo_t *cr, gpointer ud) {
    int W = 87, H = 6;
    cairo_set_source_rgb(cr, 0.11, 0.14, 0.19);   /* #1c2331 trough */
    cairo_rectangle(cr, 0, 0, W, H);
    cairo_fill(cr);
    cairo_set_source_rgb(cr, 0.914, 0.329, 0.125);  /* #E95420 */
    double cw = mon_cpu * 38.0;
    if (cw > 0) { cairo_rectangle(cr, 1, 1, cw, H - 2); cairo_fill(cr); }
    double mw = mon_mem * 38.0;
    if (mw > 0) { cairo_rectangle(cr, 46, 1, mw, H - 2); cairo_fill(cr); }
    return FALSE;
}

static gboolean tick(gpointer data) {
    char buf[64];
    time_t t = time(NULL);
    struct tm tm_;
    localtime_r(&t, &tm_);
    strftime(buf, sizeof buf, TR("%m月%d日 %H:%M:%S"), &tm_);
    const char *wd[] = { TR("日"), TR("一"), TR("二"), TR("三"), TR("四"), TR("五"), TR("六") };
    char full[96];
    g_snprintf(full, sizeof full, TR("周%s %s"), wd[tm_.tm_wday], buf);
    gtk_label_set_text(GTK_LABEL(clock_label), full);
    return G_SOURCE_CONTINUE;
}

/* ---------- 顶栏 CPU/内存小部件 ---------- */
static gboolean mon_tick(gpointer data) {
    static long prev_total = 0, prev_idle = 0;
    FILE *f = fopen("/proc/stat", "r");
    if (!f) return G_SOURCE_CONTINUE;
    long u, n, s, idle, iow, irq, sirq, steal;
    if (fscanf(f, "cpu %ld %ld %ld %ld %ld %ld %ld %ld",
               &u, &n, &s, &idle, &iow, &irq, &sirq, &steal) == 8) {
        long total = u + n + s + idle + iow + irq + sirq + steal;
        long dtotal = total - prev_total;
        long didle = (idle + iow) - prev_idle;
        double usage = dtotal > 0 ? 1.0 - (double)didle / (double)dtotal : 0.0;
        prev_total = total;
        prev_idle = idle + iow;
        fclose(f);
        unsigned long avail = 0, total_kb = 0;
        char key[64];
        unsigned long val;
        char unit[16];
        f = fopen("/proc/meminfo", "r");
        if (f) {
            while (fscanf(f, "%63s %lu %15s", key, &val, unit) >= 2) {
                if (!strcmp(key, "MemTotal:")) total_kb = val;
                else if (!strcmp(key, "MemAvailable:")) { avail = val; break; }
            }
            fclose(f);
        }
        double mem = total_kb > 0 ? 1.0 - (double)avail / (double)total_kb : 0.0;
        char buf[80];
        g_snprintf(buf, sizeof buf, "CPU %d%% · MEM %d%%",
                   (int)(usage * 100 + 0.5), (int)(mem * 100 + 0.5));
        gtk_label_set_text(GTK_LABEL(data), buf);
        mon_cpu = usage;
        mon_mem = mem;
        if (mon_draw) gtk_widget_queue_draw(mon_draw);
    } else {
        fclose(f);
    }
    return G_SOURCE_CONTINUE;
}

/* ---------- 应用菜单 ---------- */
static void on_appmenu_clicked(GtkButton *b, gpointer ud) { launch_cmd("qyappmenu"); }

/* ---------- 窗口任务栏：读 weston 补丁的窗口列表 ---------- */
typedef struct { guint id; gchar title[96]; } WinInfo;

static int taskbar_parse(WinInfo *wins, int max) {
    FILE *f = fopen(QY_WINDOWS, "r");
    int n = 0;
    if (!f) return 0;
    char line[256];
    while (n < max && fgets(line, sizeof line, f)) {
        char *tab = strchr(line, '\t');
        if (!tab) continue;
        *tab = 0;
        char *rest = tab + 1;
        char *at = strchr(rest, '@');
        if (at) *at = 0;
        char *nl = strchr(rest, '\n');
        if (nl) *nl = 0;
        if (!rest[0]) continue;
        /* 过滤壳层自身窗口与启动器 */
        if (strncmp(rest, "qydesktop", 9) == 0) continue;
        if (strcmp(rest, "qyappmenu") == 0) continue;
        /* 重复标题去重：同一应用多实例只显示一个按钮 */
        int dup = 0;
        for (int i = 0; i < n; i++) {
            if (strcmp(wins[i].title, rest) == 0) { dup = 1; break; }
        }
        if (dup) continue;
        wins[n].id = (guint)strtoul(line, NULL, 10);
        g_strlcpy(wins[n].title, rest, sizeof wins[n].title);
        n++;
    }
    fclose(f);
    return n;
}

static void on_task_clicked(GtkButton *btn, gpointer ud) {
    guint id = GPOINTER_TO_UINT(ud);
    active_id = id;
    active_until = time(NULL) + 3;   /* 点击后高亮 3 秒 */
    FILE *f = fopen(QY_FOCUS, "w");
    if (f) { fprintf(f, "%u", id); fclose(f); }
}

/* 按窗口标题关键词映射图标字符 + 主题色类 */
static void task_glyph(const char *title, const char **glyph, const char **cls) {
    if (strstr(title, "文件") || strstr(title, "主文件夹")) { *glyph = "▤"; *cls = "c-files"; return; }
    if (strstr(title, "终端"))     { *glyph = ">_"; *cls = "c-term"; return; }
    if (strstr(title, "设置"))     { *glyph = "⚙"; *cls = "c-settings"; return; }
    if (strstr(title, "监视"))     { *glyph = "▦"; *cls = "c-mon"; return; }
    if (strstr(title, "软件中心")) { *glyph = "▦"; *cls = "c-store"; return; }
    if (strstr(title, "回收站"))   { *glyph = "🗑"; *cls = "c-trash"; return; }
    if (strstr(title, "文本") || strstr(title, "编辑器")) { *glyph = "✎"; *cls = "c-grid"; return; }
    if (strstr(title, "图片") || strstr(title, "图像") || strstr(title, "查看")) { *glyph = "▣"; *cls = "c-view"; return; }
    if (strstr(title, "压缩"))     { *glyph = "▣"; *cls = "c-grid"; return; }
    if (strstr(title, "Terminal") || strstr(title, "erminal")) { *glyph = ">_"; *cls = "c-term"; return; }
    *glyph = "▣"; *cls = "c-grid";
}

static guint read_focus(void) {
    FILE *f = fopen(QY_FOCUS, "r");
    guint id = 0;
    if (f) {
        if (fscanf(f, "%u", &id) != 1) id = 0;
        fclose(f);
    }
    return id;
}

static void refresh_taskbar(void) {
    if (!taskbar_box) return;
    GList *ch = gtk_container_get_children(GTK_CONTAINER(taskbar_box));
    for (GList *it = ch; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(ch);

    WinInfo wins[16];
    int n = taskbar_parse(wins, 16);
    guint focus = read_focus();
    long now = time(NULL);
    for (int i = 0; i < n; i++) {
        GtkWidget *b = gtk_button_new();
        gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
        add_class(b, "qy-bar-btn");
        GtkWidget *hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
        gtk_container_add(GTK_CONTAINER(b), hb);
        const char *glyph, *cls;
        task_glyph(wins[i].title, &glyph, &cls);
        GtkWidget *gl = gtk_label_new(glyph);
        add_class(gl, "qy-task-glyph");
        add_class(gl, cls);
        gtk_box_pack_start(GTK_BOX(hb), gl, FALSE, FALSE, 0);
        GtkWidget *tl = gtk_label_new(wins[i].title);
        add_class(tl, "qy-task-label");
        gtk_box_pack_start(GTK_BOX(hb), tl, FALSE, FALSE, 0);
        gtk_widget_set_tooltip_text(b, wins[i].title);
        if ((wins[i].id == active_id && now < active_until) ||
            wins[i].id == focus)
            add_class(b, "qy-bar-btn-active");
        g_signal_connect(b, "clicked", G_CALLBACK(on_task_clicked),
                         GUINT_TO_POINTER(wins[i].id));
        gtk_box_pack_start(GTK_BOX(taskbar_box), b, FALSE, FALSE, 2);
        gtk_widget_show_all(b);
    }
}

static gboolean taskbar_tick(gpointer ud) { refresh_taskbar(); return G_SOURCE_CONTINUE; }

/* ---------- Dock ---------- */
static void dock_click(GtkButton *btn, gpointer ud) { launch_cmd(((AppEntry *)ud)->cmdline); }

static GtkWidget *dock_icon(AppEntry *a) {
    GtkWidget *btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
    add_class(btn, "qy-dock-icon");
    add_class(btn, a->css);
    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(btn), v);
    GtkWidget *ic = gtk_label_new(a->glyph);
    gtk_widget_set_halign(ic, GTK_ALIGN_CENTER);
    gtk_box_pack_start(GTK_BOX(v), ic, TRUE, TRUE, 0);
    GtkWidget *dot = gtk_label_new("●");
    gtk_widget_set_halign(dot, GTK_ALIGN_CENTER);
    add_class(dot, "qy-dock-dot");
    gtk_box_pack_start(GTK_BOX(v), dot, FALSE, FALSE, 0);
    gtk_widget_set_visible(dot, FALSE);
    a->dot = dot;
    gtk_widget_set_tooltip_text(btn, TR(a->name));
    g_signal_connect(btn, "clicked", G_CALLBACK(dock_click), a);
    return btn;
}

static gboolean dock_tick(gpointer ud) {
    for (int i = 0; i < NAPPS; i++) {
        int pid = proc_running(apps[i].exe);
        apps[i].pid = pid;
        if (apps[i].dot) gtk_widget_set_visible(apps[i].dot, pid > 0);
    }
    return G_SOURCE_CONTINUE;
}

/* ---------- 桌面图标 ---------- */
static void desktop_icon_click(GtkButton *btn, gpointer ud) {
    launch_cmd((const char *)ud);
}

static GtkWidget *desktop_icon(const char *glyph, const char *css,
                               const char *label, const char *cmdline) {
    GtkWidget *btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
    add_class(btn, "qy-desktop-icon");
    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_container_add(GTK_CONTAINER(btn), v);

    /* 彩色圆形按钮（按钮才可靠绘制 CSS 背景色） */
    GtkWidget *circle = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(circle), GTK_RELIEF_NONE);
    add_class(circle, "qy-desktop-glyph");
    add_class(circle, css);
    gtk_widget_set_size_request(circle, 44, 44);
    GtkWidget *gl = gtk_label_new(glyph);
    gtk_container_add(GTK_CONTAINER(circle), gl);

    GtkWidget *lb = gtk_label_new(label);
    add_class(lb, "qy-desktop-label");
    gtk_box_pack_start(GTK_BOX(v), circle, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v), lb, FALSE, FALSE, 0);
    g_signal_connect(btn, "clicked", G_CALLBACK(desktop_icon_click),
                     (gpointer)g_strdup(cmdline));
    return btn;
}

/* ---------- 壁纸（供菜单刷新） ---------- */
static GdkPixbuf *wallpaper = NULL;
static guint wall_seed = 0;

/* 程序化生成品牌壁纸: 深蓝→深紫渐变 + 橙/紫柔光圆斑（种子不同图案不同） */
static GdkPixbuf *gen_wallpaper(guint seed) {
    int w = 1600, h = 900;
    cairo_surface_t *surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
    cairo_t *cr = cairo_create(surf);
    /* 基底垂直渐变 */
    cairo_pattern_t *pat = cairo_pattern_create_linear(0, 0, 0, h);
    cairo_pattern_add_color_stop_rgb(pat, 0, 0.045 + (seed % 2) * 0.015, 0.058, 0.13);
    cairo_pattern_add_color_stop_rgb(pat, 1, 0.12 + (seed % 3) * 0.02, 0.055 + (seed % 2) * 0.02, 0.155);
    cairo_set_source(cr, pat);
    cairo_paint(cr);
    cairo_pattern_destroy(pat);
    /* 橙色柔光圆斑 */
    srand(seed);
    for (int i = 0; i < 8; i++) {
        double cx = rand() % w, cy = rand() % h;
        double rad = 60 + rand() % 240;
        cairo_pattern_t *rg = cairo_pattern_create_radial(cx, cy, 10, cx, cy, rad);
        cairo_pattern_add_color_stop_rgba(rg, 0, 0.91, 0.33, 0.13, 0.26);
        cairo_pattern_add_color_stop_rgba(rg, 1, 0.91, 0.33, 0.13, 0);
        cairo_set_source(cr, rg);
        cairo_arc(cr, cx, cy, rad, 0, 2 * G_PI);
        cairo_fill(cr);
        cairo_pattern_destroy(rg);
    }
    /* 紫色柔光圆斑 */
    for (int i = 0; i < 6; i++) {
        double cx = rand() % w, cy = rand() % h;
        double rad = 50 + rand() % 200;
        cairo_pattern_t *rg = cairo_pattern_create_radial(cx, cy, 10, cx, cy, rad);
        cairo_pattern_add_color_stop_rgba(rg, 0, 0.47, 0.13, 0.44, 0.24);
        cairo_pattern_add_color_stop_rgba(rg, 1, 0.47, 0.13, 0.44, 0);
        cairo_set_source(cr, rg);
        cairo_arc(cr, cx, cy, rad, 0, 2 * G_PI);
        cairo_fill(cr);
        cairo_pattern_destroy(rg);
    }
    /* 星空点缀: 随机白色小星点（不同种子分布不同） */
    for (int i = 0; i < 90; i++) {
        double sx = rand() % w, sy = rand() % h;
        double sr = 0.5 + (rand() % 25) / 20.0;   /* 0.5~1.75px 半径 */
        cairo_set_source_rgba(cr, 1, 1, 1, 0.25 + (rand() % 60) / 100.0);
        cairo_arc(cr, sx, sy, sr, 0, 2 * G_PI);
        cairo_fill(cr);
    }
    cairo_destroy(cr);
    GdkPixbuf *pb = gdk_pixbuf_get_from_surface(surf, 0, 0, w, h);
    cairo_surface_destroy(surf);
    return pb;
}

/* 换一张新壁纸（右键刷新 / 定时轮换共用） */
static void rotate_wallpaper(void) {
    if (wallpaper) g_object_unref(wallpaper);
    wall_seed++;
    wallpaper = gen_wallpaper(wall_seed);
    if (desktop_fixed) gtk_widget_queue_draw(desktop_fixed);
}

/* ---------- 桌面右键菜单 ---------- */
static void menu_new_folder(GtkMenuItem *mi, gpointer ud) {
    const char *home = g_get_home_dir();
    if (!home || !home[0]) home = "/root";
    gchar *path = g_strdup_printf("%s/新建文件夹", home);
    int i = 1;
    while (g_file_test(path, G_FILE_TEST_EXISTS)) {
        g_free(path);
        path = g_strdup_printf("%s/新建文件夹%d", home, i++);
    }
    g_mkdir_with_parents(path, 0755);
    g_free(path);
}

static void menu_open_terminal(GtkMenuItem *mi, gpointer ud) { launch_cmd("weston-terminal"); }
static void menu_open_files(GtkMenuItem *mi, gpointer ud) { launch_cmd("qyfiles"); }
static void menu_open_settings(GtkMenuItem *mi, gpointer ud) { launch_cmd("qysettings"); }
static void menu_open_monitor(GtkMenuItem *mi, gpointer ud) { launch_cmd("qymon"); }
static void menu_open_driver(GtkMenuItem *mi, gpointer ud) { launch_cmd("qydriver"); }
static void menu_open_trash(GtkMenuItem *mi, gpointer ud) { launch_cmd("qyfiles --trash"); }
static void menu_refresh_wallpaper(GtkMenuItem *mi, gpointer ud) {
    rotate_wallpaper();
}

/* 自动轮换壁纸 (默认 600s, 可用 QY_WALL_INTERVAL 秒覆盖) */
static gboolean auto_wall_tick(gpointer ud) {
    rotate_wallpaper();
    return G_SOURCE_CONTINUE;
}

static gboolean auto_close_about(gpointer p) {
    gtk_widget_destroy(GTK_WIDGET(p));
    return G_SOURCE_REMOVE;
}

static void menu_about(GtkMenuItem *mi, gpointer ud) {
    (void)mi; (void)ud;
    GtkWidget *dlg = gtk_message_dialog_new(NULL, GTK_DIALOG_DESTROY_WITH_PARENT,
                                            GTK_MESSAGE_INFO, GTK_BUTTONS_OK,
                                            "%s", TR("启元 Linux 桌面"));
    /* 系统信息: 发行版 / 内核 / 内存 */
    gchar *os = NULL;
    g_file_get_contents("/etc/os-release", &os, NULL, NULL);
    gchar *distro = g_strdup(TR("未知发行版"));
    if (os) {
        const char *p = strstr(os, "PRETTY_NAME=");
        if (p) {
            p += 12;
            const char *e = strchr(p, '\n');
            gchar *name = g_strstrip(g_strndup(p, e ? (gsize)(e - p) : strlen(p)));
            if (name[0] == '"' && name[strlen(name) - 1] == '"') {
                name[strlen(name) - 1] = 0;
                g_free(distro);
                distro = g_strdup(name + 1);
            } else {
                g_free(distro);
                distro = g_strdup(name);
            }
            g_free(name);
        }
    }
    g_free(os);
    gchar *kver = NULL;
    g_spawn_command_line_sync("uname -r", &kver, NULL, NULL, NULL);
    gchar *mem = NULL;
    g_file_get_contents("/proc/meminfo", &mem, NULL, NULL);
    int mem_mb = -1;
    if (mem) {
        const char *p = strstr(mem, "MemTotal:");
        if (p) mem_mb = atoi(p + 9) / 1024;
    }
    g_free(mem);
    gchar *info = g_strdup_printf("%s\n%s: %s\n%s: %s\n%s: %d MB",
        TR("GTK3 单窗口桌面壳层 · weston + 自研任务栏补丁"),
        TR("发行版"), distro,
        TR("内核"), kver ? g_strstrip(kver) : TR("未知"),
        TR("内存"), mem_mb);
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dlg), "%s", info);
    g_free(distro); g_free(kver); g_free(info);
    g_printerr("QYDESKTOPDBG: about shown\n");
    if (g_getenv("QYDESKTOP_ABOUT")) {
        gtk_widget_show_all(dlg);
        g_timeout_add(4000, auto_close_about, dlg);
    } else {
        gtk_dialog_run(GTK_DIALOG(dlg));
        gtk_widget_destroy(dlg);
    }
}

static gboolean desk_button_press(GtkWidget *w, GdkEventButton *ev, gpointer ud) {
    if (ev->button == 3) {
        GtkWidget *menu = gtk_menu_new();
        add_class(menu, "qy-menu");
        GtkWidget *mi;
        mi = gtk_menu_item_new_with_label(TR("新建文件夹"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_new_folder), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        mi = gtk_menu_item_new_with_label(TR("打开终端"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_open_terminal), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
        mi = gtk_menu_item_new_with_label(TR("文件管理器"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_open_files), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        mi = gtk_menu_item_new_with_label(TR("系统设置"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_open_settings), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        mi = gtk_menu_item_new_with_label(TR("系统监视"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_open_monitor), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        mi = gtk_menu_item_new_with_label(TR("驱动管理器"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_open_driver), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        mi = gtk_menu_item_new_with_label(TR("回收站"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_open_trash), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
        mi = gtk_menu_item_new_with_label(TR("刷新壁纸"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_refresh_wallpaper), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        mi = gtk_menu_item_new_with_label(TR("关于启元"));
        add_class(mi, "qy-menu-item");
        g_signal_connect(mi, "activate", G_CALLBACK(menu_about), NULL);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
        gtk_widget_show_all(menu);
        gtk_menu_popup_at_pointer(GTK_MENU(menu), (const GdkEvent *)ev);
        g_printerr("QYDESKTOPDBG: desktop right-click menu\n");
    }
    return FALSE;
}

/* 自动化：QYDESKTOP_RIGHTCLICK=1 启动后模拟桌面右键弹出菜单 */
static gboolean auto_desktop_rightclick(gpointer p) {
    (void)p;
    GdkEventButton ev;
    memset(&ev, 0, sizeof ev);
    ev.type = GDK_BUTTON_PRESS;
    ev.button = 3;
    ev.x = 220; ev.y = 220;
    ev.x_root = 220; ev.y_root = 220;
    ev.time = gtk_get_current_event_time();
    desk_button_press(NULL, &ev, NULL);
    return G_SOURCE_REMOVE;
}

/* ---------- 电源对话框 ---------- */
static void on_power_clicked(GtkButton *b, gpointer ud) {
    GtkWidget *dlg = gtk_dialog_new_with_buttons(
        TR("系统"), NULL,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        TR("取消"), GTK_RESPONSE_CANCEL,
        TR("重启"), 1,
        TR("关机"), 2,
        NULL);
    add_class(dlg, "qy-dialog");
    gint resp = gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
    if (resp == 1) launch_cmd("busybox reboot");
    else if (resp == 2) launch_cmd("busybox poweroff");
}

/* ---------- 壁纸绘制 ---------- */
static gboolean desk_draw(GtkWidget *w, cairo_t *cr, gpointer ud) {
    guint width = gtk_widget_get_allocated_width(w);
    guint height = gtk_widget_get_allocated_height(w);
    if (wallpaper) {
        int pw = gdk_pixbuf_get_width(wallpaper), ph = gdk_pixbuf_get_height(wallpaper);
        cairo_save(cr);
        cairo_scale(cr, (double)width / pw, (double)height / ph);
        gdk_cairo_set_source_pixbuf(cr, wallpaper, 0, 0);
        cairo_paint(cr);
        cairo_restore(cr);
    } else {
        cairo_pattern_t *pat = cairo_pattern_create_linear(0, 0, 0, height);
        cairo_pattern_add_color_stop_rgb(pat, 0, 0.04, 0.06, 0.12);
        cairo_pattern_add_color_stop_rgb(pat, 1, 0.11, 0.07, 0.14);
        cairo_set_source(cr, pat);
        cairo_paint(cr);
        cairo_pattern_destroy(pat);
    }
    return FALSE;
}

/* ---------- 顶栏 ---------- */
static GtkWidget *notif_label = NULL;
static gchar *last_notif_content = NULL;
static GtkWidget *res_label = NULL;

/* 分辨率快捷切换：改写 weston.ini 的 mode=（start-weston.sh 消费） */
static void apply_resolution(const char *mode) {
    if (!mode || !mode[0]) return;
    const char *path = "/etc/xdg/weston/weston.ini";
    gchar *content = NULL;
    if (!g_file_get_contents(path, &content, NULL, NULL)) {
        content = g_strdup("[core]\nshell=desktop-shell.so\n");
    }
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "mode=", 5) == 0) {
            g_string_append_printf(out, "mode=%s", mode);
            if (nl) g_string_append_c(out, '\n');
            replaced = 1;
        } else {
            g_string_append_len(out, line, len);
            if (nl) g_string_append_c(out, '\n');
        }
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "\n[output]\nname=Virtual-1\nmode=%s\n", mode);
    g_file_set_contents(path, out->str, out->len, NULL);
    g_string_free(out, TRUE);
    g_printerr("QYDESKTOPDBG: resolution=%s\n", mode);
    /* 顶栏按钮同步显示 */
    if (res_label) gtk_label_set_text(GTK_LABEL(res_label), mode);
    /* 通知用户（qydesktop 顶栏气泡读取） */
    gchar *body = g_strdup_printf(TR("分辨率已设置为 %s，重启桌面后生效"), mode);
    gchar *full = g_strdup_printf("%s|%s\n", TR("分辨率"), body);
    g_mkdir_with_parents("/tmp/qynotif", 0755);
    g_file_set_contents("/tmp/qynotif/latest.msg", full, -1, NULL);
    g_free(body); g_free(full);
}

/* 分辨率菜单项激活 */
static void on_res_activate(GtkMenuItem *mi, gpointer ud) {
    (void)mi;
    apply_resolution((const char *)ud);
}

/* 分辨率按钮点击：弹出可选模式菜单 */
static void on_res_btn_clicked(GtkWidget *w, gpointer ud) {
    static const char *modes[] = { "1280x800", "1024x768", "1920x1080", "2560x1440", NULL };
    GtkWidget *menu = gtk_menu_new();
    for (int i = 0; modes[i]; i++) {
        GtkWidget *it = gtk_menu_item_new_with_label(modes[i]);
        g_signal_connect(it, "activate", G_CALLBACK(on_res_activate), (gpointer)modes[i]);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), it);
    }
    gtk_widget_show_all(menu);
    gtk_menu_attach_to_widget(GTK_MENU(menu), w, NULL);
    gtk_menu_popup_at_widget(GTK_MENU(menu), w, GDK_GRAVITY_SOUTH_WEST, GDK_GRAVITY_NORTH_WEST, NULL);
}

/* 自动化: QYDESKTOP_RES=1024x768 启动后自动设置分辨率 */
static gboolean auto_res_apply(gpointer p) {
    apply_resolution((const char *)p);
    return G_SOURCE_REMOVE;
}

/* 通知显示：读取 /tmp/qynotif/latest.msg（qynotify/qynotifd 写入） */
static gboolean notif_tick(gpointer ud) {
    (void)ud;
    gchar *content = NULL;
    if (g_file_get_contents("/tmp/qynotif/latest.msg", &content, NULL, NULL) && content) {
        if (!last_notif_content || strcmp(last_notif_content, content) != 0) {
            char *bar = strchr(content, '|');
            if (bar) {
                *bar = 0;
                gchar *title = g_strdup_printf("🔔 %s", content);
                gtk_label_set_text(GTK_LABEL(notif_label), title);
                gtk_widget_set_tooltip_text(notif_label, bar + 1);
                g_free(title);
            }
            g_free(last_notif_content);
            last_notif_content = g_strdup(content);
        }
        g_free(content);
    } else {
        gtk_label_set_text(GTK_LABEL(notif_label), "🔔");
    }
    return G_SOURCE_CONTINUE;
}

static void tray_launch(const char *cmd) {
    gchar *s = g_strdup_printf("%s &", cmd);
    g_spawn_command_line_async(s, NULL);
    g_free(s);
}
static void on_tray_clicked(GtkWidget *w, gpointer ud) {
    tray_launch((const char *)ud);
}
static GtkWidget *make_tray_btn(const char *icon, const char *tip, const char *cmd) {
    GtkWidget *b = gtk_button_new_with_label(icon);
    gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
    add_class(b, "qy-status-btn");
    gtk_widget_set_tooltip_text(b, tip);
    g_signal_connect(b, "clicked", G_CALLBACK(on_tray_clicked), g_strdup(cmd));
    return b;
}

/* ---------- 电源菜单：关机 / 重启 / 注销 ---------- */
static void on_power_action(GtkMenuItem *mi, gpointer ud) {
    (void)mi;
    const char *cmd = (const char *)ud;
    g_printerr("QYDESKTOPDBG: power action %s\n", cmd);
    g_spawn_command_line_async(cmd, NULL);
}

static void on_power_btn_clicked(GtkWidget *w, gpointer ud) {
    (void)ud;
    GtkWidget *menu = gtk_menu_new();
    GtkWidget *mi;
    mi = gtk_menu_item_new_with_label(TR("关机"));
    g_signal_connect(mi, "activate", G_CALLBACK(on_power_action), g_strdup("poweroff"));
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
    mi = gtk_menu_item_new_with_label(TR("重启"));
    g_signal_connect(mi, "activate", G_CALLBACK(on_power_action), g_strdup("reboot"));
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
    mi = gtk_menu_item_new_with_label(TR("注销"));
    g_signal_connect(mi, "activate", G_CALLBACK(on_power_action), g_strdup("pkill -x weston"));
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
    gtk_widget_show_all(menu);
    gtk_menu_attach_to_widget(GTK_MENU(menu), w, NULL);
    gtk_menu_popup_at_widget(GTK_MENU(menu), w, GDK_GRAVITY_SOUTH_WEST, GDK_GRAVITY_NORTH_WEST, NULL);
    g_printerr("QYDESKTOPDBG: power menu shown\n");
}

/* 自动化: QYDESKTOP_POWER=1 启动后弹出电源菜单 */
static gboolean auto_power_menu(gpointer p) {
    (void)p;
    on_power_btn_clicked(power_btn, NULL);
    return G_SOURCE_REMOVE;
}

/* ---------- 音量快捷滑块（amixer Master） ---------- */
static void on_vol_scale_changed(GtkRange *range, gpointer ud) {
    (void)ud;
    int v = (int)gtk_range_get_value(range);
    gchar *cmd = g_strdup_printf("amixer -q sset Master %d%% 2>/dev/null", v);
    g_spawn_command_line_async(cmd, NULL);
    g_printerr("QYDESKTOPDBG: volume=%d\n", v);
    g_free(cmd);
}

static void on_vol_btn_clicked(GtkWidget *w, gpointer ud) {
    (void)ud;
    GtkWidget *menu = gtk_menu_new();
    GtkWidget *item = gtk_menu_item_new();
    GtkWidget *scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 100, 5);
    gtk_range_set_value(GTK_RANGE(scale), 70);
    gtk_widget_set_size_request(scale, 160, -1);
    gtk_container_add(GTK_CONTAINER(item), scale);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
    g_signal_connect(scale, "value-changed", G_CALLBACK(on_vol_scale_changed), NULL);
    gtk_widget_show_all(menu);
    gtk_menu_attach_to_widget(GTK_MENU(menu), w, NULL);
    gtk_menu_popup_at_widget(GTK_MENU(menu), w, GDK_GRAVITY_SOUTH_WEST, GDK_GRAVITY_NORTH_WEST, NULL);
}

/* 自动化: QYDESKTOP_VOL=70 启动后设置音量 */
static gboolean auto_set_volume(gpointer p) {
    int v = atoi((const char *)p);
    gchar *cmd = g_strdup_printf("amixer -q sset Master %d%% 2>/dev/null", v);
    g_spawn_command_line_async(cmd, NULL);
    g_printerr("QYDESKTOPDBG: volume=%d\n", v);
    g_free(cmd);
    return G_SOURCE_REMOVE;
}

static void build_bar(void) {
    GtkWidget *bar = gtk_event_box_new();
    add_class(bar, "qy-bar");
    gtk_widget_set_size_request(bar, SCREEN_W, BAR_H);
    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_container_add(GTK_CONTAINER(bar), hbox);

    /* 左侧应用菜单按钮（品牌 Logo） */
    GtkWidget *app_btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(app_btn), GTK_RELIEF_NONE);
    add_class(app_btn, "qy-logo-btn");
    GtkWidget *app_hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_container_add(GTK_CONTAINER(app_btn), app_hb);
    GtkWidget *app_txt = gtk_label_new("启元");
    add_class(app_txt, "qy-logo-text");
    gtk_box_pack_start(GTK_BOX(app_hb), app_txt, FALSE, FALSE, 0);
    g_signal_connect(app_btn, "clicked", G_CALLBACK(on_appmenu_clicked), NULL);
    gtk_widget_set_tooltip_text(app_btn, TR("显示应用"));
    gtk_box_pack_start(GTK_BOX(hbox), app_btn, FALSE, FALSE, 6);

    /* 窗口任务栏（中部靠左） */
    taskbar_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
    gtk_box_pack_start(GTK_BOX(hbox), taskbar_box, FALSE, FALSE, 8);

    /* 居中时钟（点击弹出日历） */
    clock_btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(clock_btn), GTK_RELIEF_NONE);
    add_class(clock_btn, "qy-clock");
    clock_label = gtk_label_new("");
    gtk_container_add(GTK_CONTAINER(clock_btn), clock_label);
    gtk_box_set_center_widget(GTK_BOX(hbox), clock_btn);
    g_signal_connect(clock_btn, "clicked", G_CALLBACK(on_clock_clicked), NULL);
    tick(clock_label);
    g_timeout_add_seconds(1, tick, clock_label);

    /* 右侧状态区 */
    GtkWidget *st = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
    GtkWidget *mon_hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 3);
    gtk_widget_set_size_request(mon_hb, 87, 8);
    mon_draw = gtk_drawing_area_new();
    gtk_widget_set_size_request(mon_draw, 87, 6);
    gtk_widget_set_halign(mon_draw, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(mon_draw, GTK_ALIGN_CENTER);
    g_signal_connect(mon_draw, "draw", G_CALLBACK(mon_draw_cb), NULL);
    gtk_widget_set_tooltip_text(mon_draw, TR("系统资源"));
    gtk_box_pack_start(GTK_BOX(mon_hb), mon_draw, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(st), mon_hb, FALSE, FALSE, 6);
    mon_label = gtk_label_new("CPU 0% · MEM 0%");
    add_class(mon_label, "qy-mon-widget");
    gtk_box_pack_start(GTK_BOX(st), mon_label, FALSE, FALSE, 6);
    g_timeout_add_seconds(2, mon_tick, mon_label);
    /* 分辨率快捷切换（写 weston.ini mode=，start-weston.sh 消费） */
    GtkWidget *res_btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(res_btn), GTK_RELIEF_NONE);
    add_class(res_btn, "qy-status-btn");
    res_label = gtk_label_new("1280x800");
    gtk_container_add(GTK_CONTAINER(res_btn), res_label);
    g_signal_connect(res_btn, "clicked", G_CALLBACK(on_res_btn_clicked), NULL);
    gtk_widget_set_tooltip_text(res_btn, TR("分辨率"));
    gtk_box_pack_start(GTK_BOX(st), res_btn, FALSE, FALSE, 0);
    GtkWidget *power = gtk_button_new_with_label("⏻");
    gtk_button_set_relief(GTK_BUTTON(power), GTK_RELIEF_NONE);
    add_class(power, "qy-status-btn");
    g_signal_connect(power, "clicked", G_CALLBACK(on_power_clicked), NULL);
    gtk_widget_set_tooltip_text(power, TR("系统"));
    gtk_box_pack_start(GTK_BOX(st), power, FALSE, FALSE, 0);

    /* 通知显示 */
    notif_label = gtk_label_new("🔔");
    add_class(notif_label, "qy-status-btn");
    gtk_widget_set_tooltip_text(notif_label, TR("通知"));
    gtk_box_pack_start(GTK_BOX(st), notif_label, FALSE, FALSE, 0);

    /* 系统托盘: 网络/声音/剪贴板/截图/锁屏 */
    GtkWidget *tray_hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
    gtk_box_pack_start(GTK_BOX(tray_hb), make_tray_btn("🌐", TR("网络"), "qynet"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tray_hb), make_tray_btn("💾", TR("驱动"), "qydriver"), FALSE, FALSE, 0);
    GtkWidget *vol_btn = gtk_button_new_with_label("🔊");
    gtk_button_set_relief(GTK_BUTTON(vol_btn), GTK_RELIEF_NONE);
    add_class(vol_btn, "qy-status-btn");
    gtk_widget_set_tooltip_text(vol_btn, TR("声音"));
    g_signal_connect(vol_btn, "clicked", G_CALLBACK(on_vol_btn_clicked), NULL);
    gtk_box_pack_start(GTK_BOX(tray_hb), vol_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tray_hb), make_tray_btn("📋", TR("剪贴板"), "qyclip"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tray_hb), make_tray_btn("📷", TR("截图"), "qyshot"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tray_hb), make_tray_btn("🔒", TR("锁屏"), "qylock"), FALSE, FALSE, 0);
    power_btn = gtk_button_new_with_label("⏻");
    gtk_button_set_relief(GTK_BUTTON(power_btn), GTK_RELIEF_NONE);
    add_class(power_btn, "qy-status-btn");
    gtk_widget_set_tooltip_text(power_btn, TR("电源"));
    g_signal_connect(power_btn, "clicked", G_CALLBACK(on_power_btn_clicked), NULL);
    gtk_box_pack_start(GTK_BOX(tray_hb), power_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(st), tray_hb, FALSE, FALSE, 4);
    gtk_widget_set_margin_end(st, 8);
    gtk_box_pack_end(GTK_BOX(hbox), st, FALSE, FALSE, 0);

    gtk_fixed_put(GTK_FIXED(desktop_fixed), bar, 0, 0);
    gtk_widget_show_all(bar);
    g_timeout_add_seconds(1, notif_tick, NULL);
}

/* ---------- 左侧 Dock ---------- */
static void build_dock(void) {
    GtkWidget *dock = gtk_event_box_new();
    add_class(dock, "qy-dock");
    gtk_widget_set_size_request(dock, DOCK_W, SCREEN_H - BAR_H - 8);
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 6);
    gtk_container_add(GTK_CONTAINER(dock), vbox);

    for (int i = 0; i < NAPPS; i++)
        gtk_box_pack_start(GTK_BOX(vbox), dock_icon(&apps[i]), FALSE, FALSE, 0);

    GtkWidget *sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_box_pack_start(GTK_BOX(vbox), sep, FALSE, FALSE, 4);

    /* 底部应用网格 */
    GtkWidget *grid_btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(grid_btn), GTK_RELIEF_NONE);
    add_class(grid_btn, "qy-dock-icon");
    add_class(grid_btn, "c-grid");
    GtkWidget *gl = gtk_label_new("⊞");
    gtk_container_add(GTK_CONTAINER(grid_btn), gl);
    gtk_widget_set_tooltip_text(grid_btn, TR("显示应用"));
    g_signal_connect(grid_btn, "clicked", G_CALLBACK(on_appmenu_clicked), NULL);
    gtk_box_pack_end(GTK_BOX(vbox), grid_btn, FALSE, FALSE, 0);

    gtk_fixed_put(GTK_FIXED(desktop_fixed), dock, 0, BAR_H);
    gtk_widget_show_all(dock);
}

/* ---------- 桌面窗口 ---------- */
static void build_desktop(void) {
    const char *seed_env = getenv("QY_WALL_SEED");   /* 演示/测试: 指定生成种子 */
    /* 优先读取 /etc/qywallpaper.conf 的 wallpaper= 路径（设置中心壁纸页写入） */
    gchar *wall_path = NULL;
    gchar *conf = NULL;
    if (g_file_get_contents("/etc/qywallpaper.conf", &conf, NULL, NULL)) {
        char *line = conf;
        while (line && *line) {
            if (strncmp(line, "wallpaper=", 10) == 0) {
                char *nl = strchr(line, '\n');
                if (nl) *nl = 0;
                if (line[10]) wall_path = g_strdup(line + 10);
                break;
            }
            char *nl = strchr(line, '\n');
            line = nl ? nl + 1 : NULL;
        }
        g_free(conf);
    }
    if (wall_path) {
        wallpaper = gdk_pixbuf_new_from_file(wall_path, NULL);
        g_free(wall_path);
    }
    if (!wallpaper && seed_env && seed_env[0]) {
        wallpaper = gen_wallpaper((guint)strtoul(seed_env, NULL, 10));
    }
    if (!wallpaper) {
        wallpaper = gdk_pixbuf_new_from_file(QY_WALL, NULL);
        if (!wallpaper) wallpaper = gen_wallpaper(0);   /* 文件缺失回退到程序化生成 */
    }
    const char *iv_env = getenv("QY_WALL_INTERVAL");   /* 自动轮换秒数(默认600) */
    int wall_interval = (iv_env && atoi(iv_env) > 0) ? atoi(iv_env) : 600;
    g_timeout_add_seconds(wall_interval, auto_wall_tick, NULL);
    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "qydesktop");
    gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
    gtk_window_set_type_hint(GTK_WINDOW(win), GDK_WINDOW_TYPE_HINT_DESKTOP);
    gtk_window_set_default_size(GTK_WINDOW(win), SCREEN_W, SCREEN_H);
    gtk_window_move(GTK_WINDOW(win), 0, 0);
    gtk_window_set_keep_below(GTK_WINDOW(win), TRUE);

    desktop_fixed = gtk_fixed_new();
    gtk_container_add(GTK_CONTAINER(win), desktop_fixed);

    GtkWidget *darea = gtk_drawing_area_new();
    gtk_widget_set_size_request(darea, SCREEN_W, SCREEN_H);
    gtk_widget_add_events(darea, GDK_BUTTON_PRESS_MASK);
    g_signal_connect(darea, "draw", G_CALLBACK(desk_draw), NULL);
    g_signal_connect(darea, "button-press-event", G_CALLBACK(desk_button_press), NULL);
    gtk_fixed_put(GTK_FIXED(desktop_fixed), darea, 0, 0);

    /* 桌面图标（左上竖排） */
    int x = 110, y = 60, dy = 110;
    gtk_fixed_put(GTK_FIXED(desktop_fixed),
                  desktop_icon("▣", "c-home", TR("主文件夹"), "qyfiles"), x, y);
    gtk_fixed_put(GTK_FIXED(desktop_fixed),
                  desktop_icon("🗑", "c-trash", TR("回收站"), "qyfiles --trash"), x, y + dy);
    gtk_fixed_put(GTK_FIXED(desktop_fixed),
                  desktop_icon("▦", "c-store", TR("软件中心"), "qystore"), x, y + dy * 2);
    gtk_fixed_put(GTK_FIXED(desktop_fixed),
                  desktop_icon(">_", "c-term", TR("终端"), "weston-terminal"), x, y + dy * 3);
    gtk_fixed_put(GTK_FIXED(desktop_fixed),
                  desktop_icon("⚙", "c-settings", TR("设置"), "qysettings"), x, y + dy * 4);
    gtk_fixed_put(GTK_FIXED(desktop_fixed),
                  desktop_icon("▦", "c-mon", TR("系统监视"), "qymon"), x, y + dy * 5);
    gtk_fixed_put(GTK_FIXED(desktop_fixed),
                  desktop_icon("▣", "c-view", TR("图片查看"), "qyview"), x, y + dy * 6);

    gtk_widget_show_all(win);
}

/* ---------- 入口 ---------- */
static void on_clock_clicked(GtkWidget *w, gpointer ud) {
    (void)ud;
    GtkWidget *menu = gtk_menu_new();
    GtkWidget *item = gtk_menu_item_new();
    GtkWidget *cal = gtk_calendar_new();
    gtk_container_add(GTK_CONTAINER(item), cal);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
    gtk_widget_show_all(menu);
    gtk_menu_attach_to_widget(GTK_MENU(menu), w, NULL);
    gtk_menu_popup_at_widget(GTK_MENU(menu), w, GDK_GRAVITY_SOUTH_WEST, GDK_GRAVITY_NORTH_WEST, NULL);
    g_printerr("QYDESKTOPDBG: calendar shown\n");
}

static gboolean auto_calendar(gpointer p) {
    (void)p;
    on_clock_clicked(clock_btn, NULL);
    return G_SOURCE_REMOVE;
}

static gboolean auto_about(gpointer p);

int main(int argc, char **argv) {
    signal(SIGCHLD, SIG_DFL);
    gtk_init(&argc, &argv);
    load_theme();
    build_desktop();
    build_bar();
    build_dock();
    /* 首启向导 */
    if (access("/etc/.qywelcomed", F_OK) != 0) launch_cmd("qywelcome");
    g_timeout_add_seconds(1, taskbar_tick, NULL);
    g_timeout_add_seconds(2, dock_tick, NULL);
    /* 自动化: QYDESKTOP_RES=1024x768 启动后自动设置分辨率 */
    const char *res_env = g_getenv("QYDESKTOP_RES");
    if (res_env && res_env[0])
        g_timeout_add(600, auto_res_apply, g_strdup(res_env));
    /* 自动化: QYDESKTOP_RIGHTCLICK=1 启动后模拟桌面右键 */
    if (g_getenv("QYDESKTOP_RIGHTCLICK"))
        g_timeout_add(1000, auto_desktop_rightclick, NULL);
    /* 自动化: QYDESKTOP_VOL=70 启动后设置音量 */
    const char *vol_env = g_getenv("QYDESKTOP_VOL");
    if (vol_env && vol_env[0])
        g_timeout_add(700, auto_set_volume, (gpointer)vol_env);
    /* 自动化: QYDESKTOP_ABOUT=1 启动后弹出关于窗口 */
    if (g_getenv("QYDESKTOP_ABOUT"))
        g_timeout_add(1200, (GSourceFunc)auto_about, NULL);
    /* 自动化: QYDESKTOP_CALENDAR=1 启动后弹出日历 */
    if (g_getenv("QYDESKTOP_CALENDAR"))
        g_timeout_add(1000, (GSourceFunc)auto_calendar, NULL);
    /* 自动化: QYDESKTOP_POWER=1 启动后弹出电源菜单 */
    if (g_getenv("QYDESKTOP_POWER"))
        g_timeout_add(1100, (GSourceFunc)auto_power_menu, NULL);
    gtk_main();
    return 0;
}

static gboolean auto_about(gpointer p) {
    (void)p;
    menu_about(NULL, NULL);
    return G_SOURCE_REMOVE;
}