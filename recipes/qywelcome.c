/* qywelcome - 澜岫首启配置向导 (GTK3)
 * 装机后首次启动运行: 设置主机名 / 普通用户+密码 / 时区 → 应用 → 完成后标记 /etc/.qywelcomed
 * 触发: qydesktop.unit 启动前由 qyinit 调 (或 qydesktop 检测未标记则拉起)
 */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>
#include <sys/statvfs.h>

static GtkWidget *win = NULL;
static GtkWidget *hn_e, *un_e, *pw_e, *pw2_e, *tz_e;
static GtkWidget *status_lb;

static void set_status(const char *m) { gtk_label_set_text(GTK_LABEL(status_lb), m); }
static void on_finish_clicked(GtkButton *b, gpointer ud);

static void read_proc_line(const char *path, const char *key, char *out, size_t outsz) {
    out[0] = 0;
    FILE *f = fopen(path, "r");
    if (!f) return;
    char buf[512];
    while (fgets(buf, sizeof buf, f)) {
        if (key && strncmp(buf, key, strlen(key)) == 0) {
            char *colon = strchr(buf, ':');
            char *nl = strchr(buf, '\n');
            if (nl) *nl = 0;
            g_strlcpy(out, colon ? colon + 2 : buf, outsz);
            break;
        }
    }
    fclose(f);
}

/* 本机信息: 内核 / CPU 型号 / 内存 / 磁盘 */
static void sysinfo_rows(GtkWidget *v) {
    char kern[128] = "-", cpu[256] = "-", mem[128] = "-", disk[128] = "-";
    struct utsname uts;
    if (uname(&uts) == 0) g_strlcpy(kern, uts.release, sizeof kern);
    read_proc_line("/proc/cpuinfo", "model name", cpu, sizeof cpu);
    read_proc_line("/proc/meminfo", "MemTotal", mem, sizeof mem);
    if (mem[0]) {
        char *p = strchr(mem, 'k');
        if (p) *p = 0;
        char tmp[64];
        g_snprintf(tmp, sizeof tmp, "%s", mem);
        double gb = atof(tmp) / (1024.0 * 1024.0);
        g_snprintf(mem, sizeof mem, "%.2f GB", gb);
    }
    struct statvfs sv;
    if (statvfs("/", &sv) == 0 && sv.f_blocks > 0) {
        double usage = 1.0 - (double)sv.f_bavail / (double)sv.f_blocks;
        double total_gb = (double)sv.f_blocks * (double)sv.f_frsize / (1024.0 * 1024.0 * 1024.0);
        g_snprintf(disk, sizeof disk, "%d%% (%.0f GB)", (int)(usage * 100 + 0.5), total_gb);
    }

    const char *rows[][2] = {
        { TR("系统"), "澜岫 Linux" },
        { TR("内核"), kern },
        { TR("CPU 型号"), cpu },
        { TR("内存"), mem },
        { TR("磁盘"), disk },
    };
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    qy_add_class(box, "qy-welcome-info");
    for (int i = 0; i < 5; i++) {
        GtkWidget *row = gtk_label_new(NULL);
        gtk_label_set_markup(GTK_LABEL(row), g_strdup_printf(
            "<b>%s:</b>  %s", rows[i][0], rows[i][1]));
        gtk_widget_set_halign(row, GTK_ALIGN_START);
        qy_add_class(row, "qy-welcome-info-row");
        gtk_box_pack_start(GTK_BOX(box), row, FALSE, FALSE, 0);
    }
    gtk_box_pack_start(GTK_BOX(v), box, FALSE, FALSE, 4);
}

static gboolean auto_fill(gpointer p);   /* 前向声明 */
static void activate(GtkApplication *app, gpointer ud) {
    qy_load_theme();
    win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("欢迎使用澜岫 Linux"));
    gtk_window_set_default_size(GTK_WINDOW(win), 480, 420);
    gtk_container_set_border_width(GTK_CONTAINER(win), 16);
    /* weston 输入焦点修复（release 238）：欢迎向导启动时不抢桌面键盘焦点，
     * 避免 qydesktop 无法接收 VNC/sendkey 输入。 */
    gtk_window_set_accept_focus(GTK_WINDOW(win), FALSE);
    gtk_window_set_focus_visible(GTK_WINDOW(win), FALSE);

    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    GtkWidget *logo = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(logo), "<span size='xx-large' weight='bold'>澜岫 LANXIU</span>");
    gtk_widget_set_halign(logo, GTK_ALIGN_CENTER);
    qy_add_class(logo, "qy-about-logo");
    gtk_box_pack_start(GTK_BOX(v), logo, FALSE, FALSE, 4);

    GtkWidget *title = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(title),
        TR2("<span size='x-large' weight='bold'>欢迎使用澜岫 Linux</span>\n只需几步，完成初始配置","<span size='x-large' weight='bold'>Welcome to LANXIU Linux</span>\nA few steps to set up"));
    gtk_widget_set_halign(title, GTK_ALIGN_CENTER);

    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 10);

    hn_e  = gtk_entry_new();  gtk_entry_set_text(GTK_ENTRY(hn_e), "lanxiu");
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
    sysinfo_rows(v);
    gtk_box_pack_start(GTK_BOX(v), fin, FALSE, FALSE, 4);
    gtk_box_pack_start(GTK_BOX(v), status_lb, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(win), v);
    gtk_widget_show_all(win);

    /* 自动化验证: QYWELCOME_FILL=1 启动后自动填写表单 */
    if (g_getenv("QYWELCOME_FILL"))
        g_timeout_add(800, auto_fill, NULL);
}

/* 自动化验证: QYWELCOME_FILL=1 启动后自动填写表单 */
static gboolean auto_fill(gpointer p) {
    (void)p;
    gtk_entry_set_text(GTK_ENTRY(hn_e), "lanxiu");
    gtk_entry_set_text(GTK_ENTRY(un_e), "user");
    gtk_entry_set_text(GTK_ENTRY(pw_e), "123456");
    gtk_entry_set_text(GTK_ENTRY(pw2_e), "123456");
    gtk_entry_set_text(GTK_ENTRY(tz_e), "Asia/Shanghai");
    g_printerr("QYWELCOMEDBG: filled host=lanxiu user=user tz=Asia/Shanghai\n");
    return G_SOURCE_REMOVE;
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

    if (!*hn) hn = "lanxiu";
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
    set_status(TR("OK 配置完成！重启或直接使用。"));
    gtk_button_set_label(b, TR("已完成"));
    gtk_widget_set_sensitive(GTK_WIDGET(b), FALSE);
}

int main(int argc, char **argv) {
    /* 已配置过 → 直接退出 */
    FILE *f = fopen("/etc/.qywelcomed", "r");
    if (f) { fclose(f); return 0; }

    GtkApplication *app = gtk_application_new("com.lanxiu.welcome", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int rc = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return rc;
}
