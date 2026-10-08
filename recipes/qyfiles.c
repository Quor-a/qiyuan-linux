/* qyfiles - 启元文件管理器 (GTK3) — v3: 回收站页(还原/清空) + 侧边栏 + 彻底删除 */
#include "qyl10n.h"
#include <gtk/gtk.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <glib/gstdio.h>

static GtkWidget *view;
static GtkWidget *status;
static char cwd[4096];
static int in_trash = 0;   /* 当前是否处于回收站页 */
static int g_argc = 0;     /* main 传下: --trash 检测用 */
static char **g_argv = NULL;
static void chdir_to(const char *path);
static void chdir_trash(void);

/* v2.0 主题 + 工具栏状态按钮 */
static void load_theme(void) {
    GtkCssProvider *p = gtk_css_provider_new();
    if (gtk_css_provider_load_from_path(p, "/usr/share/themes/qiyuan/gtk-3.0/gtk.css", NULL)) {
        gtk_style_context_add_provider_for_screen(
            gdk_screen_get_default(), GTK_STYLE_PROVIDER(p),
            GTK_STYLE_PROVIDER_PRIORITY_USER);
    }
    g_object_unref(p);
}

static void add_class(GtkWidget *w, const char *cls) {
    gtk_style_context_add_class(gtk_widget_get_style_context(w), cls);
}

/* 工具栏按钮（按 普通目录 / 回收站 切换可见性） */
static GtkWidget *b_mk = NULL, *b_del = NULL, *b_ren = NULL;
static GtkWidget *b_open = NULL;
static GtkWidget *b_cp = NULL;
static GtkWidget *b_res = NULL, *b_pur = NULL, *b_emp = NULL;

static void set_mode_buttons(void) {
    if (!b_mk) return;
    gboolean trash = in_trash;
    gtk_widget_set_visible(b_mk, !trash);
    gtk_widget_set_visible(b_del, !trash);
    gtk_widget_set_visible(b_ren, !trash);
    gtk_widget_set_visible(b_open, !trash);
    gtk_widget_set_visible(b_cp, !trash);
    gtk_widget_set_visible(b_res, trash);
    gtk_widget_set_visible(b_pur, trash);
    gtk_widget_set_visible(b_emp, trash);
}

/* ---------- freedesktop Trash 规范: ~/.local/share/Trash/files + info ---------- */
static void trash_dir(char *files, size_t fl, char *info, size_t il) {
    const char *home = g_get_home_dir();
    if (files && fl) snprintf(files, fl, "%s/.local/share/Trash/files", home);
    if (info && il) snprintf(info, il, "%s/.local/share/Trash/info", home);
    if (files && fl) g_mkdir_with_parents(files, 0700);
    if (info && il) g_mkdir_with_parents(info, 0700);
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

/* 读取 .trashinfo 的 Path= 行 */
static gboolean read_trashinfo(const char *tinfo, char *out, size_t ol) {
    FILE *f = fopen(tinfo, "r");
    if (!f) return FALSE;
    char line[4096];
    gboolean ok = FALSE;
    while (fgets(line, sizeof line, f)) {
        if (!strncmp(line, "Path=", 5)) {
            line[strcspn(line, "\r\n")] = 0;
            /* 规范: Path 为 URL 编码, 这里按字面处理(%20 之外的常见场景) */
            g_strlcpy(out, line + 5, ol);
            ok = TRUE;
            break;
        }
    }
    fclose(f);
    return ok;
}

/* ---------- 操作实现 ---------- */
static void selected_name(gchar **name) {
    *name = NULL;
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
    GtkTreeIter it;
    if (!gtk_tree_selection_get_selected(sel, NULL, &it)) return;
    GtkTreeModel *m = gtk_tree_view_get_model(GTK_TREE_VIEW(view));
    gtk_tree_model_get(m, &it, 1, name, -1);
}

static void do_delete(void) {
    gchar *name; selected_name(&name);
    if (!name) return;
    gchar *full = g_build_filename(in_trash ? "" : cwd, name, NULL);
    if (in_trash) { g_free(name); g_free(full); return; }
    GError *err = NULL;
    if (!trash_file(full, &err)) {
        gchar *msg = g_strdup_printf(TR("删除失败: %s"), err ? err->message : "?");
        gtk_label_set_text(GTK_LABEL(status), msg);
        g_free(msg); g_clear_error(&err);
    }
    g_free(name); g_free(full);
    chdir_to(cwd);
}

/* 彻底删除 (Shift+Delete 语义): 回收站内或普通目录 rm -rf */
static void do_purge(void) {
    gchar *name; selected_name(&name);
    if (!name) return;
    gchar *full = in_trash
        ? g_build_filename(g_get_home_dir(), ".local/share/Trash/files", name, NULL)
        : g_build_filename(cwd, name, NULL);
    GtkWidget *dlg = gtk_message_dialog_new(GTK_WINDOW(gtk_widget_get_toplevel(view)),
        GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING, GTK_BUTTONS_OK_CANCEL,
        TR("彻底删除 \"%s\"? 不可恢复!"), name);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        gchar *cmd = g_strdup_printf("rm -rf -- %s", full);
        int rc = system(cmd);
        g_free(cmd);
        gtk_label_set_text(GTK_LABEL(status), rc == 0 ? TR("已彻底删除") : TR("删除失败"));
        if (in_trash) {
            char info[4096];
            trash_dir(NULL, 0, info, sizeof info);
            gchar *ti = g_strdup_printf("%s/%s.trashinfo", info, name);
            g_unlink(ti); g_free(ti);
        }
    }
    gtk_widget_destroy(dlg);
    g_free(name); g_free(full);
    if (in_trash) chdir_trash(); else chdir_to(cwd);
}

