/* qysetup - 启元系统安装器 (GTK3 GUI 前端)
 * 后端: /usr/bin/qyinstall <disk>（CLI 脚本，已实测）
 * 界面: 磁盘列表 → 确认 → 后台安装（VTE 风格日志区，禁止窗口关闭直到完成）
 */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <string.h>
#include <glib/gstdio.h>

static GtkWidget *win = NULL;
static GtkWidget *disk_list = NULL;
static GtkWidget *log_view = NULL;
static GtkWidget *btn_install = NULL;
static GtkWidget *bar = NULL;
static GPid install_pid = 0;
static gint log_watch = 0;
static gboolean installing = FALSE;

/* --- 磁盘枚举: 读 /sys/block, 只留块设备盘 --- */
static gboolean is_disk_name(const char *n) {
    if (g_str_has_prefix(n, "sd") || g_str_has_prefix(n, "vd") ||
        g_str_has_prefix(n, "hd") || g_str_has_prefix(n, "nvme"))
        return TRUE;
    return FALSE;
}
/* 过滤掉 live 介质所在盘sr0 等; 大小字节 */
static gboolean disk_size(const char *name, guint64 *bytes) {
    gchar *p = g_strdup_printf("/sys/block/%s/size", name);
    gchar *c = NULL; gsize len = 0;
    if (!g_file_get_contents(p, &c, &len, NULL)) { g_free(p); return FALSE; }
    *bytes = g_ascii_strtoull(c, NULL, 10) * 512ULL;
    g_free(c); g_free(p);
    return TRUE;
}
static void refresh_disks(void) {
    GtkListStore *st = GTK_LIST_STORE(gtk_tree_view_get_model(GTK_TREE_VIEW(disk_list)));
    gtk_list_store_clear(st);
    GDir *d = g_dir_open("/sys/block", 0, NULL);
    if (!d) return;
    const gchar *n;
    while ((n = g_dir_read_name(d))) {
        guint64 sz;
        if (!is_disk_name(n)) continue;
        if (!disk_size(n, &sz)) continue;
        if (sz < 1024ULL*1024*1024) continue;      /* < 1GB 忽略 */
        gchar *dev = g_strdup_printf("/dev/%s", n);
        gchar *hum = g_strdup_printf("%.1f GB", sz / 1073741824.0);
        GtkTreeIter it;
        gtk_list_store_append(st, &it);
        gtk_list_store_set(st, &it, 0, dev, 1, hum, -1);
        g_free(dev); g_free(hum);
    }
    g_dir_close(d);
}

static void log_append(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    gchar *s = g_strdup_vprintf(fmt, ap);
    va_end(ap);
    GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(log_view));
    GtkTextIter end;
    gtk_text_buffer_get_end_iter(b, &end);
    gtk_text_buffer_insert(b, &end, s, -1);
    gtk_text_buffer_insert(b, &end, "\n", -1);
    gtk_text_view_scroll_to_iter(GTK_TEXT_VIEW(log_view), &end, 0, FALSE, 0, 0);
    g_free(s);
}

static gboolean on_install_out(GIOChannel *ch, GIOCondition cond, gpointer ud) {
    gchar *line; gsize len; GIOStatus st;
    while ((st = g_io_channel_read_line(ch, &line, &len, NULL, NULL)) == G_IO_STATUS_NORMAL && line) {
        GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(log_view));
        GtkTextIter end;
        gtk_text_buffer_get_end_iter(b, &end);
        gtk_text_buffer_insert(b, &end, line, -1);
        g_free(line);
    }
    return TRUE;
}

