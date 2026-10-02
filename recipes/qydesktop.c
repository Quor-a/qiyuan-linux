/* qydesktop - 启元桌面 shell：顶栏（启动器+任务栏+时钟）+ 桌面图标 + 应用启动器 */
#include <gtk/gtk.h>
#include <time.h>
#include <string.h>
#include <gdk-pixbuf/gdk-pixbuf.h>

static gboolean tick(gpointer data) {
    GtkLabel *l = GTK_LABEL(data);
    time_t t = time(NULL);
    struct tm tm_;
    localtime_r(&t, &tm_);
    char buf[64];
    strftime(buf, sizeof buf, "%Y-%m-%d %H:%M:%S", &tm_);
    gtk_label_set_text(l, buf);
    return G_SOURCE_CONTINUE;
}


/* ---- 壁纸 ---- */
static GdkPixbuf *wallpaper = NULL;

static gboolean desk_draw(GtkWidget *w, cairo_t *cr, gpointer ud) {
    guint width, height;
    width = gtk_widget_get_allocated_width(w);
    height = gtk_widget_get_allocated_height(w);
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

/* ---- 应用注册表 ---- */
typedef struct { const char *name; const char *icon; const char *cmdline; } AppEntry;
static const AppEntry apps[] = {
    { "终端",   ">_", "weston-terminal" },
    { "文件",   "📁", "qyfiles" },
    { "设置",   "⚙",  "true" },  /* 占位: 系统设置待开发 */
};
#define NAPPS (sizeof apps / sizeof apps[0])
static GtkWidget *launcher = NULL;

static void launch_cmd(const char *cmd) {
    GError *err = NULL;
    if (!g_spawn_command_line_async(cmd, &err)) {
        g_printerr("launch failed: %s\n", err->message);
        g_error_free(err);
    }
}

static void launch_app(GtkButton *btn, gpointer ud) {
    const char *cmd = (const char *)ud;
    if (!cmd || strcmp(cmd, "true") == 0) return;
    launch_cmd(cmd);
    if (launcher) gtk_widget_hide(launcher);
}

static void toggle_launcher(GtkButton *btn, gpointer ud) {
    if (!launcher) return;
    if (gtk_widget_get_visible(launcher)) gtk_widget_hide(launcher);
    else gtk_widget_show_all(launcher);
}

static gboolean on_launcher_delete(GtkWidget *w, GdkEvent *e, gpointer ud) {
    gtk_widget_hide(w);
    return TRUE; /* 阻止销毁, 只隐藏 */
}

/* 桌面图标: 一个图标 = 图上文字下的 Button */
static GtkWidget *make_desktop_icon(const AppEntry *a) {
    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_margin_start(v, 14);
    gtk_widget_set_margin_top(v, 14);
    GtkWidget *ic = gtk_label_new(a->icon);
    gtk_widget_set_name(ic, "app-icon");
    PangoAttrList *big = pango_attr_list_new();
    pango_attr_list_insert(big, pango_attr_size_new_absolute(32 * PANGO_SCALE));
    gtk_label_set_attributes(GTK_LABEL(ic), big);
    pango_attr_list_unref(big);
    GtkWidget *lb = gtk_label_new(a->name);
    GtkWidget *btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
    gtk_container_add(GTK_CONTAINER(btn), v);
    gtk_box_pack_start(GTK_BOX(v), ic, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v), lb, FALSE, FALSE, 0);
    g_signal_connect(btn, "clicked", G_CALLBACK(launch_app), (gpointer)a->cmdline);
    return btn;
}