/* 还原: files/<name> → info 的 Path, 目标已存在则加 .restored 后缀 */
static void do_restore(void) {
    gchar *name; selected_name(&name);
    if (!name) return;
    char info[4096], orig[4096];
    trash_dir(NULL, 0, info, sizeof info);
    gchar *ti = g_strdup_printf("%s/%s.trashinfo", info, name);
    if (!read_trashinfo(ti, orig, sizeof orig)) {
        gtk_label_set_text(GTK_LABEL(status), TR("还原失败: 无元数据"));
        g_free(name); g_free(ti); return;
    }
    g_free(ti);
    if (g_file_test(orig, G_FILE_TEST_EXISTS)) {
        gchar *alt = g_strdup_printf("%s.restored", orig);
        g_strlcpy(orig, alt, sizeof orig);
        g_free(alt);
    }
    gchar *src = g_build_filename(g_get_home_dir(), ".local/share/Trash/files", name, NULL);
    gchar *cmd = g_strdup_printf("mv -b -- %s %s", src, orig);
    int rc = system(cmd);
    g_free(cmd); g_free(src);
    if (rc == 0) {
        g_unlink(ti);
        gchar *msg = g_strdup_printf(TR("已还原到 %s"), orig);
        gtk_label_set_text(GTK_LABEL(status), msg);
        g_free(msg);
    } else {
        gtk_label_set_text(GTK_LABEL(status), TR("还原失败"));
    }
    g_free(name);
    chdir_trash();
}

/* 清空回收站 (二次确认) */
static void do_empty_trash(void) {
    GtkWidget *dlg = gtk_message_dialog_new(GTK_WINDOW(gtk_widget_get_toplevel(view)),
        GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING, GTK_BUTTONS_OK_CANCEL,
        TR("清空回收站? 全部内容不可恢复!"));
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        char files[4096], info[4096];
        trash_dir(files, sizeof files, info, sizeof info);
        gchar *c1 = g_strdup_printf("rm -rf -- %s/* %s/*", files, info);
        system(c1); g_free(c1);
        gtk_label_set_text(GTK_LABEL(status), "回收站已清空");
    }
    gtk_widget_destroy(dlg);
    if (in_trash) chdir_trash();
}

