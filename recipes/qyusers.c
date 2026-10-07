/* qyusers - 启元用户管理 (GTK3)
 * 功能: 用户列表 (uid>=1000) / 新建用户 (调 qyuseradd) / 修改密码 (busybox chpasswd) / 删除用户
 * 提权: 经 qysudo 执行写操作 (wheel 用户密码校验)
 */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static GtkWidget *list_box = NULL;
static GtkWidget *status_lb = NULL;
static GtkWidget *win = NULL;

static void on_pw_clicked(GtkButton *b, gpointer ud);
static void on_del_clicked(GtkButton *b, gpointer ud);

/* ---------- 工具 ---------- */
static char *read_first_line(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return NULL;
    char buf[512];
    if (!fgets(buf, sizeof buf, f)) { fclose(f); return NULL; }
    fclose(f);
    buf[strcspn(buf, "\n")] = 0;
    return g_strdup(buf);
}

static void set_status(const char *msg) {
    gtk_label_set_text(GTK_LABEL(status_lb), msg);
}

/* ---------- 刷新用户列表 ---------- */
typedef struct {
    char name[64];
    int uid;
    char home[128];
    int in_wheel;
} URow;

static URow rows[64];
static int nrows = 0;

static gboolean user_in_wheel(const char *name) {
    char *gl = read_first_line("/etc/group"); /* 需要遍历, 简化: 直接搜文件 */
    (void)gl;
    FILE *f = fopen("/etc/group", "r");
    if (!f) return FALSE;
    char line[512];
    gboolean found = FALSE;
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, "wheel:", 6) == 0) {
            if (strstr(line, name)) found = TRUE;
            break;
        }
    }
    fclose(f);
    return found;
}

static void refresh_list(void) {
    /* 清空 */
    GList *ch = gtk_container_get_children(GTK_CONTAINER(list_box));
    for (GList *it = ch; it; it = it->next)
        gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(ch);
    nrows = 0;

    FILE *f = fopen("/etc/passwd", "r");
    if (!f) { set_status(TR("无法读取 /etc/passwd")); return; }
    char line[512];
    int total = 0;
    while (fgets(line, sizeof line, f) && nrows < 64) {
        total++;
        line[strcspn(line, "\n")] = 0;
        char *c1 = strchr(line, ':'); if (!c1) continue;
        char *c2 = strchr(c1+1, ':'); if (!c2) continue;
        char *c3 = strchr(c2+1, ':'); if (!c3) continue;
        char *c4 = strchr(c3+1, ':'); if (!c4) continue;
        char *c5 = strchr(c4+1, ':'); if (!c5) continue;
        *c1 = 0; *c2 = 0; *c3 = 0; *c4 = 0; *c5 = 0;
        int uid = atoi(c3 + 1);
        if (uid < 1000) continue;   /* 只列普通用户 */
        URow *r = &rows[nrows++];
        snprintf(r->name, sizeof r->name, "%s", line);
        r->uid = uid;
        {
            snprintf(r->home, sizeof r->home, "%s", c5+1);
            char *cl = strchr(r->home, ':');
            if (cl) *cl = 0;
        }
        r->in_wheel = user_in_wheel(r->name);
    }
    fclose(f);

    if (nrows == 0) {
        GtkWidget *lb = gtk_label_new(TR("（暂无普通用户）"));
        gtk_box_pack_start(GTK_BOX(list_box), lb, FALSE, FALSE, 4);
        gtk_widget_show_all(list_box);
        return;
    }
    for (int i = 0; i < nrows; i++) {
        char info[256];
        snprintf(info, sizeof info, "%s　uid=%d　%s%s",
                 rows[i].name, rows[i].uid, rows[i].home,
                 rows[i].in_wheel ? "　[wheel]" : "");
        GtkWidget *hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *lb = gtk_label_new(info);
        gtk_widget_set_halign(lb, GTK_ALIGN_START);
        GtkWidget *pw = gtk_button_new_with_label(TR("改密"));
        GtkWidget *del = gtk_button_new_with_label(TR("删除"));
        gtk_box_pack_start(GTK_BOX(hb), lb, TRUE, TRUE, 2);
        gtk_box_pack_start(GTK_BOX(hb), pw, FALSE, FALSE, 2);
        gtk_box_pack_start(GTK_BOX(hb), del, FALSE, FALSE, 2);
        /* 回调: 携带用户名拷贝 */
        g_object_set_data_full(G_OBJECT(pw), "user", g_strdup(rows[i].name), g_free);
        g_object_set_data_full(G_OBJECT(del), "user", g_strdup(rows[i].name), g_free);
        g_signal_connect(pw, "clicked", G_CALLBACK(on_pw_clicked), NULL);
        g_signal_connect(del, "clicked", G_CALLBACK(on_del_clicked), NULL);
        gtk_box_pack_start(GTK_BOX(list_box), hb, FALSE, FALSE, 4);
    }
    gtk_widget_show_all(list_box);
}

