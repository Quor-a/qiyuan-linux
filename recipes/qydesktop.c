/* qydesktop - 启元桌面 shell（Ubuntu GNOME 风格布局）
 * 顶栏: 活动(左) | 运行窗口(中左) | 时钟(居中) | 状态区(右)
 * 左侧垂直 Dock: 深色半透明条 + 彩色圆角图标 + 底部九点应用网格
 * 桌面: 品牌壁纸 + 主文件夹图标
 */
#include "qyl10n.h"
#include <gtk/gtk.h>
#include <time.h>
#include <string.h>
#include <signal.h>
#include <dirent.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <gdk-pixbuf/gdk-pixbuf.h>

/* ---------- 应用注册表 ---------- */
typedef struct {
    const char *name;
    const char *icon;
    const char *color;      /* Dock 图标底色 */
    const char *cmdline;
    const char *exe;        /* /proc/<pid>/comm 名 */
    GPid        pid;
} AppEntry;

static AppEntry apps[] = {
    { "文件", "▤", "#E95420", "qyfiles",         "qyfiles",         0 },
    { "终端", ">_", "#2C2C2C", "weston-terminal", "weston-termi",    0 },
    { "设置", "⚙",  "#77216F", "qysettings",      "qysettings",      0 },
};
#define NAPPS ((int)(sizeof apps / sizeof apps[0]))

static GtkWidget *taskbar_box = NULL;
static GtkWidget *clock_label = NULL;

/* ---------- 时钟 ---------- */
static gboolean tick(gpointer data) {
    char buf[64];
    time_t t = time(NULL);
    struct tm tm_;
    localtime_r(&t, &tm_);
    strftime(buf, sizeof buf, TR("%m月%d日 %H:%M"), &tm_);
    gtk_label_set_text(GTK_LABEL(clock_label), buf);
    return G_SOURCE_CONTINUE;
}

/* ---------- 真窗口枚举: 扫 /proc/<pid>/comm ---------- */
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

static void on_task_clicked(GtkButton *btn, gpointer ud) {
    AppEntry *a = (AppEntry *)ud;
    if (a && a->pid > 0) kill(a->pid, SIGTERM);
}