static void do_rename(void) {
    gchar *name; selected_name(&name);
    if (!name) return;
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

/* 复制选中文件为副本（"名字 副本.ext" / 已存在则 副本.2.ext） */
static void do_copy_named(const char *name) {
    if (!name || !name[0]) return;
    const char *dot = strrchr(name, '.');
    const char *suffix = TR("副本");
    gchar *dst = NULL;
    if (dot && dot != name) {
        gchar *base = g_strndup(name, dot - name);
        dst = g_strdup_printf("%s%s%s", base, suffix, dot);
        g_free(base);
    } else {
        dst = g_strdup_printf("%s%s", name, suffix);
    }
    if (g_file_test(dst, G_FILE_TEST_EXISTS)) {
        for (int i = 2; ; i++) {
            g_free(dst); dst = NULL;
            if (dot && dot != name) {
                gchar *base = g_strndup(name, dot - name);
                dst = g_strdup_printf("%s%s.%d%s", base, suffix, i, dot);
                g_free(base);
            } else {
                dst = g_strdup_printf("%s%s.%d", name, suffix, i);
            }
            if (!g_file_test(dst, G_FILE_TEST_EXISTS)) break;
        }
    }
    gchar *src_full = g_build_filename(cwd, name, NULL);
    gchar *dst_full = g_build_filename(cwd, dst, NULL);
    gchar *cmd = g_strdup_printf("cp -r -- %s %s", g_shell_quote(src_full), g_shell_quote(dst_full));
    int rc = system(cmd);
    g_free(cmd); g_free(src_full); g_free(dst_full);
    if (rc == 0) {
        gchar *msg = g_strdup_printf("%s: %s", TR("复制成功"), dst);
        gtk_label_set_text(GTK_LABEL(status), msg);
        g_free(msg);
        if (in_trash) chdir_trash(); else chdir_to(cwd);
    } else {
        gtk_label_set_text(GTK_LABEL(status), TR("复制失败"));
    }
    g_free(dst);
}

static gboolean auto_copy(gpointer p) {
    do_copy_named((const char *)p);
    g_free(p);
    return G_SOURCE_REMOVE;
}

static void do_copy(GtkButton *b, gpointer ud) {
    (void)b; (void)ud;
    gchar *name;
    selected_name(&name);
    if (!name) { gtk_label_set_text(GTK_LABEL(status), TR("请先选择一个文件")); return; }
    do_copy_named(name);
    g_free(name);
}

/* ---------- 侧边栏导航 ---------- */
static void on_side(GtkButton *b, gpointer ud) {
    const char *p = (const char *)ud;
    if (!strcmp(p, "TRASH")) chdir_trash();
    else chdir_to(p);
}

static GtkWidget *side_button(const char *label, const char *target, GtkWidget *box) {
    GtkWidget *b = gtk_button_new_with_label(label);
    gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
    add_class(b, "qy-files-side");
    char *t = g_strdup(target);
    g_signal_connect(b, "clicked", G_CALLBACK(on_side), t);
    gtk_box_pack_start(GTK_BOX(box), b, FALSE, FALSE, 1);
    return b;
}

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
            gtk_label_set_text(GTK_LABEL(status), in_trash
                ? TR("已选中: 用工具栏[还原/彻底删除]操作")
                : TR("已选中: 用工具栏[新建文件夹/删除/重命名]操作"));
        }
        return TRUE;
    }
    return FALSE;
}

/* ---------- 导航 ---------- */
static void chdir_to(const char *path) {
    in_trash = 0;
    set_mode_buttons();
    GtkListStore *store = GTK_LIST_STORE(gtk_tree_view_get_model(GTK_TREE_VIEW(view)));
    gtk_list_store_clear(store);
    GDir *dir = g_dir_open(path, 0, NULL);
    gint n = 0, ndir = 0, nfile = 0;
    if (!dir) return;
    const gchar *name;
    while ((name = g_dir_read_name(dir))) {
        gchar *full = g_build_filename(path, name, NULL);
        gboolean isdir = g_file_test(full, G_FILE_TEST_IS_DIR);
        char sizestr[32] = "—";
        if (!isdir) {
            struct stat st;
            if (stat(full, &st) == 0) {
                if (st.st_size >= 1024 * 1024)
                    g_snprintf(sizestr, sizeof sizestr, "%.1f MB", st.st_size / 1024.0 / 1024.0);
                else if (st.st_size >= 1024)
                    g_snprintf(sizestr, sizeof sizestr, "%.1f KB", st.st_size / 1024.0);
                else
                    g_snprintf(sizestr, sizeof sizestr, "%ld B", (long)st.st_size);
            }
        }
        g_free(full);
        GtkTreeIter it;
        gtk_list_store_append(store, &it);
        gtk_list_store_set(store, &it, 0, isdir ? TR("[目录]") : TR("[文件]"), 1, name, 2, sizestr, -1);
        n++;
        if (isdir) ndir++; else nfile++;
    }
    g_dir_close(dir);
    gchar *msg = g_strdup_printf(TR("位置: %s · %d 项"), path, n);
    if (n == 0) {
        char tmp[512];
        g_snprintf(tmp, sizeof tmp, "%s — %s", msg, TR("此文件夹为空"));
        g_free(msg);
        msg = g_strdup(tmp);
    }
    gtk_label_set_text(GTK_LABEL(status), msg);
    g_free(msg);
    g_strlcpy(cwd, path, sizeof cwd);
}