static void on_install_exit(GPid pid, gint status, gpointer ud) {
    g_spawn_close_pid(pid);
    install_pid = 0;
    g_source_remove(log_watch);
    installing = FALSE;
    gboolean ok = (status == 0);
    log_append(ok ? TR("=== 安装完成！===") : TR("=== 安装失败（状态 %d），查看上方日志 ==="), status);
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(bar), ok ? 1.0 : 0.0);
    gtk_widget_set_sensitive(btn_install, TRUE);
    if (ok) {
        GtkWidget *dlg = gtk_message_dialog_new(GTK_WINDOW(win), GTK_DIALOG_MODAL,
            GTK_MESSAGE_INFO, GTK_BUTTONS_NONE,
            "启元系统已成功安装！\n\n重新启动后将从硬盘引导，\n首次开机会出现初始配置向导。");
        gtk_window_set_title(GTK_WINDOW(dlg), TR("安装完成"));
        gtk_dialog_add_buttons(GTK_DIALOG(dlg), TR("稍后重启"), GTK_RESPONSE_CANCEL, TR("立即重启"), GTK_RESPONSE_OK, NULL);
        gint r = gtk_dialog_run(GTK_DIALOG(dlg));
        gtk_widget_destroy(dlg);
        if (r == GTK_RESPONSE_OK) system("reboot");
    }
}

static void do_install(GtkWidget *w, gpointer ud) {
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(disk_list));
    GtkTreeIter it; GtkTreeModel *m;
    if (!gtk_tree_selection_get_selected(sel, &m, &it)) {
        log_append(TR("请先在列表中选择目标磁盘"));
        return;
    }
    gchar *dev = NULL;
    gtk_tree_model_get(m, &it, 0, &dev, -1);

    /* 用户预创建 (可选): 弹表单 */
    GtkWidget *udlg = gtk_dialog_new_with_buttons(TR("初始用户"), GTK_WINDOW(win), GTK_DIALOG_MODAL,
        TR("跳过"), GTK_RESPONSE_CANCEL, TR("确定"), GTK_RESPONSE_OK, NULL);
    GtkWidget *ug = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(ug), 6);
    gtk_grid_set_column_spacing(GTK_GRID(ug), 8);
    gtk_container_set_border_width(GTK_CONTAINER(ug), 12);
    GtkWidget *une = gtk_entry_new();
    GtkWidget *upe = gtk_entry_new();
    gtk_entry_set_visibility(GTK_ENTRY(upe), FALSE);
    gtk_grid_attach(GTK_GRID(ug), gtk_label_new(TR("用户名（留空跳过）")), 0, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(ug), une, 1, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(ug), gtk_label_new(TR("密码")), 0, 1, 1, 1);
    gtk_grid_attach(GTK_GRID(ug), upe, 1, 1, 1, 1);
    GtkWidget *ua = gtk_dialog_get_content_area(GTK_DIALOG(udlg));
    gtk_box_pack_start(GTK_BOX(ua), ug, TRUE, TRUE, 0);
    gtk_widget_show_all(udlg);
    gint uresp = gtk_dialog_run(GTK_DIALOG(udlg));
    const char *uname = gtk_entry_get_text(GTK_ENTRY(une));
    const char *upass = gtk_entry_get_text(GTK_ENTRY(upe));
    gchar *user_spec = NULL;
    if (uresp == GTK_RESPONSE_OK && *uname) {
        if (*upass)
            user_spec = g_strdup_printf("%s %s", uname, upass);
        else
            user_spec = g_strdup_printf("%s", uname);
    }
    gtk_widget_destroy(udlg);

    /* 二次确认 */
    GtkWidget *dlg = gtk_message_dialog_new(GTK_WINDOW(win), GTK_DIALOG_MODAL,
        GTK_MESSAGE_WARNING, GTK_BUTTONS_OK_CANCEL,
        "将把启元系统安装到 %s\n该磁盘上的所有数据将被清除！", dev);
    gtk_window_set_title(GTK_WINDOW(dlg), TR("确认安装"));
    gint resp = gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
    if (resp != GTK_RESPONSE_OK) { g_free(dev); if (user_spec) g_free(user_spec); return; }

    installing = TRUE;
    gtk_widget_set_sensitive(btn_install, FALSE);
    gtk_progress_bar_pulse(GTK_PROGRESS_BAR(bar));
    log_append(TR("=== 开始安装到 %s ==="), dev);
    gchar *cmd;
    if (user_spec)
        cmd = g_strdup_printf("/usr/bin/qyinstall %s --user %s", dev, user_spec);
    else
        cmd = g_strdup_printf("/usr/bin/qyinstall %s", dev);
    gchar *argv[4] = { "/bin/busybox", "sh", "-c", cmd };
    g_free(user_spec);
    GError *err = NULL;
    gint outfd;
    if (!g_spawn_async_with_pipes(NULL, argv, NULL,
            G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD,
            NULL, NULL, &install_pid, NULL, &outfd, NULL, &err)) {
        log_append(TR("启动 qyinstall 失败: %s"), err->message);
        g_error_free(err);
        installing = FALSE;
        gtk_widget_set_sensitive(btn_install, TRUE);
        g_free(dev); g_free(cmd);
        return;
    }
    GIOChannel *ch = g_io_channel_unix_new(outfd);
    log_watch = g_io_add_watch(ch, G_IO_IN, on_install_out, NULL);
    g_io_channel_unref(ch);
    g_child_watch_add(install_pid, on_install_exit, NULL);
    g_free(dev); g_free(cmd);
}

