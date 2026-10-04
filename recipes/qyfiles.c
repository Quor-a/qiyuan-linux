/* qyfiles - 启元文件管理器 (GTK3) — v2: 重命名/删除+回收站/新建文件夹/右键菜单 */
#include <gtk/gtk.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <glib/gstdio.h>

static GtkWidget *view;
static GtkWidget *status;
static char cwd[4096];
static void chdir_to(const char *path);

/* ---------- freedesktop Trash 规范: ~/.local/share/Trash/files + info ---------- */
static void trash_dir(char *files, size_t fl, char *info, size_t il) {
    const char *home = g_get_home_dir();
    snprintf(files, fl, "%s/.local/share/Trash/files", home);
    snprintf(info, il, "%s/.local/share/Trash/info", home);
    g_mkdir_with_parents(files, 0700);
    g_mkdir_with_parents(info, 0700);
}

/* 同名原子命名: name.txt → name.2.txt */
static void unique_trash_name(const char *files, const char *name, char *out, size_t ol) {
    snprintf(out, ol, "%s/%s", files, name);
    if (g_file_test(out, G_FILE_TEST_EXISTS)) {
        const char *dot = strrchr(name, '.');
        for (int i = 2; ; i++) {
            if (dot && dot != name) {
                char base[512]; size_t bl = dot - name;
                if (bl >= sizeof base) bl = sizeof base - 1;
                memcpy(base, name, bl); base[bl] = 0;
                snprintf(out, ol, "%s/%s.%d%s", files, base, i, dot);
            } else {
                snprintf(out, ol, "%s/%s.%d", files, name, i);
            }
            if (!g_file_test(out, G_FILE_TEST_EXISTS)) break;
        }
    }
}

static gboolean trash_file(const char *path, GError **err) {
    char files[4096], info[4096], tname[4096], tinfo[4096];
    trash_dir(files, sizeof files, info, sizeof info);
    const char *name = strrchr(path, '/');
    name = name ? name + 1 : path;
    unique_trash_name(files, name, tname, sizeof tname);
    /* mv 到 files/ */
    gchar *cmd = g_strdup_printf("mv -b -- %s %s 2>/dev/null", path, tname);
    int rc = system(cmd);
    g_free(cmd);
    if (rc != 0) { g_set_error(err, 0, 1, "move failed"); return FALSE; }
    /* 写 .trashinfo */
    const char *bn = strrchr(tname, '/') + 1;
    snprintf(tinfo, sizeof tinfo, "%s/%s.trashinfo", info, bn);
    GDateTime *now = g_date_time_new_now_local();
    gchar *iso = g_date_time_format(now, "%Y-%m-%dT%H:%M:%S");
    FILE *f = fopen(tinfo, "w");
    if (f) {
        fprintf(f, "[Trash Info]\nPath=%s\nDeletionDate=%s\n", path, iso);
        fclose(f);
    }
    g_date_time_unref(now); g_free(iso);
    return TRUE;
}

/* ---------- 操作实现 ---------- */
static void do_delete(void) {
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
    GtkTreeIter it;
    if (!gtk_tree_selection_get_selected(sel, NULL, &it)) return;
    GtkTreeModel *m = gtk_tree_view_get_model(GTK_TREE_VIEW(view));
    gchar *name;
    gtk_tree_model_get(m, &it, 1, &name, -1);
    gchar *full = g_build_filename(cwd, name, NULL);
    GError *err = NULL;
    if (!trash_file(full, &err)) {
        gchar *msg = g_strdup_printf("删除失败: %s", err ? err->message : "?");
        gtk_label_set_text(GTK_LABEL(status), msg);
        g_free(msg); g_clear_error(&err);
    }
    g_free(name); g_free(full);
    chdir_to(cwd);
}