/* ---------- 改密 / 删除 ---------- */
static void on_pw_clicked(GtkButton *b, gpointer ud) {
    const char *name = g_object_get_data(G_OBJECT(b), "user");
    if (!name) return;
    GtkWidget *dlg = gtk_dialog_new_with_buttons(TR("修改密码"), GTK_WINDOW(win), GTK_DIALOG_MODAL,
        TR("_取消"), GTK_RESPONSE_CANCEL, TR("_确定"), GTK_RESPONSE_OK, NULL);
    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_column_spacing(GTK_GRID(grid), 8);
    gtk_container_set_border_width(GTK_CONTAINER(grid), 12);
    GtkWidget *pe = gtk_entry_new();
    gtk_entry_set_visibility(GTK_ENTRY(pe), FALSE);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(name), 0, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), pe, 1, 0, 1, 1);
    GtkWidget *area = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    gtk_box_pack_start(GTK_BOX(area), grid, TRUE, TRUE, 0);
    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *pw = gtk_entry_get_text(GTK_ENTRY(pe));
        if (*pw) {
            gchar *cmd = g_strdup_printf("echo '%s:%s' | busybox chpasswd >/dev/null 2>&1", name, pw);
            int rc = system(cmd);
            g_free(cmd);
            set_status(rc == 0 ? TR("密码已修改") : TR("修改失败"));
        }
    }
    gtk_widget_destroy(dlg);
}

static void on_del_clicked(GtkButton *b, gpointer ud) {
    const char *name = g_object_get_data(G_OBJECT(b), "user");
    if (!name) return;
    GtkWidget *dlg = gtk_message_dialog_new(GTK_WINDOW(win), GTK_DIALOG_MODAL,
        GTK_MESSAGE_QUESTION, GTK_BUTTONS_OK_CANCEL,
        TR("确认删除用户 %s？（home 目录一并删除）"), name);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        gchar *cmd = g_strdup_printf(
            "sed -i '/^%s:/d' /etc/passwd /etc/group /etc/shadow; "
            "sed -i \"s/,%s//g\" /etc/group; rm -rf /home/%s", name, name, name);
        int rc = system(cmd);
        g_free(cmd);
        set_status(rc == 0 ? TR("已删除") : TR("删除失败"));
        refresh_list();
    }
    gtk_widget_destroy(dlg);
}

/* ---------- 动作 ---------- */
static void on_add_clicked(GtkButton *b, gpointer ud) {
    GtkWidget *dlg = gtk_dialog_new_with_buttons(TR("新建用户"), GTK_WINDOW(win), GTK_DIALOG_MODAL,
        TR("_取消"), GTK_RESPONSE_CANCEL, TR("_创建"), GTK_RESPONSE_OK, NULL);
    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 6);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 8);
    gtk_container_set_border_width(GTK_CONTAINER(grid), 12);
    GtkWidget *ne = gtk_entry_new();
    GtkWidget *pe = gtk_entry_new();
    gtk_entry_set_visibility(GTK_ENTRY(pe), FALSE);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(TR("用户名")), 0, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), ne, 1, 0, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(TR("初始密码")), 0, 1, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), pe, 1, 1, 1, 1);
    GtkWidget *cb = gtk_check_button_new_with_label(TR("加入 wheel 组（可 qysudo 提权）"));
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(cb), TRUE);
    gtk_grid_attach(GTK_GRID(grid), cb, 0, 2, 2, 1);
    GtkWidget *area = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    gtk_box_pack_start(GTK_BOX(area), grid, TRUE, TRUE, 0);
    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *name = gtk_entry_get_text(GTK_ENTRY(ne));
        const char *pw = gtk_entry_get_text(GTK_ENTRY(pe));
        if (*name) {
            gchar *cmd;
            if (*pw)
                cmd = g_strdup_printf("qyuseradd '%s' '%s'", name, pw);
            else
                cmd = g_strdup_printf("qyuseradd '%s'", name);
            int rc = system(cmd);
            g_free(cmd);
            /* 非 wheel: 从组里去掉 */
            if (!gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(cb))) {
                gchar *cmd2 = g_strdup_printf("sed -i \"s/,%s//\" /etc/group", name);
                system(cmd2); g_free(cmd2);
            }
            if (rc == 0)
                set_status(TR("创建成功"));
            else
                set_status(TR("创建失败（重名？）"));
            refresh_list();
        }
    }
    gtk_widget_destroy(dlg);
}

static void on_refresh_clicked(GtkButton *b, gpointer ud) {
    refresh_list();
    set_status(TR("已刷新"));
}

static void activate(GtkApplication *app, gpointer ud) {
    qy_load_theme();
    win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元用户管理"));
    gtk_window_set_default_size(GTK_WINDOW(win), 520, 420);
    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_set_border_width(GTK_CONTAINER(v), 14);
    GtkWidget *tb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *add = gtk_button_new_with_label(TR("＋ 新建用户"));
    GtkWidget *rf = gtk_button_new_with_label(TR("刷新"));
    gtk_box_pack_start(GTK_BOX(tb), add, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tb), rf, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tb), gtk_label_new(""), TRUE, TRUE, 0);
    g_signal_connect(add, "clicked", G_CALLBACK(on_add_clicked), NULL);
    g_signal_connect(rf, "clicked", G_CALLBACK(on_refresh_clicked), NULL);
    list_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    GtkWidget *sc = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(sc), list_box);
    gtk_widget_set_vexpand(sc, TRUE);
    status_lb = gtk_label_new(TR("就绪"));
    gtk_box_pack_start(GTK_BOX(v), tb, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v), sc, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(v), status_lb, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(win), v);
    refresh_list();
    gtk_widget_show_all(win);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.users", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int rc = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return rc;
}
