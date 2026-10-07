/* qywelcome - 启元首启配置向导 (GTK3)
 * 装机后首次启动运行: 设置主机名 / 普通用户+密码 / 时区 → 应用 → 完成后标记 /etc/.qywelcomed
 * 触发: qydesktop.unit 启动前由 qyinit 调 (或 qydesktop 检测未标记则拉起)
 */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>

static GtkWidget *win = NULL;
static GtkWidget *hn_e, *un_e, *pw_e, *pw2_e, *tz_e;
static GtkWidget *status_lb;

static void set_status(const char *m) { gtk_label_set_text(GTK_LABEL(status_lb), m); }
static void on_finish_clicked(GtkButton *b, gpointer ud);

static void activate(GtkApplication *app, gpointer ud) {
    qy_load_theme();
    win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("欢迎使用启元 Linux"));
    gtk_window_set_default_size(GTK_WINDOW(win), 480, 420);
    gtk_container_set_border_width(GTK_CONTAINER(win), 16);

    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    GtkWidget *title = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(title),
        TR2("<span size='x-large' weight='bold'>欢迎使用启元 Linux</span>\n只需几步，完成初始配置","<span size='x-large' weight='bold'>Welcome to Qiyuan Linux</span>\nA few steps to set up"));
    gtk_widget_set_halign(title, GTK_ALIGN_CENTER);

    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 10);

    hn_e  = gtk_entry_new();  gtk_entry_set_text(GTK_ENTRY(hn_e), "qiyuan");
    un_e  = gtk_entry_new();
    pw_e  = gtk_entry_new();  gtk_entry_set_visibility(GTK_ENTRY(pw_e), FALSE);
    pw2_e = gtk_entry_new();  gtk_entry_set_visibility(GTK_ENTRY(pw2_e), FALSE);
    tz_e  = gtk_entry_new();  gtk_entry_set_text(GTK_ENTRY(tz_e), "Asia/Shanghai");

    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(TR("主机名")),     0, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), hn_e,                        1, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(TR("用户名")),     0, 1, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), un_e,                        1, 1, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(TR("密码")),       0, 2, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), pw_e,                        1, 2, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(TR("确认密码")),   0, 3, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), pw2_e,                       1, 3, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(TR("时区")),       0, 4, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), tz_e,                        1, 4, 1, 1);

    GtkWidget *hint = gtk_label_new(TR("用户将加入 wheel 组，可用 qysudo 提权"));
    gtk_widget_set_halign(hint, GTK_ALIGN_START);

    GtkWidget *fin = gtk_button_new_with_label(TR("完成配置"));
    g_signal_connect(fin, "clicked", G_CALLBACK(on_finish_clicked), NULL);
    gtk_widget_set_halign(fin, GTK_ALIGN_END);

    status_lb = gtk_label_new("");

    gtk_box_pack_start(GTK_BOX(v), title, FALSE, FALSE, 4);
    gtk_box_pack_start(GTK_BOX(v), grid, TRUE, TRUE, 4);
    gtk_box_pack_start(GTK_BOX(v), hint, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v), fin, FALSE, FALSE, 4);
    gtk_box_pack_start(GTK_BOX(v), status_lb, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(win), v);
    gtk_widget_show_all(win);
}

static void sysrun(const char *fmt, const char *a) {
    gchar *cmd = g_strdup_printf(fmt, a);
    system(cmd);
    g_free(cmd);
}

static void on_finish_clicked(GtkButton *b, gpointer ud) {
    const char *hn = gtk_entry_get_text(GTK_ENTRY(hn_e));
    const char *un = gtk_entry_get_text(GTK_ENTRY(un_e));
    const char *pw = gtk_entry_get_text(GTK_ENTRY(pw_e));
    const char *pw2 = gtk_entry_get_text(GTK_ENTRY(pw2_e));
    const char *tz = gtk_entry_get_text(GTK_ENTRY(tz_e));

    if (!*hn) hn = "qiyuan";
    if (!*un) { set_status(TR("用户名不能为空")); return; }
    if (strcmp(pw, pw2) != 0) { set_status(TR("两次密码不一致")); return; }

    /* 主机名 */
    FILE *f = fopen("/etc/hostname", "w");
    if (f) { fprintf(f, "%s\n", hn); fclose(f); }
    sysrun("hostname '%s'", hn);

    /* 时区 (可选) */
    if (*tz) {
        gchar *cmd = g_strdup_printf(
            "[ -f /usr/share/zoneinfo/%s ] && ln -sf /usr/share/zoneinfo/%s /etc/localtime", tz, tz);
        system(cmd); g_free(cmd);
    }

    /* 用户 */
    gchar *cmd = g_strdup_printf("qyuseradd '%s' '%s' >/dev/null 2>&1", un, pw);
    int rc = system(cmd);
    g_free(cmd);
    if (rc != 0) { set_status(TR("创建用户失败（重名？）")); return; }

    /* 标记完成 */
    f = fopen("/etc/.qywelcomed", "w");
    if (f) { fprintf(f, "1\n"); fclose(f); }
    set_status(TR("✓ 配置完成！重启或直接使用。"));
    gtk_button_set_label(b, TR("已完成"));
    gtk_widget_set_sensitive(GTK_WIDGET(b), FALSE);
}

int main(int argc, char **argv) {
    /* 已配置过 → 直接退出 */
    FILE *f = fopen("/etc/.qywelcomed", "r");
    if (f) { fclose(f); return 0; }

    GtkApplication *app = gtk_application_new("com.qiyuan.welcome", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int rc = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return rc;
}
