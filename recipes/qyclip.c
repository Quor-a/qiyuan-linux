/* qyclip.c — 启元剪贴板管理器
 * 监听剪贴板 owner-change，保存文本历史，点击条目可复制回剪贴板。
 * 自动化: QYCLIP_AUTO=文本 启动后模拟复制该文本（用于截图/自测）。
 */
#include <gtk/gtk.h>
#include <string.h>
#include "qytheme.h"
#include "qyl10n.h"

#define MAX_HIST 50

static GtkWidget *listbox = NULL;
static GtkWidget *status_label = NULL;
static GPtrArray *history = NULL;

static void on_copy_clicked(GtkWidget *w, gpointer ud);
static gboolean auto_read_clip(gpointer p);

/* 添加一条历史（去重，限制条数，更新 UI） */
static void add_history(const char *text) {
    if (!text || !text[0]) return;
    if (history->len > 0 &&
        strcmp((const char *)g_ptr_array_index(history, history->len - 1), text) == 0)
        return;
    g_ptr_array_add(history, g_strdup(text));
    if (history->len > MAX_HIST)
        g_ptr_array_remove_index(history, 0);

    /* 重建列表（简单方式） */
    gtk_container_foreach(GTK_CONTAINER(listbox), (GtkCallback)gtk_widget_destroy, NULL);
    for (int i = (int)history->len - 1; i >= 0; i--) {
        const char *t = (const char *)g_ptr_array_index(history, i);
        GtkWidget *row = gtk_button_new_with_label(t);
        gtk_widget_set_halign(row, GTK_ALIGN_FILL);
        g_signal_connect(row, "clicked", G_CALLBACK(on_copy_clicked), g_strdup(t));
        gtk_list_box_insert(GTK_LIST_BOX(listbox), row, -1);
    }
    char st[256];
    g_snprintf(st, sizeof st, "%s: %d", TR("剪贴板历史"), (int)history->len);
    gtk_label_set_text(GTK_LABEL(status_label), st);
}

static void on_copy_clicked(GtkWidget *w, gpointer ud) {
    (void)w;
    const char *text = (const char *)ud;
    gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), text, -1);
    char st[256];
    g_snprintf(st, sizeof st, "%s: %s", TR("已复制"), text);
    gtk_label_set_text(GTK_LABEL(status_label), st);
    g_free(ud);
}

/* 剪贴板内容请求回调 */
static void got_text(GtkClipboard *clip, const char *text, gpointer data) {
    (void)clip; (void)data;
    if (text && text[0])
        add_history(text);
}

static void on_owner_change(GtkClipboard *clip, GdkEvent *event, gpointer data) {
    (void)clip; (void)event; (void)data;
    gtk_clipboard_request_text(clip, got_text, NULL);
}

/* 清空历史 */
static void on_clear_history(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (history) g_ptr_array_set_size(history, 0);
    gtk_container_foreach(GTK_CONTAINER(listbox), (GtkCallback)gtk_widget_destroy, NULL);
    gtk_label_set_text(GTK_LABEL(status_label), TR("暂无历史"));
}

/* 自动化: 设置剪贴板文本 */
static gboolean auto_set_clip(gpointer p) {
    const char *text = (const char *)p;
    gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), text, -1);
    g_timeout_add(600, auto_read_clip, NULL);
    g_free(p);
    return G_SOURCE_REMOVE;
}
static gboolean auto_read_clip(gpointer p) {
    (void)p;
    gtk_clipboard_request_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), got_text, NULL);
    return G_SOURCE_REMOVE;
}

static void activate(GtkApplication *app, gpointer ud) {
    (void)ud;
    qy_load_theme();
    history = g_ptr_array_new_with_free_func(g_free);

    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("剪贴板"));
    gtk_window_set_default_size(GTK_WINDOW(win), 460, 420);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_widget_set_margin_start(vbox, 10);
    gtk_widget_set_margin_end(vbox, 10);
    gtk_widget_set_margin_top(vbox, 8);
    gtk_widget_set_margin_bottom(vbox, 8);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    GtkWidget *bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *b_clear = gtk_button_new_with_label(TR("清空历史"));
    g_signal_connect(b_clear, "clicked", G_CALLBACK(on_clear_history), NULL);
    gtk_box_pack_start(GTK_BOX(bar), b_clear, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), bar, FALSE, FALSE, 0);

    GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sw), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    listbox = gtk_list_box_new();
    gtk_container_add(GTK_CONTAINER(sw), listbox);
    gtk_box_pack_start(GTK_BOX(vbox), sw, TRUE, TRUE, 0);

    status_label = gtk_label_new(TR("暂无历史"));
    qy_add_class(status_label, "qy-mon-info");
    gtk_widget_set_halign(status_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 0);

    /* 监听剪贴板变化 */
    GtkClipboard *clip = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    g_signal_connect(clip, "owner-change", G_CALLBACK(on_owner_change), NULL);

    const char *auto_text = g_getenv("QYCLIP_AUTO");
    if (auto_text)
        g_timeout_add(800, auto_set_clip, g_strdup(auto_text));

    gtk_widget_show_all(win);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.clip", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    char *own_argv[2] = { argv[0], NULL };
    int rc = g_application_run(G_APPLICATION(app), 1, own_argv);
    g_object_unref(app);
    return rc;
}