static void chdir_trash(void) {
    in_trash = 1;
    set_mode_buttons();
    char files[4096], info[4096];
    trash_dir(files, sizeof files, info, sizeof info);
    GtkListStore *store = GTK_LIST_STORE(gtk_tree_view_get_model(GTK_TREE_VIEW(view)));
    gtk_list_store_clear(store);
    GDir *dir = g_dir_open(files, 0, NULL);
    gint n = 0;
    if (dir) {
        const gchar *name;
        while ((name = g_dir_read_name(dir))) {
            gchar *ti = g_strdup_printf("%s/%s.trashinfo", info, name);
            char orig[4096];
            GtkTreeIter it;
            gtk_list_store_append(store, &it);
            if (read_trashinfo(ti, orig, sizeof orig)) {
                gtk_list_store_set(store, &it, 0, orig, 1, name, 2, TR("—"), -1);
            } else {
                gtk_list_store_set(store, &it, 0, TR("(无元数据)"), 1, name, 2, TR("—"), -1);
            }
            g_free(ti);
            n++;
        }
        g_dir_close(dir);
    }
    if (n == 0)
        gtk_label_set_text(GTK_LABEL(status), TR("回收站为空"));
    else
        gtk_label_set_text(GTK_LABEL(status), TR("位置: 回收站 (工具栏: 还原 / 彻底删除 / 清空)"));
    g_strlcpy(cwd, files, sizeof cwd);
}

/* 打开选中项：目录→进入；图片→qyview；文本→qyedit；其它→状态栏提示 */
static void open_path(const char *name) {
    if (in_trash) return;
    gchar *full = g_build_filename(cwd, name, NULL);
    if (g_file_test(full, G_FILE_TEST_IS_DIR)) { chdir_to(full); g_free(full); return; }
    const char *ext = strrchr(name, '.');
    gboolean is_img = FALSE, is_txt = FALSE;
    if (ext) {
        if (!g_ascii_strcasecmp(ext, ".png") || !g_ascii_strcasecmp(ext, ".jpg") ||
            !g_ascii_strcasecmp(ext, ".jpeg") || !g_ascii_strcasecmp(ext, ".bmp") ||
            !g_ascii_strcasecmp(ext, ".gif") || !g_ascii_strcasecmp(ext, ".webp"))
            is_img = TRUE;
        else if (!g_ascii_strcasecmp(ext, ".txt") || !g_ascii_strcasecmp(ext, ".c") ||
                 !g_ascii_strcasecmp(ext, ".h") || !g_ascii_strcasecmp(ext, ".md") ||
                 !g_ascii_strcasecmp(ext, ".sh") || !g_ascii_strcasecmp(ext, ".py") ||
                 !g_ascii_strcasecmp(ext, ".ini") || !g_ascii_strcasecmp(ext, ".conf") ||
                 !g_ascii_strcasecmp(ext, ".desktop") || !g_ascii_strcasecmp(ext, ".log"))
            is_txt = TRUE;
    }
    if (is_img || is_txt) {
        gchar *cmd = g_strdup_printf("%s '%s' &", is_img ? "qyview" : "qyedit", full);
        g_spawn_command_line_async(cmd, NULL);
        g_free(cmd);
    } else {
        char msg[512];
        g_snprintf(msg, sizeof msg, "%s — %s", name, TR("暂不支持打开该类型"));
        gtk_label_set_text(GTK_LABEL(status), msg);
    }
    g_free(full);
}