static void refresh_taskbar(void) {
    if (!taskbar_box) return;
    GList *ch = gtk_container_get_children(GTK_CONTAINER(taskbar_box));
    for (GList *it = ch; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(ch);
    for (int i = 0; i < NAPPS; i++) {
        int pid = proc_running(apps[i].exe);
        apps[i].pid = pid;
        if (pid <= 0) continue;
        gchar *label = g_strdup_printf("%s", apps[i].name);
        GtkWidget *b = gtk_button_new_with_label(label);
        gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
        gtk_widget_override_color(b, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
        g_free(label);
        g_signal_connect(b, "clicked", G_CALLBACK(on_task_clicked), &apps[i]);
        gtk_box_pack_start(GTK_BOX(taskbar_box), b, FALSE, FALSE, 2);
        gtk_widget_show_all(b);
    }
}

static gboolean taskbar_tick(gpointer ud) { refresh_taskbar(); return G_SOURCE_CONTINUE; }

/* ---------- 启动 ---------- */
static void launch_cmd(const char *cmd) {
    GError *err = NULL;
    gchar **argv = NULL;
    if (!g_shell_parse_argv(cmd, NULL, &argv, &err)) { if (err) g_error_free(err); return; }
    g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &err);
    if (err) { g_printerr("launch: %s\n", err->message); g_error_free(err); }
    g_strfreev(argv);
}

static void dock_click(GtkButton *btn, gpointer ud) { launch_cmd(((AppEntry *)ud)->cmdline); }

/* ---------- Dock 彩色图标 ---------- */
static GtkWidget *dock_icon(AppEntry *a) {
    GtkWidget *btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
    GdkRGBA c;
    gdk_rgba_parse(&c, a->color);
    gtk_widget_override_background_color(btn, GTK_STATE_FLAG_NORMAL, &c);
    GtkWidget *ic = gtk_label_new(a->icon);
    PangoAttrList *big = pango_attr_list_new();
    pango_attr_list_insert(big, pango_attr_size_new_absolute(24 * PANGO_SCALE));
    gtk_label_set_attributes(GTK_LABEL(ic), big);
    pango_attr_list_unref(big);
    gtk_widget_override_color(ic, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
    gtk_widget_set_size_request(btn, 50, 50);
    gtk_container_add(GTK_CONTAINER(btn), ic);
    gtk_widget_set_tooltip_text(btn, a->name);
    g_signal_connect(btn, "clicked", G_CALLBACK(dock_click), a);
    return btn;
}

static void menu_click(GtkButton *btn, gpointer ud) { launch_cmd("qyappmenu"); }

/* ---------- 左侧垂直 Dock ---------- */
static void build_dock(void) {
    GtkWidget *dock = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(dock), "qydesktop-dock");
    gtk_window_set_decorated(GTK_WINDOW(dock), FALSE);
    gtk_window_set_type_hint(GTK_WINDOW(dock), GDK_WINDOW_TYPE_HINT_DOCK);
    gtk_window_set_default_size(GTK_WINDOW(dock), 62, 768);
    gtk_window_move(GTK_WINDOW(dock), 0, 28);

    GdkRGBA bg = {0.07, 0.07, 0.09, 0.95};
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 6);
    gtk_widget_override_background_color(vbox, GTK_STATE_FLAG_NORMAL, &bg);
    gtk_container_add(GTK_CONTAINER(dock), vbox);

    for (int i = 0; i < NAPPS; i++)
        gtk_box_pack_start(GTK_BOX(vbox), dock_icon(&apps[i]), FALSE, FALSE, 0);

    gtk_box_pack_start(GTK_BOX(vbox), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 2);

    /* 底部九点网格 = 应用菜单 */
    GtkWidget *grid_btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(grid_btn), GTK_RELIEF_NONE);
    gtk_widget_override_background_color(grid_btn, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){0.25,0.25,0.28,1});
    GtkWidget *gl = gtk_label_new("⊞");
    PangoAttrList *big = pango_attr_list_new();
    pango_attr_list_insert(big, pango_attr_size_new_absolute(24 * PANGO_SCALE));
    gtk_label_set_attributes(GTK_LABEL(gl), big);
    pango_attr_list_unref(big);
    gtk_widget_override_color(gl, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
    gtk_widget_set_size_request(grid_btn, 50, 50);
    gtk_container_add(GTK_CONTAINER(grid_btn), gl);
    gtk_widget_set_tooltip_text(grid_btn, TR("显示应用"));
    g_signal_connect(grid_btn, "clicked", G_CALLBACK(menu_click), NULL);
    gtk_box_pack_end(GTK_BOX(vbox), grid_btn, FALSE, FALSE, 0);

    gtk_widget_show_all(dock);
}

/* ---------- 顶栏 (活动 | 窗口 | 时钟 | 状态) ---------- */
static void on_activities(GtkButton *b, gpointer ud) { launch_cmd("qyappmenu"); }