static void do_rename(void) {
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
    GtkTreeIter it;
    if (!gtk_tree_selection_get_selected(sel, NULL, &it)) return;
    GtkTreeModel *m = gtk_tree_view_get_model(GTK_TREE_VIEW(view));
    gchar *name;
    gtk_tree_model_get(m, &it, 1, &name, -1);
    GtkWidget *dlg = gtk_dialog_new_with_buttons("重命名", GTK_WINDOW(gtk_widget_get_toplevel(view)),
        GTK_DIALOG_MODAL, "_取消", GTK_RESPONSE_CANCEL, "_确定", GTK_RESPONSE_OK, NULL);
    GtkWidget *entry = gtk_entry_new();
    gtk_entry_set_text(GTK_ENTRY(entry), name);
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    gtk_box_pack_start(GTK_BOX(box), gtk_label_new("新名称:"), FALSE, FALSE, 4);
    gtk_box_pack_start(GTK_BOX(box), entry, FALSE, FALSE, 4);
    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *nn = gtk_entry_get_text(GTK_ENTRY(entry));
        if (nn[0] && strcmp(nn, name) != 0) {
            gchar *oldf = g_build_filename(cwd, name, NULL);
            gchar *newf = g_build_filename(cwd, nn, NULL);
            gchar *cmd = g_strdup_printf("mv -b -- %s %s", oldf, newf);
            if (system(cmd) == 0) gtk_label_set_text(GTK_LABEL(status), "重命名完成");
            g_free(cmd); g_free(oldf); g_free(newf);
        }
    }
    gtk_widget_destroy(dlg);
    g_free(name);
    chdir_to(cwd);
}

static void do_mkdir(void) {
    GtkWidget *dlg = gtk_dialog_new_with_buttons("新建文件夹", GTK_WINDOW(gtk_widget_get_toplevel(view)),
        GTK_DIALOG_MODAL, "_取消", GTK_RESPONSE_CANCEL, "_确定", GTK_RESPONSE_OK, NULL);
    GtkWidget *entry = gtk_entry_new();
    gtk_entry_set_text(GTK_ENTRY(entry), "新建文件夹");
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    gtk_box_pack_start(GTK_BOX(box), entry, FALSE, FALSE, 6);
    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *nn = gtk_entry_get_text(GTK_ENTRY(entry));
        if (nn[0]) {
            gchar *full = g_build_filename(cwd, nn, NULL);
            if (g_mkdir(full, 0755) == 0) gtk_label_set_text(GTK_LABEL(status), "文件夹已创建");
            else gtk_label_set_text(GTK_LABEL(status), "创建失败");
            g_free(full);
        }
    }
    gtk_widget_destroy(dlg);
    chdir_to(cwd);
}

/* ---------- 右键菜单 ---------- */
/* ---------- 右键: 崩溃规避 (裸 Wayland 下 GtkMenu popup 不稳) → 选中该行 + 状态栏提示, 操作走工具栏按钮 ---------- */
static gboolean on_popup(GtkWidget *w, GdkEventButton *ev, gpointer ud) {
    if (ev->type == GDK_BUTTON_PRESS && ev->button == 3) {
        GtkTreePath *path = NULL;
        GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
        if (gtk_tree_view_get_path_at_pos(GTK_TREE_VIEW(view),
                (gint)ev->x, (gint)ev->y, &path, NULL, NULL, NULL) && path) {
            gtk_tree_selection_unselect_all(sel);
            gtk_tree_selection_select_path(sel, path);
            gtk_tree_path_free(path);
            gtk_label_set_text(GTK_LABEL(status), "已选中: 用工具栏[新建文件夹/删除/重命名]操作");
        }
        return TRUE;
    }
    return FALSE;
}