static void do_open_sel(GtkButton *b, gpointer ud) {
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
    GtkTreeModel *m;
    GtkTreeIter it;
    if (!gtk_tree_selection_get_selected(sel, &m, &it)) {
        gtk_label_set_text(GTK_LABEL(status), TR("请先选择一个文件"));
        return;
    }
    gchar *name;
    gtk_tree_model_get(m, &it, 1, &name, -1);
    open_path(name);
    g_free(name);
}

static void on_activated(GtkTreeView *tv, GtkTreePath *path, GtkTreeViewColumn *col, gpointer ud) {
    GtkTreeModel *m = gtk_tree_view_get_model(tv);
    GtkTreeIter it;
    gchar *name;
    gtk_tree_model_get_iter(m, &it, path);
    gtk_tree_model_get(m, &it, 1, &name, -1);
    open_path(name);
    g_free(name);
}

static void on_refresh(GtkButton *b, gpointer ud) {
    if (in_trash) chdir_trash();
    else chdir_to(cwd);
}

static void on_up(GtkButton *b, gpointer ud) {
    if (in_trash) { chdir_to("/"); return; }
    gchar *parent = g_path_get_dirname(cwd);
    chdir_to(parent);
    g_free(parent);
}

static void on_home(GtkButton *b, gpointer ud) { chdir_to(g_get_home_dir()); }

