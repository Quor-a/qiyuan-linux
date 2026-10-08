/* qyswitcher.c — 启元窗口切换器（Alt-Tab）
 * 弹出式窗口列表（X11 枚举），点击激活窗口。
 * 自动化: QYSWITCH_AUTO=1 启动后自动枚举；QYSWITCH_DISPLAY 指定 DISPLAY（默认 :0）。
 */
#include <gtk/gtk.h>
#include <string.h>
#include "qytheme.h"
#include "qyl10n.h"

static GtkWidget *listbox = NULL;
static GtkWidget *status_label = NULL;
static GtkWidget *win = NULL;

/* 枚举 X 窗口 */
static char **fetch_windows(int *out_n) {
    const char *dpy = g_getenv("QYSWITCH_DISPLAY");
    if (!dpy) dpy = ":0";
    gchar *cmd = g_strdup_printf("DISPLAY=%s /usr/bin/qysw-x11", dpy);
    gchar *out = NULL;
    if (!g_spawn_command_line_sync(cmd, &out, NULL, NULL, NULL) || !out) {
        g_free(cmd);
        g_free(out);
        if (out_n) *out_n = 0;
        return NULL;
    }
    g_free(cmd);
    gchar **lines = g_strsplit(out, "\n", 0);
    g_free(out);
    int n = 0;
    while (lines && lines[n] && lines[n][0]) n++;
    if (out_n) *out_n = n;
    return lines;
}

static void clear_rows(void) {
    gtk_container_foreach(GTK_CONTAINER(listbox), (GtkCallback)gtk_widget_destroy, NULL);
}

static void on_row_clicked(GtkWidget *w, gpointer ud);

/* 已知启元应用（用于检测运行中） */
static const char *known_apps[] = {
    "qyfiles", "qyedit", "qyterm", "qysettings", "qymon", "qynet",
    "qystore", "qybrowser", "qyshot", "qyclip", "qylock", "qysearch",
    "qymedia", "qyswitcher", "qyview", "qyarc", "qyctl", "qywallpaper",
    "qydesktop", "qyappmenu", "qyusers", "qysudo",
};
#define NKNOWN ((int)(sizeof known_apps / sizeof known_apps[0]))

/* 运行中启元应用 */
static void add_running_apps(void) {
    gchar *out = NULL;
    if (!g_spawn_command_line_sync("pgrep -a -f /usr/bin/qy", &out, NULL, NULL, NULL) || !out) {
        g_free(out);
        return;
    }
    gchar **lines = g_strsplit(out, "\n", 0);
    g_free(out);
    int shown = 0;
    for (int i = 0; lines && lines[i]; i++) {
        if (!lines[i][0]) continue;
        /* 行: pid /usr/bin/name ... */
        char *name = strrchr(lines[i], '/');
        if (!name) continue;
        name++;
        char *space = strchr(name, ' ');
        if (space) *space = 0;
        for (int k = 0; k < NKNOWN; k++) {
            if (strcmp(name, known_apps[k]) == 0) {
                GtkWidget *row = gtk_button_new_with_label(
                    g_strdup_printf("● %s", name));
                gtk_widget_set_halign(row, GTK_ALIGN_FILL);
                gtk_widget_set_tooltip_text(row, TR("已运行"));
                g_signal_connect(row, "clicked", G_CALLBACK(on_row_clicked),
                                 g_strdup(name));
                gtk_list_box_insert(GTK_LIST_BOX(listbox), row, -1);
                shown++;
                break;
            }
        }
    }
    g_strfreev(lines);
    (void)shown;
}

static void on_row_clicked(GtkWidget *w, gpointer ud) {
    (void)w;
    const char *id = (const char *)ud;
    /* 若是已知应用名则启动 */
    for (int k = 0; k < NKNOWN; k++) {
        if (strcmp(id, known_apps[k]) == 0) {
            gchar *cmd = g_strdup_printf("%s &", id);
            g_spawn_command_line_async(cmd, NULL);
            g_free(cmd);
            g_free(ud);
            return;
        }
    }
    /* 否则视为 X11 窗口 id 激活 */
    const char *dpy = g_getenv("QYSWITCH_DISPLAY");
    if (!dpy) dpy = ":0";
    gchar *cmd = g_strdup_printf("DISPLAY=%s /usr/bin/qysw-x11 -a %s", dpy, id);
    g_spawn_command_line_async(cmd, NULL);
    g_free(cmd);
    g_free(ud);
}

/* 填充窗口列表 */
static void populate(void) {
    clear_rows();
    int n = 0;
    gchar **lines = fetch_windows(&n);
    if (!n) {
        gtk_label_set_text(GTK_LABEL(status_label), TR("未找到窗口"));
        gtk_widget_show_all(listbox);
        return;
    }
    for (int i = 0; i < n; i++) {
        char *line = lines[i];
        char *bar = strchr(line, '|');
        if (!bar) continue;
        *bar = 0;
        const char *id = line;
        const char *name = bar + 1;
        GtkWidget *row = gtk_button_new_with_label(name);
        gtk_widget_set_halign(row, GTK_ALIGN_FILL);
        gtk_widget_set_tooltip_text(row, id);
        g_signal_connect(row, "clicked", G_CALLBACK(on_row_clicked), g_strdup(id));
        gtk_list_box_insert(GTK_LIST_BOX(listbox), row, -1);
    }
    g_strfreev(lines);
    /* 运行中启元应用 */
    add_running_apps();
    char st[128];
    g_snprintf(st, sizeof st, "%s %d · %s", TR("窗口"), n, TR("已运行应用"));
    gtk_label_set_text(GTK_LABEL(status_label), st);
    gtk_widget_show_all(listbox);
}

static void on_refresh(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    populate();
}

static gboolean auto_sw(gpointer p) {
    (void)p;
    populate();
    return G_SOURCE_REMOVE;
}

static void activate(GtkApplication *app, gpointer ud) {
    (void)ud;
    qy_load_theme();
    win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("窗口切换器"));
    gtk_window_set_default_size(GTK_WINDOW(win), 420, 320);
    gtk_window_set_position(GTK_WINDOW(win), GTK_WIN_POS_CENTER);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_widget_set_margin_start(vbox, 10);
    gtk_widget_set_margin_end(vbox, 10);
    gtk_widget_set_margin_top(vbox, 8);
    gtk_widget_set_margin_bottom(vbox, 8);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *lbl = gtk_label_new("⇥");
    GtkWidget *b_refresh = gtk_button_new_with_label(TR("刷新"));
    g_signal_connect(b_refresh, "clicked", G_CALLBACK(on_refresh), NULL);
    gtk_box_pack_start(GTK_BOX(row), lbl, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(row), b_refresh, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), row, FALSE, FALSE, 0);

    GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sw), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    listbox = gtk_list_box_new();
    gtk_container_add(GTK_CONTAINER(sw), listbox);
    gtk_box_pack_start(GTK_BOX(vbox), sw, TRUE, TRUE, 0);

    status_label = gtk_label_new("");
    qy_add_class(status_label, "qy-mon-info");
    gtk_widget_set_halign(status_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 0);

    gtk_widget_show_all(win);

    if (g_getenv("QYSWITCH_AUTO"))
        g_timeout_add(600, auto_sw, NULL);
    else
        populate();
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.switcher", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    char *own_argv[2] = { argv[0], NULL };
    int rc = g_application_run(G_APPLICATION(app), 1, own_argv);
    g_object_unref(app);
    return rc;
}