static void build_bar(void) {
    GtkWidget *bar = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(bar), "qydesktop-bar");
    gtk_window_set_decorated(GTK_WINDOW(bar), FALSE);
    gtk_window_set_type_hint(GTK_WINDOW(bar), GDK_WINDOW_TYPE_HINT_DOCK);
    gtk_window_set_default_size(GTK_WINDOW(bar), 1280, 28);
    gtk_window_move(GTK_WINDOW(bar), 0, 0);

    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_override_background_color(hbox, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){0.03,0.03,0.04,1});
    gtk_container_add(GTK_CONTAINER(bar), hbox);

    GtkWidget *act = gtk_button_new_with_label(TR("活动"));
    gtk_button_set_relief(GTK_BUTTON(act), GTK_RELIEF_NONE);
    gtk_widget_override_color(act, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
    g_signal_connect(act, "clicked", G_CALLBACK(on_activities), NULL);
    gtk_box_pack_start(GTK_BOX(hbox), act, FALSE, FALSE, 6);

    /* 运行中窗口按钮 */
    taskbar_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
    gtk_box_pack_start(GTK_BOX(hbox), taskbar_box, FALSE, FALSE, 4);

    /* 居中时钟 */
    clock_label = gtk_label_new("");
    gtk_widget_override_color(clock_label, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
    gtk_box_set_center_widget(GTK_BOX(hbox), clock_label);
    tick(clock_label);
    g_timeout_add_seconds(1, tick, clock_label);

    /* 右侧状态区 */
    GtkWidget *st = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *l1 = gtk_label_new("⌨");
    GtkWidget *l2 = gtk_label_new("🔈");
    GtkWidget *l3 = gtk_label_new("⏻");
    for (int i = 0; i < 3; i++) {}
    gtk_widget_override_color(l1, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
    gtk_widget_override_color(l2, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
    gtk_widget_override_color(l3, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
    gtk_box_pack_start(GTK_BOX(st), l1, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(st), l2, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(st), l3, FALSE, FALSE, 0);
    gtk_widget_set_margin_end(st, 10);
    gtk_box_pack_end(GTK_BOX(hbox), st, FALSE, FALSE, 0);

    gtk_widget_show_all(bar);
}

/* ---------- 桌面 (壁纸 + 主文件夹) ---------- */
static GdkPixbuf *wallpaper = NULL;

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
        cairo_set_source_rgb(cr, 0.07, 0.10, 0.17);
        cairo_paint(cr);
    }
    return FALSE;
}

static gboolean home_click(GtkWidget *btn, GdkEventButton *ev, gpointer ud) {
    launch_cmd("qyfiles");
    return TRUE;
}

static void build_desktop(void) {
    wallpaper = gdk_pixbuf_new_from_file("/usr/share/backgrounds/qiyuan.png", NULL);
    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "qydesktop");
    gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
    gtk_window_set_type_hint(GTK_WINDOW(win), GDK_WINDOW_TYPE_HINT_DESKTOP);
    gtk_window_set_default_size(GTK_WINDOW(win), 1280, 772);
    gtk_window_move(GTK_WINDOW(win), 0, 28);

    GtkWidget *fixed = gtk_fixed_new();
    gtk_container_add(GTK_CONTAINER(win), fixed);

    GtkWidget *darea = gtk_drawing_area_new();
    gtk_widget_set_size_request(darea, 1280, 772);
    g_signal_connect(darea, "draw", G_CALLBACK(desk_draw), NULL);
    gtk_fixed_put(GTK_FIXED(fixed), darea, 0, 0);

    /* 主文件夹 (Dock 右侧, 上对齐) */
    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    GtkWidget *btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
    GtkWidget *ic = gtk_label_new("▣");
    PangoAttrList *big = pango_attr_list_new();
    pango_attr_list_insert(big, pango_attr_size_new_absolute(34 * PANGO_SCALE));
    gtk_label_set_attributes(GTK_LABEL(ic), big);
    pango_attr_list_unref(big);
    gtk_widget_override_color(ic, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,0.85,0.5,1});
    GtkWidget *lb = gtk_label_new(TR("主文件夹"));
    gtk_widget_override_color(lb, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1,1,1,1});
    gtk_container_add(GTK_CONTAINER(btn), v);
    gtk_box_pack_start(GTK_BOX(v), ic, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v), lb, FALSE, FALSE, 0);
    g_signal_connect(btn, "button-press-event", G_CALLBACK(home_click), NULL);
    gtk_fixed_put(GTK_FIXED(fixed), btn, 88, 14);

    gtk_widget_show_all(win);
}

int main(int argc, char **argv) {
    signal(SIGCHLD, SIG_DFL);
    gtk_init(&argc, &argv);
    build_bar();
    build_dock();
    build_desktop();
    /* 首启向导: 未配置过则拉起 */
    if (access("/etc/.qywelcomed", F_OK) != 0) launch_cmd("qywelcome");
    g_timeout_add_seconds(2, taskbar_tick, NULL);
    gtk_main();
    return 0;
}