static void activate(GtkApplication *app, gpointer ud) {
    load_theme();
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元文件管理器"));
    GdkGeometry geo = { .max_width = 1920, .max_height = 1080 };
    gtk_window_set_geometry_hints(GTK_WINDOW(win), NULL, &geo, GDK_HINT_MAX_SIZE);
    gtk_window_set_default_size(GTK_WINDOW(win), 920, 560);

    GtkWidget *hpane = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_container_add(GTK_CONTAINER(win), hpane);

    /* 侧边栏 */
    GtkWidget *side = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_size_request(side, 120, -1);
    gtk_container_set_border_width(GTK_CONTAINER(side), 4);
    const char *home = g_get_home_dir();
    static char p_home[512], p_docs[512], p_dl[512], p_pics[512];
    snprintf(p_home, sizeof p_home, "%s", home);
    snprintf(p_docs, sizeof p_docs, TR("%s/文档"), home);
    snprintf(p_dl, sizeof p_dl, TR("%s/下载"), home);
    snprintf(p_pics, sizeof p_pics, TR("%s/图片"), home);
    side_button(TR("主目录"), p_home, side);
    side_button(TR("图片"), p_pics, side);
    side_button(TR("文档"), p_docs, side);
    side_button(TR("下载"), p_dl, side);
    side_button(TR("根目录 /"), "/", side);
    side_button(TR("回收站"), "TRASH", side);
    gtk_box_pack_start(GTK_BOX(hpane), side, FALSE, FALSE, 0);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_box_pack_start(GTK_BOX(hpane), vbox, TRUE, TRUE, 0);

    GtkWidget *hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *toolbar = gtk_event_box_new();
    gtk_container_add(GTK_CONTAINER(toolbar), hbox);
    add_class(toolbar, "qy-files-toolbar");
    gtk_box_pack_start(GTK_BOX(vbox), toolbar, FALSE, FALSE, 2);
    GtkWidget *b_ref = gtk_button_new_with_label(TR("刷新"));
    add_class(b_ref, "qy-btn");
    g_signal_connect(b_ref, "clicked", G_CALLBACK(on_refresh), NULL);
    GtkWidget *b_home = gtk_button_new_with_label(TR("主目录"));
    add_class(b_home, "qy-btn");
    g_signal_connect(b_home, "clicked", G_CALLBACK(on_home), NULL);
    GtkWidget *b_up = gtk_button_new_with_label(TR("上一级"));
    add_class(b_up, "qy-btn");
    g_signal_connect(b_up, "clicked", G_CALLBACK(on_up), NULL);
    b_mk = gtk_button_new_with_label(TR("新建文件夹"));
    add_class(b_mk, "qy-btn");
    g_signal_connect(b_mk, "clicked", G_CALLBACK(do_mkdir), NULL);
    b_del = gtk_button_new_with_label(TR("删除"));
    add_class(b_del, "qy-btn");
    g_signal_connect(b_del, "clicked", G_CALLBACK(do_delete), NULL);
    b_ren = gtk_button_new_with_label(TR("重命名"));
    add_class(b_ren, "qy-btn");
    g_signal_connect(b_ren, "clicked", G_CALLBACK(do_rename), NULL);
    b_cp = gtk_button_new_with_label(TR("复制"));
    add_class(b_cp, "qy-btn");
    g_signal_connect(b_cp, "clicked", G_CALLBACK(do_copy), NULL);
    b_open = gtk_button_new_with_label(TR("打开"));
    add_class(b_open, "qy-btn");
    g_signal_connect(b_open, "clicked", G_CALLBACK(do_open_sel), NULL);
    b_res = gtk_button_new_with_label(TR("还原"));
    add_class(b_res, "qy-btn qy-btn-danger");
    g_signal_connect(b_res, "clicked", G_CALLBACK(do_restore), NULL);
    b_pur = gtk_button_new_with_label(TR("彻底删除"));
    add_class(b_pur, "qy-btn qy-btn-danger");
    g_signal_connect(b_pur, "clicked", G_CALLBACK(do_purge), NULL);
    b_emp = gtk_button_new_with_label(TR("清空回收站"));
    add_class(b_emp, "qy-btn qy-btn-danger");
    g_signal_connect(b_emp, "clicked", G_CALLBACK(do_empty_trash), NULL);
    gtk_box_pack_start(GTK_BOX(hbox), b_ref, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_home, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_up, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_mk, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_del, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_ren, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_cp, FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(hbox), b_open, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_res, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_pur, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_emp, FALSE, FALSE, 0);

    GtkListStore *store = gtk_list_store_new(3, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING);
    view = gtk_tree_view_new_with_model(GTK_TREE_MODEL(store));
    GtkCellRenderer *r1 = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(view), -1, TR("类型/原位置"), r1, "text", 0, NULL);
    GtkCellRenderer *r2 = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(view), -1, TR("名称"), r2, "text", 1, NULL);
    GtkCellRenderer *r3 = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(view), -1, TR("大小"), r3, "text", 2, NULL);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(scroll), view);
    gtk_box_pack_start(GTK_BOX(vbox), scroll, TRUE, TRUE, 0);
    g_signal_connect(view, "row-activated", G_CALLBACK(on_activated), NULL);
    g_signal_connect(view, "button-press-event", G_CALLBACK(on_popup), NULL);

    status = gtk_label_new(TR("位置: /"));
    gtk_widget_set_halign(status, GTK_ALIGN_START);
    add_class(status, "qy-files-status");
    gtk_box_pack_start(GTK_BOX(vbox), status, FALSE, FALSE, 2);

    gtk_widget_show_all(win);
    /* argv[1]=="--trash" → 启动即进回收站视图 (调试/自证用) */
    if (g_argc > 1 && !strcmp(g_argv[1], "--trash")) chdir_trash(); else chdir_to(home);
    /* 自动化验证: QYFILES_COPY=<文件名> 启动后自动复制该文件 */
    const char *cp = g_getenv("QYFILES_COPY");
    if (cp && cp[0])
        g_timeout_add(300, (GSourceFunc)auto_copy, g_strdup(cp));
}

int main(int argc, char **argv) {
    g_argc = argc; g_argv = argv;
    GtkApplication *app = gtk_application_new("com.qiyuan.files", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    /* 只把 argv[0] 交给 GtkApplication: 否则 --trash 会被其命令行解析器判为
       "Unknown option" 而直接退出 (自启/调试场景静默失败根因) */
    char *own_argv[2] = { argv[0], NULL };
    int rc = g_application_run(G_APPLICATION(app), 1, own_argv);
    g_object_unref(app);
    return rc;
}
