/* qydesktop - 启元桌面 shell（传统模式, 对标 Cinnamon/Xfce 交互）
 * 顶栏任务栏：⊞应用菜单 | 运行中窗口按钮 | 时钟
 * 桌面层：钉底全屏壁纸(DESKTOP hint) + 应用图标(点击启动)
 */
#include <gtk/gtk.h>
#include <time.h>
#include <string.h>
#include <signal.h>
#include <sys/wait.h>
#include <gdk-pixbuf/gdk-pixbuf.h>

/* ---------- 应用注册表 ---------- */
typedef struct {
    const char *name;
    const char *icon;
    const char *cmdline;
    GPid        pid;        /* 运行跟踪, 0 = 未运行 */
} AppEntry;

static AppEntry apps[] = {
    { "文件管理器", "🗂", "qyfiles",         0 },
    { "终端",       ">_", "weston-terminal", 0 },
    { "系统设置",   "⚙",  "qysettings",      0 },
};
#define NAPPS ((int)(sizeof apps / sizeof apps[0]))

static GtkWidget *taskbar_box = NULL;

/* ---------- 时钟 ---------- */
static gboolean tick(gpointer data) {
    char buf[64];
    time_t t = time(NULL);
    struct tm tm_;
    localtime_r(&t, &tm_);
    strftime(buf, sizeof buf, "%m-%d %H:%M", &tm_);
    gtk_label_set_text(GTK_LABEL(data), buf);
    return G_SOURCE_CONTINUE;
}

/* ---------- 任务栏刷新 ---------- */
static void on_task_clicked(GtkButton *btn, gpointer ud);

static void refresh_taskbar(void) {
    if (!taskbar_box) return;
    GList *ch = gtk_container_get_children(GTK_CONTAINER(taskbar_box));
    for (GList *it = ch; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(ch);
    for (int i = 0; i < NAPPS; i++) {
        if (apps[i].pid <= 0) continue;
        gchar *label = g_strdup_printf("▸ %s", apps[i].name);
        GtkWidget *b = gtk_button_new_with_label(label);
        gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
        g_free(label);
        g_object_set_data(G_OBJECT(b), "app", &apps[i]);
        g_signal_connect(b, "clicked", G_CALLBACK(on_task_clicked), NULL);
        gtk_box_pack_start(GTK_BOX(taskbar_box), b, FALSE, FALSE, 2);
        gtk_widget_show_all(b);
    }
}

static void child_watch(GPid pid, gint status, gpointer ud) {
    AppEntry *a = (AppEntry *)ud;
    a->pid = 0;
    refresh_taskbar();
    g_spawn_close_pid(pid);
}

/* 点任务栏按钮 = 关闭对应应用(简化: 关进程) */
static void on_task_clicked(GtkButton *btn, gpointer ud) {
    AppEntry *a = g_object_get_data(G_OBJECT(btn), "app");
    if (a && a->pid > 0) kill(a->pid, SIGTERM);
}

/* ---------- 启动 ---------- */
static void launch_app(AppEntry *a) {
    if (a->pid > 0) return; /* 已运行 */
    GError *err = NULL;
    GPid pid = 0;
    gchar **argv = NULL;
    if (!g_shell_parse_argv(a->cmdline, NULL, &argv, &err)) {
        g_printerr("parse failed: %s\n", err ? err->message : "?");
        if (err) g_error_free(err);
        return;
    }
    if (g_spawn_async(NULL, argv, NULL,
                      G_SPAWN_DO_NOT_REAP_CHILD | G_SPAWN_SEARCH_PATH,
                      NULL, NULL, &pid, &err)) {
        a->pid = pid;
        g_child_watch_add(pid, child_watch, a);
        refresh_taskbar();
    } else {
        g_printerr("launch failed: %s\n", err ? err->message : "?");
        if (err) g_error_free(err);
    }
    g_strfreev(argv);
}

/* ---------- 应用菜单(弹出式开始菜单) ---------- */
static GtkWidget *app_menu = NULL;

static void menu_launch(GtkButton *btn, gpointer ud) {
    AppEntry *a = (AppEntry *)ud;
    launch_app(a);
    gtk_widget_hide(app_menu);
}

static void build_app_menu(void) {
    app_menu = gtk_window_new(GTK_WINDOW_POPUP);
    gtk_window_set_decorated(GTK_WINDOW(app_menu), FALSE);
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 8);
    GtkWidget *title = gtk_label_new("应  用");
    gtk_widget_set_halign(title, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), title, FALSE, FALSE, 2);
    for (int i = 0; i < NAPPS; i++) {
        GtkWidget *b = gtk_button_new_with_label(apps[i].name);
        GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
        gtk_box_pack_start(GTK_BOX(h), gtk_label_new(apps[i].icon), FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(h), b, TRUE, TRUE, 0);
        g_signal_connect(b, "clicked", G_CALLBACK(menu_launch), &apps[i]);
        gtk_box_pack_start(GTK_BOX(vbox), h, FALSE, FALSE, 0);
    }
    gtk_container_add(GTK_CONTAINER(app_menu), vbox);
}