static void activate(GtkApplication *app, gpointer ud) {
    qy_load_theme();
    win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元系统安装器"));
    gtk_window_set_default_size(GTK_WINDOW(win), 640, 480);

    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_set_border_width(GTK_CONTAINER(v), 12);
    gtk_container_add(GTK_CONTAINER(win), v);

    v = v; /* 列表区 */
    GtkWidget *lbl = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(lbl), TR("<b>目标磁盘</b>（选中后点安装；数据将被清除）"));
    gtk_widget_set_halign(lbl, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(v), lbl, FALSE, FALSE, 0);

    GtkListStore *st = gtk_list_store_new(2, G_TYPE_STRING, G_TYPE_STRING);
    disk_list = gtk_tree_view_new_with_model(GTK_TREE_MODEL(st));
    GtkCellRenderer *r = gtk_cell_renderer_text_new();
    GtkTreeViewColumn *c1 = gtk_tree_view_column_new_with_attributes(TR("设备"), r, "text", 0, NULL);
    GtkTreeViewColumn *c2 = gtk_tree_view_column_new_with_attributes(TR("容量"), r, "text", 1, NULL);
    gtk_tree_view_append_column(GTK_TREE_VIEW(disk_list), c1);
    gtk_tree_view_append_column(GTK_TREE_VIEW(disk_list), c2);
    gtk_tree_view_set_headers_visible(GTK_TREE_VIEW(disk_list), TRUE);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(scroll), disk_list);
    gtk_scrolled_window_set_min_content_height(GTK_SCROLLED_WINDOW(scroll), 110);
    gtk_box_pack_start(GTK_BOX(v), scroll, FALSE, FALSE, 0);

    btn_install = gtk_button_new_with_label(TR("⬇  安装启元到所选磁盘"));
    g_signal_connect(btn_install, "clicked", G_CALLBACK(do_install), NULL);
    gtk_box_pack_start(GTK_BOX(v), btn_install, FALSE, FALSE, 0);

    bar = gtk_progress_bar_new();
    gtk_box_pack_start(GTK_BOX(v), bar, FALSE, FALSE, 0);

    GtkWidget *lbl2 = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(lbl2), TR("<b>安装日志</b>"));
    gtk_widget_set_halign(lbl2, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(v), lbl2, FALSE, FALSE, 0);
    log_view = gtk_text_view_new();
    gtk_text_view_set_editable(GTK_TEXT_VIEW(log_view), FALSE);
    gtk_text_view_set_monospace(GTK_TEXT_VIEW(log_view), TRUE);
    GtkWidget *s2 = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(s2), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(s2), log_view);
    gtk_box_pack_start(GTK_BOX(v), s2, TRUE, TRUE, 0);

    refresh_disks();
    gtk_widget_show_all(win);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("org.qiyuan.qysetup", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    /* GUI 启动不传参数：安装走界面 */
    int rc = g_application_run(G_APPLICATION(app), 1, argv);
    g_object_unref(app);
    return rc;
}
