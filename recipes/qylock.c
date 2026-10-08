/* qylock.c — 启元锁屏
 * 全屏锁屏：大时钟 + 日期 + 密码解锁。
 * 密码来自 /etc/qylockpass.conf 第一行（无文件时默认 qiyuan）。
 * 自动化: QYLOCK_AUTO=密码 启动后自动输入并解锁（用于自测截图）。
 */
#include <gtk/gtk.h>
#include <string.h>
#include <time.h>
#include "qytheme.h"
#include "qyl10n.h"

static GtkWidget *clock_label = NULL;
static GtkWidget *date_label = NULL;
static GtkWidget *pass_entry = NULL;
static GtkWidget *status_label = NULL;
static GtkApplication *g_app = NULL;

/* 读取锁屏密码（配置文件或默认） */
static const char *get_lock_pass(void) {
    static char pass[128] = "";
    if (pass[0]) return pass;
    gchar *c = NULL;
    g_file_get_contents("/etc/qylockpass.conf", &c, NULL, NULL);
    if (c) {
        char *nl = strchr(c, '\n');
        if (nl) *nl = 0;
        if (c[0]) g_strlcpy(pass, c, sizeof pass);
        g_free(c);
    }
    if (!pass[0]) g_strlcpy(pass, "qiyuan", sizeof pass);
    return pass;
}

/* 更新时钟 */
static gboolean update_clock(gpointer p) {
    (void)p;
    time_t t = time(NULL);
    struct tm *tm = localtime(&t);
    char buf[64];
    g_snprintf(buf, sizeof buf, "%02d:%02d:%02d", tm->tm_hour, tm->tm_min, tm->tm_sec);
    if (clock_label) gtk_label_set_text(GTK_LABEL(clock_label), buf);
    g_snprintf(buf, sizeof buf, "%04d-%02d-%02d", tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday);
    if (date_label) gtk_label_set_text(GTK_LABEL(date_label), buf);
    return G_SOURCE_CONTINUE;
}

/* 尝试解锁 */
static void try_unlock(void) {
    const char *input = gtk_entry_get_text(GTK_ENTRY(pass_entry));
    if (strcmp(input, get_lock_pass()) == 0) {
        if (g_app) g_application_quit(G_APPLICATION(g_app));
        else exit(0);
        return;
    }
    gtk_label_set_text(GTK_LABEL(status_label), TR("密码错误，请重试"));
    gtk_entry_set_text(GTK_ENTRY(pass_entry), "");
    gtk_widget_grab_focus(pass_entry);
}

static void on_unlock(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    try_unlock();
}

static gboolean on_entry_activate(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    try_unlock();
    return TRUE;
}

/* 自动化: 输入密码并解锁 */
static gboolean auto_unlock(gpointer p) {
    const char *pass = (const char *)p;
    gtk_entry_set_text(GTK_ENTRY(pass_entry), pass);
    try_unlock();
    g_free(p);
    return G_SOURCE_REMOVE;
}

static void activate(GtkApplication *app, gpointer ud) {
    (void)ud;
    g_app = app;
    qy_load_theme();
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("锁屏"));
    gtk_window_set_default_size(GTK_WINDOW(win), 1280, 800);
    gtk_window_fullscreen(GTK_WINDOW(win));
    gtk_widget_set_name(win, "qylock-win");

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_valign(vbox, GTK_ALIGN_CENTER);
    gtk_widget_set_halign(vbox, GTK_ALIGN_CENTER);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 大时钟 */
    clock_label = gtk_label_new("--:--:--");
    gtk_widget_set_name(clock_label, "qylock-clock");
    gtk_box_pack_start(GTK_BOX(vbox), clock_label, FALSE, FALSE, 0);

    /* 日期 */
    date_label = gtk_label_new("");
    gtk_widget_set_name(date_label, "qylock-date");
    gtk_box_pack_start(GTK_BOX(vbox), date_label, FALSE, FALSE, 0);

    /* 解锁行: 密码输入 + 解锁按钮 */
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    pass_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(pass_entry), TR("输入密码解锁"));
    gtk_entry_set_visibility(GTK_ENTRY(pass_entry), FALSE);
    gtk_widget_set_size_request(pass_entry, 240, -1);
    GtkWidget *btn = gtk_button_new_with_label(TR("解锁"));
    qy_add_class(btn, "qy-btn");
    g_signal_connect(btn, "clicked", G_CALLBACK(on_unlock), NULL);
    g_signal_connect(pass_entry, "activate", G_CALLBACK(on_entry_activate), NULL);
    gtk_box_pack_start(GTK_BOX(row), pass_entry, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(row), btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), row, FALSE, FALSE, 0);

    /* 状态栏 */
    status_label = gtk_label_new("");
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 0);

    const char *auto_pass = g_getenv("QYLOCK_AUTO");
    if (auto_pass)
        g_timeout_add(1200, auto_unlock, g_strdup(auto_pass));

    gtk_widget_show_all(win);
    update_clock(NULL);
    g_timeout_add(1000, update_clock, NULL);
    gtk_widget_grab_focus(pass_entry);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.lock", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    char *own_argv[2] = { argv[0], NULL };
    int rc = g_application_run(G_APPLICATION(app), 1, own_argv);
    g_object_unref(app);
    return rc;
}