/* ---------- 导航 ---------- */
static void chdir_to(const char *path) {
    GtkListStore *store = GTK_LIST_STORE(gtk_tree_view_get_model(GTK_TREE_VIEW(view)));
    gtk_list_store_clear(store);
    GDir *dir = g_dir_open(path, 0, NULL);
    if (!dir) return;
    const gchar *name;
    while ((name = g_dir_read_name(dir))) {
        gchar *full = g_build_filename(path, name, NULL);
        gboolean isdir = g_file_test(full, G_FILE_TEST_IS_DIR);
        g_free(full);
        GtkTreeIter it;
        gtk_list_store_append(store, &it);
        gtk_list_store_set(store, &it, 0, isdir ? "[目录]" : "[文件]", 1, name, -1);
    }
    g_dir_close(dir);
    gchar *msg = g_strdup_printf("位置: %s", path);
    gtk_label_set_text(GTK_LABEL(status), msg);
    g_free(msg);
    g_strlcpy(cwd, path, sizeof cwd);
}

static void on_activated(GtkTreeView *tv, GtkTreePath *path, GtkTreeViewColumn *col, gpointer ud) {
    GtkTreeModel *m = gtk_tree_view_get_model(tv);
    GtkTreeIter it;
    gchar *name;
    gtk_tree_model_get_iter(m, &it, path);
    gtk_tree_model_get(m, &it, 1, &name, -1);
    gchar *full = g_build_filename(cwd, name, NULL);
    if (g_file_test(full, G_FILE_TEST_IS_DIR)) chdir_to(full);
    g_free(name); g_free(full);
}

static void on_up(GtkButton *b, gpointer ud) {
    gchar *parent = g_path_get_dirname(cwd);
    chdir_to(parent);
    g_free(parent);
}

static void on_home(GtkButton *b, gpointer ud) { chdir_to("/"); }

static void activate(GtkApplication *app, gpointer ud) {
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), "启元文件管理器");
    GdkGeometry geo = { .max_width = 1920, .max_height = 1080 };
    gtk_window_set_geometry_hints(GTK_WINDOW(win), NULL, &geo, GDK_HINT_MAX_SIZE);
    gtk_window_set_default_size(GTK_WINDOW(win), 640, 460);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_box_pack_start(GTK_BOX(vbox), hbox, FALSE, FALSE, 2);
    GtkWidget *b_home = gtk_button_new_with_label("/ 根目录");
    g_signal_connect(b_home, "clicked", G_CALLBACK(on_home), NULL);
    GtkWidget *b_up = gtk_button_new_with_label("上一级");
    g_signal_connect(b_up, "clicked", G_CALLBACK(on_up), NULL);
    GtkWidget *b_mk = gtk_button_new_with_label("新建文件夹");
    g_signal_connect(b_mk, "clicked", G_CALLBACK(do_mkdir), NULL);
    GtkWidget *b_del = gtk_button_new_with_label("删除");
    g_signal_connect(b_del, "clicked", G_CALLBACK(do_delete), NULL);
    GtkWidget *b_ren = gtk_button_new_with_label("重命名");
    g_signal_connect(b_ren, "clicked", G_CALLBACK(do_rename), NULL);
    gtk_box_pack_start(GTK_BOX(hbox), b_home, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_up, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_mk, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_del, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_ren, FALSE, FALSE, 0);

    GtkListStore *store = gtk_list_store_new(2, G_TYPE_STRING, G_TYPE_STRING);
    view = gtk_tree_view_new_with_model(GTK_TREE_MODEL(store));
    GtkCellRenderer *r1 = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(view), -1, "类型", r1, "text", 0, NULL);
    GtkCellRenderer *r2 = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(view), -1, "名称", r2, "text", 1, NULL);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(scroll), view);
    gtk_box_pack_start(GTK_BOX(vbox), scroll, TRUE, TRUE, 0);
    g_signal_connect(view, "row-activated", G_CALLBACK(on_activated), NULL);
    g_signal_connect(view, "button-press-event", G_CALLBACK(on_popup), NULL);

    status = gtk_label_new("位置: /");
    gtk_widget_set_halign(status, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), status, FALSE, FALSE, 2);

    gtk_widget_show_all(win);
    chdir_to("/");
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.files", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int rc = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return rc;
}