static void build_launcher(GtkApplication *app) {
    launcher = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(launcher), "应用启动器");
    GdkGeometry geo = { .max_width = 1920, .max_height = 1080 };
    gtk_window_set_geometry_hints(GTK_WINDOW(launcher), NULL, &geo, GDK_HINT_MAX_SIZE);
    gtk_window_set_default_size(GTK_WINDOW(launcher), 300, 220);
    gtk_window_set_resizable(GTK_WINDOW(launcher), TRUE);
    g_signal_connect(launcher, "delete-event", G_CALLBACK(on_launcher_delete), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 10);
    for (unsigned i = 0; i < NAPPS; i++) {
        GtkWidget *b = gtk_button_new_with_label(apps[i].name);
        g_signal_connect(b, "clicked", G_CALLBACK(launch_app), (gpointer)apps[i].cmdline);
        gtk_box_pack_start(GTK_BOX(vbox), b, FALSE, FALSE, 0);
    }
    GtkWidget *quit = gtk_button_new_with_label("退出桌面会话");
    g_signal_connect(quit, "clicked", G_CALLBACK(gtk_main_quit), NULL);
    gtk_box_pack_end(GTK_BOX(vbox), quit, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(launcher), vbox);
}

static void activate(GtkApplication *app, gpointer ud) {
    /* 顶栏: 应用按钮 | 任务栏(占位) | 时钟 */
    GtkWidget *bar = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(bar), "qydesktop-bar");
    GdkGeometry geo = { .max_width = 1920, .max_height = 1080 };
    gtk_window_set_geometry_hints(GTK_WINDOW(bar), NULL, &geo, GDK_HINT_MAX_SIZE);
    gtk_window_set_default_size(GTK_WINDOW(bar), 1280, 30);
    gtk_window_set_decorated(GTK_WINDOW(bar), FALSE);
    gtk_window_set_type_hint(GTK_WINDOW(bar), GDK_WINDOW_TYPE_HINT_DOCK);
    gtk_window_set_resizable(GTK_WINDOW(bar), TRUE);

    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_container_add(GTK_CONTAINER(bar), hbox);

    GtkWidget *menu_btn = gtk_button_new_with_label("应用");
    g_signal_connect(menu_btn, "clicked", G_CALLBACK(toggle_launcher), NULL);
    gtk_box_pack_start(GTK_BOX(hbox), menu_btn, FALSE, FALSE, 4);

    GtkWidget *tasks = gtk_label_new("任务栏(开发中)");
    gtk_widget_set_halign(tasks, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(hbox), tasks, TRUE, TRUE, 8);

    GtkWidget *clock = gtk_label_new("");
    gtk_widget_set_halign(clock, GTK_ALIGN_END);
    gtk_widget_set_margin_end(clock, 12);
    gtk_box_pack_start(GTK_BOX(hbox), clock, FALSE, FALSE, 0);
    tick(clock);
    g_timeout_add_seconds(1, tick, clock);

    build_launcher(app);

    /* 桌面窗口: 左侧纵向排应用图标 */
    GtkWidget *desk = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(desk), "qydesktop");
    GdkGeometry dgeo = { .max_width = 1920, .max_height = 1080 };
    gtk_window_set_geometry_hints(GTK_WINDOW(desk), NULL, &dgeo, GDK_HINT_MAX_SIZE);
    gtk_window_set_default_size(GTK_WINDOW(desk), 1280, 770);
    gtk_window_set_resizable(GTK_WINDOW(desk), TRUE);
    wallpaper = gdk_pixbuf_new_from_file("/usr/share/backgrounds/qiyuan.png", NULL);
    GtkWidget *darea = gtk_drawing_area_new();
    gtk_widget_set_hexpand(darea, TRUE);
    gtk_widget_set_vexpand(darea, TRUE);
    g_signal_connect(darea, "draw", G_CALLBACK(desk_draw), NULL);
    /* 图标层叠放在壁纸上: 固定容器 */
    GtkWidget *fixed = gtk_fixed_new();
    gtk_container_add(GTK_CONTAINER(desk), fixed);
    gtk_fixed_put(GTK_FIXED(fixed), darea, 0, 0);
    gtk_widget_set_size_request(darea, 1280, 770);
    for (unsigned i = 0; i < NAPPS; i++) {
        GtkWidget *icn = make_desktop_icon(&apps[i]);
        gtk_fixed_put(GTK_FIXED(fixed), icn, 14, 14 + i * 86);
    }
    gtk_widget_show_all(fixed);

    gtk_widget_show_all(bar);
    gtk_widget_show_all(desk);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.desktop", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int rc = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return rc;
}
