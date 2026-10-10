/* qygit.c — 澜岫 Git 工具 (GTK3)
 * 显示仓库状态与最近提交，支持刷新 / 提交 / 推送。
 * 调用 /usr/bin/git（随 qydesktop 包内置）。
 * 自动化：QYGIT_REPO=/path 启动后自动显示仓库状态（日志 QYGITDBG）
 */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <glib/gstdio.h>

static GtkWidget *path_entry = NULL;
static GtkWidget *view = NULL;
static GtkTextBuffer *buffer = NULL;
static GtkWidget *status_label = NULL;
static GtkWidget *commit_entry = NULL;

/* 执行 git 命令（在指定仓库），返回合并 stdout+stderr */
static char *run_git(const char *repo, const char *args) {
    gchar *q = g_shell_quote(repo);
    gchar *cmd = g_strdup_printf("git -C %s %s", q, args);
    g_free(q);
    gchar *out = NULL, *err = NULL;
    gint rc = 0;
    g_spawn_command_line_sync(cmd, &out, &err, &rc, NULL);
    g_free(cmd);
    GString *s = g_string_new(NULL);
    if (out && out[0]) g_string_append(s, out);
    if (err && err[0]) {
        if (s->len) g_string_append_c(s, '\n');
        g_string_append(s, err);
    }
    gchar *res = g_string_free(s, FALSE);
    g_free(out); g_free(err);
    return res;
}

/* 刷新：显示 git status --short + branch + 最近提交 */
static void do_refresh(void) {
    const char *repo = gtk_entry_get_text(GTK_ENTRY(path_entry));
    if (!repo || !repo[0]) return;
    if (!g_file_test(repo, G_FILE_TEST_IS_DIR)) {
        gtk_text_buffer_set_text(buffer, TR("仓库路径无效或不存在的目录"), -1);
        return;
    }
    gchar *status = run_git(repo, "status --short --branch");
    gchar *log = run_git(repo, "log --oneline -8 2>&1");
    GString *s = g_string_new(NULL);
    g_string_append_printf(s, "== %s ==\n%s", repo, status ? status : "");
    g_string_append_printf(s, "\n--- %s ---\n%s", TR("最近提交"), log ? log : "");
    gtk_text_buffer_set_text(buffer, s->str, -1);
    g_string_free(s, TRUE);
    g_free(status); g_free(log);
    /* 状态行：统计工作区改动数 */
    gchar *counts = run_git(repo, "status --porcelain");
    int changed = 0;
    if (counts) {
        for (char *p = counts; *p; p++)
            if (*p == '\n') changed++;
        if (changed == 0 && counts[0]) changed = 1;
    }
    g_free(counts);
    gchar *st = g_strdup_printf(TR("工作区改动 %d 项"), changed);
    gtk_label_set_text(GTK_LABEL(status_label), st);
    g_free(st);
    g_printerr("QYGITDBG: repo=%s status=%d\n", repo, changed);
}

/* 提交：git add -A && git commit -m */
static void do_commit(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    const char *repo = gtk_entry_get_text(GTK_ENTRY(path_entry));
    const char *msg = gtk_entry_get_text(GTK_ENTRY(commit_entry));
    if (!msg || !msg[0]) return;
    gchar *out = run_git(repo, "add -A");
    g_free(out);
    gchar *qmsg = g_shell_quote(msg);
    gchar *args = g_strdup_printf("commit -m %s", qmsg);
    out = run_git(repo, args);
    g_free(args);
    g_free(out);
    gtk_entry_set_text(GTK_ENTRY(commit_entry), "");
    do_refresh();
}

/* 推送 */
static void do_push(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    gchar *res = run_git(gtk_entry_get_text(GTK_ENTRY(path_entry)), "push 2>&1");
    GtkWidget *dlg = gtk_message_dialog_new(
        gtk_widget_get_toplevel(w) ? GTK_WINDOW(gtk_widget_get_toplevel(w)) : NULL,
        GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_OK, "%s", res);
    gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
    g_free(res);
    do_refresh();
}

static gboolean auto_refresh(gpointer p) {
    (void)p;
    do_refresh();
    return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    qy_load_theme();

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), TR("澜岫 Git 工具"));
    gtk_window_set_default_size(GTK_WINDOW(win), 720, 460);
    qy_make_titlebar(GTK_WINDOW(win), TR("澜岫 Git 工具"));
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 8);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 顶部：仓库路径 + 按钮 */
    GtkWidget *top = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    path_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(path_entry), TR("仓库路径，如 /root/repo"));
    gtk_box_pack_start(GTK_BOX(top), path_entry, TRUE, TRUE, 0);
    GtkWidget *b_refresh = gtk_button_new_with_label(TR("刷新"));
    qy_add_class(b_refresh, "qy-btn");
    g_signal_connect(b_refresh, "clicked", G_CALLBACK(do_refresh), NULL);
    gtk_box_pack_start(GTK_BOX(top), b_refresh, FALSE, FALSE, 0);
    GtkWidget *b_push = gtk_button_new_with_label(TR("推送"));
    qy_add_class(b_push, "qy-btn");
    g_signal_connect(b_push, "clicked", G_CALLBACK(do_push), NULL);
    gtk_box_pack_start(GTK_BOX(top), b_push, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), top, FALSE, FALSE, 0);

    /* 状态输出 */
    buffer = gtk_text_buffer_new(NULL);
    view = gtk_text_view_new_with_buffer(buffer);
    gtk_text_view_set_editable(GTK_TEXT_VIEW(view), FALSE);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_NONE);
    GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(sw), view);
    gtk_box_pack_start(GTK_BOX(vbox), sw, TRUE, TRUE, 0);

    /* 底部：提交信息 + 提交按钮 */
    GtkWidget *bottom = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    commit_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(commit_entry), TR("提交说明，如 修复问题"));
    g_signal_connect(commit_entry, "activate", G_CALLBACK(do_commit), NULL);
    gtk_box_pack_start(GTK_BOX(bottom), commit_entry, TRUE, TRUE, 0);
    GtkWidget *b_commit = gtk_button_new_with_label(TR("提交"));
    qy_add_class(b_commit, "qy-btn");
    g_signal_connect(b_commit, "clicked", G_CALLBACK(do_commit), NULL);
    gtk_box_pack_start(GTK_BOX(bottom), b_commit, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), bottom, FALSE, FALSE, 0);

    status_label = gtk_label_new("");
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 0);

    gtk_widget_show_all(win);

    /* 自动化：QYGIT_REPO=/path 启动后自动显示状态 */
    const char *env = g_getenv("QYGIT_REPO");
    if (env && env[0]) {
        gtk_entry_set_text(GTK_ENTRY(path_entry), env);
        g_timeout_add(800, auto_refresh, NULL);
    }
    gtk_main();
    return 0;
}