static void toggle_menu(GtkWidget *btn, gpointer ud) {
    if (!gtk_widget_get_visible(app_menu)) {
        gtk_window_move(GTK_WINDOW(app_menu), 6, 32);
        gtk_widget_show_all(app_menu);
    } else gtk_widget_hide(app_menu);
}

/* ---------- 壁纸 ---------- */
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

/* ---------- 桌面图标 ---------- */
static gboolean icon_click(GtkWidget *btn, GdkEventButton *ev, gpointer ud) {
    if (ev->type == GDK_2BUTTON_PRESS || ev->button == 1) {
        launch_app((AppEntry *)ud);
        return TRUE;
    }
    return FALSE;
}

static GtkWidget *make_desktop_icon(AppEntry *a) {
    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 3);
    GtkWidget *btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
    GtkWidget *ic = gtk_label_new(a->icon);
    PangoAttrList *big = pango_attr_list_new();
    pango_attr_list_insert(big, pango_attr_size_new_absolute(34 * PANGO_SCALE));
    gtk_label_set_attributes(GTK_LABEL(ic), big);
    pango_attr_list_unref(big);
    GtkWidget *lb = gtk_label_new(a->name);
    gtk_widget_override_color(lb, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){1, 1, 1, 1});
    gtk_container_add(GTK_CONTAINER(btn), v);
    gtk_box_pack_start(GTK_BOX(v), ic, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v), lb, FALSE, FALSE, 0);
    g_signal_connect(btn, "button-press-event", G_CALLBACK(icon_click), a);
    return btn;
}

/* ---------- 顶栏 + 桌面 ---------- */
static void build_bar(void) {
    GtkWidget *bar = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(bar), "qydesktop-bar");
    gtk_window_set_decorated(GTK_WINDOW(bar), FALSE);
    gtk_window_set_type_hint(GTK_WINDOW(bar), GDK_WINDOW_TYPE_HINT_DOCK);
    gtk_window_set_default_size(GTK_WINDOW(bar), 1280, 30);
    gtk_window_move(GTK_WINDOW(bar), 0, 0);

    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_container_add(GTK_CONTAINER(bar), hbox);

    GtkWidget *menu_btn = gtk_button_new_with_label("⊞ 应用");
    gtk_button_set_relief(GTK_BUTTON(menu_btn), GTK_RELIEF_NONE);
    g_signal_connect(menu_btn, "clicked", G_CALLBACK(toggle_menu), NULL);
    gtk_box_pack_start(GTK_BOX(hbox), menu_btn, FALSE, FALSE, 2);

    taskbar_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_box_pack_start(GTK_BOX(hbox), taskbar_box, TRUE, TRUE, 4);

    GtkWidget *clock = gtk_label_new("");
    gtk_widget_set_margin_end(clock, 10);
    gtk_box_pack_start(GTK_BOX(hbox), clock, FALSE, FALSE, 0);
    tick(clock);
    g_timeout_add_seconds(1, tick, clock);

    gtk_widget_show_all(bar);
}

static void build_desktop(void) {
    wallpaper = gdk_pixbuf_new_from_file("/usr/share/backgrounds/qiyuan.png", NULL);
    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "qydesktop");
    gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
    gtk_window_set_type_hint(GTK_WINDOW(win), GDK_WINDOW_TYPE_HINT_DESKTOP);
    gtk_window_set_default_size(GTK_WINDOW(win), 1280, 770);
    gtk_window_move(GTK_WINDOW(win), 0, 30);

    GtkWidget *fixed = gtk_fixed_new();
    gtk_container_add(GTK_CONTAINER(win), fixed);

    GtkWidget *darea = gtk_drawing_area_new();
    gtk_widget_set_size_request(darea, 1280, 770);
    g_signal_connect(darea, "draw", G_CALLBACK(desk_draw), NULL);
    gtk_fixed_put(GTK_FIXED(fixed), darea, 0, 0);

    for (int i = 0; i < NAPPS; i++) {
        GtkWidget *icn = make_desktop_icon(&apps[i]);
        gtk_fixed_put(GTK_FIXED(fixed), icn, 12, 12 + i * 92);
    }
    gtk_widget_show_all(win);
}

int main(int argc, char **argv) {
    signal(SIGCHLD, SIG_DFL);
    gtk_init(&argc, &argv);
    build_bar();
    build_app_menu();
    build_desktop();
    gtk_main();
    return 0;
}
