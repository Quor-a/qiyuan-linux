/* qyfiles - 启元文件管理器 (GTK3) — v4: 目录搜索过滤 */
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
static char g_search[128] = "";  /* 当前搜索关键字（空=全部） */
static GSList *cut_sources = NULL; /* 剪切源列表（多选） */
static void chdir_to(const char *path);
static void chdir_trash(void);
static GdkPixbuf *load_icon_for(const char *name, gboolean isdir);
static GdkPixbuf *make_dir_icon(void);
static GdkPixbuf *make_file_icon(double r, double g, double b);

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
static GtkWidget *b_nf = NULL;   /* 新建文件按钮 */
static GtkWidget *b_open = NULL;
static GtkWidget *b_cp = NULL, *b_prop = NULL;
static GtkWidget *b_res = NULL, *b_pur = NULL, *b_emp = NULL;

static void set_mode_buttons(void) {
    if (!b_mk) return;
    gboolean trash = in_trash;
    gtk_widget_set_visible(b_mk, !trash);
    gtk_widget_set_visible(b_nf, !trash);
    gtk_widget_set_visible(b_del, !trash);
    gtk_widget_set_visible(b_ren, !trash);
    gtk_widget_set_visible(b_open, !trash);
    gtk_widget_set_visible(b_cp, !trash);
    gtk_widget_set_visible(b_prop, !trash);
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

/* 多选：收集所有选中文件名到 GSList（调用者 g_slist_free_full(names, g_free)） */
static GSList *selected_names(void) {
    GSList *list = NULL;
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
    GtkTreeModel *m = gtk_tree_view_get_model(GTK_TREE_VIEW(view));
    GList *rows = gtk_tree_selection_get_selected_rows(sel, &m);
    for (GList *r = rows; r; r = r->next) {
        GtkTreeIter it;
        if (gtk_tree_model_get_iter(m, &it, r->data)) {
            gchar *name = NULL;
            gtk_tree_model_get(m, &it, 1, &name, -1);
            if (name) list = g_slist_prepend(list, name);
        }
    }
    g_list_free_full(rows, (GDestroyNotify)gtk_tree_path_free);
    return g_slist_reverse(list);
}

static void do_delete(void) {
    GSList *names = selected_names();
    if (!names) return;
    if (in_trash) { g_slist_free_full(names, g_free); return; }
    for (GSList *l = names; l; l = l->next) {
        const char *name = (const char *)l->data;
        gchar *full = g_build_filename(cwd, name, NULL);
        GError *err = NULL;
        if (!trash_file(full, &err)) {
            gchar *msg = g_strdup_printf(TR("删除失败: %s"), err ? err->message : "?");
            gtk_label_set_text(GTK_LABEL(status), msg);
            g_free(msg); g_clear_error(&err);
        }
        g_free(full);
    }
    g_slist_free_full(names, g_free);
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

/* 新建文本文件（默认 新建文件.txt，可改名） */
static void do_newfile(void) {
    GtkWidget *dlg = gtk_dialog_new_with_buttons("新建文件", GTK_WINDOW(gtk_widget_get_toplevel(view)),
        GTK_DIALOG_MODAL, "_取消", GTK_RESPONSE_CANCEL, "_确定", GTK_RESPONSE_OK, NULL);
    GtkWidget *entry = gtk_entry_new();
    gtk_entry_set_text(GTK_ENTRY(entry), "新建文件.txt");
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    gtk_box_pack_start(GTK_BOX(box), entry, FALSE, FALSE, 6);
    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *nn = gtk_entry_get_text(GTK_ENTRY(entry));
        if (nn[0]) {
            gchar *full = g_build_filename(cwd, nn, NULL);
            if (g_file_set_contents(full, "", 0, NULL) == TRUE)
                gtk_label_set_text(GTK_LABEL(status), "文件已创建");
            else
                gtk_label_set_text(GTK_LABEL(status), "创建失败");
            g_free(full);
        }
    }
    gtk_widget_destroy(dlg);
    chdir_to(cwd);
}

/* 自动化: QYFILES_NEWFILE=1 启动后直接创建未命名.txt（跳过对话框） */
static gboolean auto_newfile(gpointer p) {
    (void)p;
    gchar *full = g_build_filename(cwd, "未命名.txt", NULL);
    if (g_file_set_contents(full, "", 0, NULL))
        g_printerr("QYFILESDBG: newfile created %s\n", full);
    else
        g_printerr("QYFILESDBG: newfile failed\n");
    g_free(full);
    chdir_to(cwd);
    return G_SOURCE_REMOVE;
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
    GSList *names = selected_names();
    if (!names) { gtk_label_set_text(GTK_LABEL(status), TR("请先选择一个文件")); return; }
    for (GSList *l = names; l; l = l->next)
        do_copy_named((const char *)l->data);
    g_slist_free_full(names, g_free);
    chdir_to(cwd);
}

/* ---------- 剪切 / 粘贴（移动文件） ---------- */
static void do_cut(GtkButton *b, gpointer ud) {
    (void)b; (void)ud;
    GSList *names = selected_names();
    if (!names) { gtk_label_set_text(GTK_LABEL(status), TR("请先选择一个文件")); return; }
    g_slist_free_full(cut_sources, g_free);
    cut_sources = NULL;
    int n = 0;
    for (GSList *l = names; l; l = l->next) {
        cut_sources = g_slist_prepend(cut_sources, g_build_filename(cwd, (const char *)l->data, NULL));
        n++;
    }
    cut_sources = g_slist_reverse(cut_sources);
    g_printerr("QYFILESDBG: cut %d items\n", n);
    gchar *msg = g_strdup_printf(TR("已剪切 %d 项"), n);
    gtk_label_set_text(GTK_LABEL(status), msg);
    g_free(msg);
    g_slist_free_full(names, g_free);
}

static void do_paste(GtkButton *b, gpointer ud) {
    (void)b; (void)ud;
    if (!cut_sources) {
        gtk_label_set_text(GTK_LABEL(status), TR("没有可粘贴的剪切项"));
        return;
    }
    if (in_trash) {
        gtk_label_set_text(GTK_LABEL(status), TR("回收站中不能粘贴"));
        return;
    }
    int ok = 0, fail = 0;
    for (GSList *l = cut_sources; l; l = l->next) {
        const gchar *src = (const gchar *)l->data;
        gchar *base = g_path_get_basename(src);
        gchar *dst = g_build_filename(cwd, base, NULL);
        g_free(base);
        gchar *cmd = g_strdup_printf("mv -b -- %s %s", g_shell_quote(src), g_shell_quote(dst));
        int rc = system(cmd);
        g_free(cmd);
        if (rc == 0) ok++; else fail++;
        g_free(dst);
    }
    if (fail == 0) {
        gtk_label_set_text(GTK_LABEL(status), TR("已粘贴"));
        g_slist_free_full(cut_sources, g_free);
        cut_sources = NULL;
        chdir_to(cwd);
    } else {
        gchar *msg = g_strdup_printf(TR("粘贴失败 %d 项"), fail);
        gtk_label_set_text(GTK_LABEL(status), msg);
        g_free(msg);
    }
}

/* ---------- 属性对话框: 名称 / 位置 / 大小 / 修改时间 / 权限 ---------- */
static void do_prop_name(const char *name) {
    if (!name || !name[0]) return;
    gchar *full = g_build_filename(cwd, name, NULL);
    struct stat st;
    if (stat(full, &st) != 0) { g_free(full); return; }
    char size_buf[64], mtime_buf[64], perm_buf[16];
    g_snprintf(size_buf, sizeof size_buf, "%lld %s",
               (long long)st.st_size, TR("字节"));
    struct tm *tm = localtime(&st.st_mtime);
    if (tm) strftime(mtime_buf, sizeof mtime_buf, "%Y-%m-%d %H:%M:%S", tm);
    else g_strlcpy(mtime_buf, "-", sizeof mtime_buf);
    g_snprintf(perm_buf, sizeof perm_buf, "%o", st.st_mode & 07777);
    GtkWidget *dlg = gtk_dialog_new_with_buttons(TR("属性"),
        GTK_WINDOW(gtk_widget_get_toplevel(view)), GTK_DIALOG_MODAL,
        "_确定", GTK_RESPONSE_OK, NULL);
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 6);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 12);
    const char *rows[][2] = {
        { TR("名称"), name },
        { TR("位置"), cwd },
        { TR("文件大小"), size_buf },
        { TR("修改时间"), mtime_buf },
        { TR("权限"), perm_buf },
    };
    for (int i = 0; i < 5; i++) {
        GtkWidget *k = gtk_label_new(rows[i][0]);
        gtk_widget_set_halign(k, GTK_ALIGN_START);
        gtk_grid_attach(GTK_GRID(grid), k, 0, i, 1, 1);
        GtkWidget *v = gtk_label_new(rows[i][1]);
        gtk_widget_set_halign(v, GTK_ALIGN_START);
        gtk_grid_attach(GTK_GRID(grid), v, 1, i, 1, 1);
    }
    gtk_box_pack_start(GTK_BOX(box), grid, FALSE, FALSE, 10);
    gtk_widget_show_all(dlg);
    gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
    g_free(full);
}

static gboolean auto_prop(gpointer p) {
    do_prop_name((const char *)p);
    g_free(p);
    return G_SOURCE_REMOVE;
}

static void do_prop(GtkButton *b, gpointer ud) {
    (void)b; (void)ud;
    gchar *name;
    selected_name(&name);
    if (!name) { gtk_label_set_text(GTK_LABEL(status), TR("请先选择一个文件")); return; }
    do_prop_name(name);
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

/* ---------- 右键菜单（真实 GtkMenu） ---------- */
static void do_open_sel(GtkButton *b, gpointer ud);

static void add_menuitem(GtkWidget *menu, const char *label, GCallback cb) {
    GtkWidget *mi = gtk_menu_item_new_with_label(label);
    g_signal_connect(mi, "activate", cb, NULL);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
}

/* 为当前选中行弹出上下文菜单（trigger 可为 NULL——自动化场景） */
static void show_context_menu(GdkEvent *trigger) {
    GtkWidget *menu = gtk_menu_new();
    if (in_trash) {
        add_menuitem(menu, TR("还原"), G_CALLBACK(do_restore));
        add_menuitem(menu, TR("彻底删除"), G_CALLBACK(do_purge));
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
        add_menuitem(menu, TR("清空回收站"), G_CALLBACK(do_empty_trash));
    } else {
        add_menuitem(menu, TR("打开"), G_CALLBACK(do_open_sel));
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
        add_menuitem(menu, TR("剪切"), G_CALLBACK(do_cut));
        add_menuitem(menu, TR("复制"), G_CALLBACK(do_copy));
        add_menuitem(menu, TR("粘贴"), G_CALLBACK(do_paste));
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
        add_menuitem(menu, TR("重命名"), G_CALLBACK(do_rename));
        add_menuitem(menu, TR("删除"), G_CALLBACK(do_delete));
        add_menuitem(menu, TR("属性"), G_CALLBACK(do_prop));
    }
    gtk_widget_show_all(menu);
    g_printerr("QYFILESDBG: context menu ready (%d items)\n", in_trash ? 4 : 7);
    /* Wayland 下必须将菜单 attach 到窗口，否则临时窗口无法定位/显示 */
    gtk_menu_attach_to_widget(GTK_MENU(menu), view, NULL);
    if (trigger)
        gtk_menu_popup_at_widget(GTK_MENU(menu), view,
            GDK_GRAVITY_SOUTH_WEST, GDK_GRAVITY_NORTH_WEST, trigger);
    else
        gtk_menu_popup_at_widget(GTK_MENU(menu), view,
            GDK_GRAVITY_SOUTH_WEST, GDK_GRAVITY_NORTH_WEST, NULL);
}

static gboolean on_popup(GtkWidget *w, GdkEventButton *ev, gpointer ud) {
    (void)w; (void)ud;
    if (ev->type == GDK_BUTTON_PRESS && ev->button == 3) {
        GtkTreePath *path = NULL;
        GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
        if (!gtk_tree_view_get_path_at_pos(GTK_TREE_VIEW(view),
                (gint)ev->x, (gint)ev->y, &path, NULL, NULL, NULL) || !path)
            return TRUE;
        gtk_tree_selection_unselect_all(sel);
        gtk_tree_selection_select_path(sel, path);
        gtk_tree_path_free(path);
        show_context_menu((GdkEvent *)ev);
        return TRUE;
    }
    return FALSE;
}

/* 自动化：QYFILES_MULTI=file1,file2 选中多行并触发剪切（自测多选） */
static gboolean auto_multi(gpointer p) {
    const char *csv = (const char *)p;
    GtkTreeModel *m = gtk_tree_view_get_model(GTK_TREE_VIEW(view));
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
    char *copy = g_strdup(csv);
    char **names = g_strsplit(copy, ",", 0);
    for (int i = 0; names && names[i]; i++) {
        GtkTreeIter it;
        if (gtk_tree_model_get_iter_first(m, &it)) {
            do {
                gchar *name = NULL;
                gtk_tree_model_get(m, &it, 1, &name, -1);
                if (name && strcmp(name, names[i]) == 0)
                    gtk_tree_selection_select_iter(sel, &it);
                g_free(name);
            } while (gtk_tree_model_iter_next(m, &it));
        }
    }
    g_strfreev(names);
    g_free(copy);
    g_free(p);
    do_cut(NULL, NULL);
    return G_SOURCE_REMOVE;
}

/* 自动化：QYFILES_RIGHTCLICK=文件名 选中该行并弹出右键菜单（自测截图用） */
static gboolean auto_rightclick(gpointer p) {
    const char *target = (const char *)p;
    GtkTreeModel *m = gtk_tree_view_get_model(GTK_TREE_VIEW(view));
    GtkTreeIter it;
    if (gtk_tree_model_get_iter_first(m, &it)) {
        do {
            gchar *name = NULL;
            gtk_tree_model_get(m, &it, 1, &name, -1);
            if (name && strcmp(name, target) == 0) {
                GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(view));
                gtk_tree_selection_unselect_all(sel);
                gtk_tree_selection_select_iter(sel, &it);
                g_free(name);
                g_free(p);
                /* 伪造右键事件，使菜单有触发事件（Wayland 下必须） */
                GdkEventButton evt;
                memset(&evt, 0, sizeof evt);
                evt.type = GDK_BUTTON_PRESS;
                evt.button = 3;
                evt.x = 10;
                evt.y = 10;
                evt.time = GDK_CURRENT_TIME;
                evt.window = gtk_widget_get_window(view);
                if (evt.window) g_object_ref(evt.window);
                show_context_menu((GdkEvent *)&evt);
                if (evt.window) g_object_unref(evt.window);
                return G_SOURCE_REMOVE;
            }
            g_free(name);
        } while (gtk_tree_model_iter_next(m, &it));
    }
    g_free(p);
    return G_SOURCE_REMOVE;
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
        /* 搜索过滤: 名称包含关键字才显示 */
        if (g_search[0] && !strstr(name, g_search))
            continue;
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
        GdkPixbuf *pb = load_icon_for(name, isdir);
        gtk_list_store_append(store, &it);
        gtk_list_store_set(store, &it, 0, isdir ? TR("[目录]") : TR("[文件]"), 1, name, 2, sizestr, 3, pb, -1);
        if (pb) g_object_unref(pb);
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
            GdkPixbuf *pb = make_file_icon(0.72, 0.72, 0.78);
            gtk_list_store_append(store, &it);
            if (read_trashinfo(ti, orig, sizeof orig)) {
                gtk_list_store_set(store, &it, 0, orig, 1, name, 2, TR("—"), 3, pb, -1);
            } else {
                gtk_list_store_set(store, &it, 0, TR("(无元数据)"), 1, name, 2, TR("—"), 3, pb, -1);
            }
            if (pb) g_object_unref(pb);
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

/* ---------- 搜索过滤 ---------- */
static void on_search_changed(GtkSearchEntry *se, gpointer ud) {
    (void)ud;
    const char *text = gtk_entry_get_text(GTK_ENTRY(se));
    g_strlcpy(g_search, text ? text : "", sizeof g_search);
    if (in_trash) chdir_trash(); else chdir_to(cwd);
}

/* 自动化验证: QYFILES_SEARCH=/etc:passwd → 进入 /etc 且只显示含 passwd 的项 */
static gboolean auto_search(gpointer p) {
    if (p) {
        gchar *dir = g_strdup((const char *)p);
        chdir_to(dir);
        g_free(dir);
    } else {
        chdir_to(cwd);
    }
    return G_SOURCE_REMOVE;
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

/* ---------- 图标视图 ---------- */
static GtkWidget *icon_view = NULL;
static GtkWidget *stack = NULL;

/* 内置绘制图标（不依赖图标主题，自包含）：直接操作 pixbuf 像素 */
static void fill_rect(guint8 *p, int rs, int nc, int x0, int y0, int x1, int y1,
                       guint8 r, guint8 g, guint8 b, guint8 a) {
    for (int y = y0; y < y1; y++)
        for (int x = x0; x < x1; x++) {
            guint8 *px = p + y * rs + x * nc;
            px[0] = r; px[1] = g; px[2] = b; px[3] = a;
        }
}

/* 文件夹图标 */
static GdkPixbuf *make_dir_icon(void) {
    GdkPixbuf *pb = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, 48, 48);
    gdk_pixbuf_fill(pb, 0x00000000);
    guint8 *p = gdk_pixbuf_get_pixels(pb);
    int rs = gdk_pixbuf_get_rowstride(pb);
    int nc = gdk_pixbuf_get_n_channels(pb);
    fill_rect(p, rs, nc, 4, 16, 44, 42, 242, 199, 46, 255);
    fill_rect(p, rs, nc, 2, 8, 17, 18, 247, 217, 82, 255);
    return pb;
}

/* 文件图标：按类型着色 */
static GdkPixbuf *make_file_icon(double r, double g, double b) {
    GdkPixbuf *pb = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, 48, 48);
    gdk_pixbuf_fill(pb, 0x00000000);
    guint8 *p = gdk_pixbuf_get_pixels(pb);
    int rs = gdk_pixbuf_get_rowstride(pb);
    int nc = gdk_pixbuf_get_n_channels(pb);
    int rr = (int)(r * 255), gg = (int)(g * 255), bb = (int)(b * 255);
    fill_rect(p, rs, nc, 12, 4, 36, 44, rr, gg, bb, 255);
    fill_rect(p, rs, nc, 16, 14, 32, 17, rr * 7 / 10, gg * 7 / 10, bb * 7 / 10, 255);
    fill_rect(p, rs, nc, 16, 22, 32, 25, rr * 7 / 10, gg * 7 / 10, bb * 7 / 10, 255);
    fill_rect(p, rs, nc, 16, 30, 26, 33, rr * 7 / 10, gg * 7 / 10, bb * 7 / 10, 255);
    return pb;
}

/* 按文件类型加载图标（目录=文件夹；扩展名映射颜色） */
static GdkPixbuf *load_icon_for(const char *name, gboolean isdir) {
    if (isdir) return make_dir_icon();
    const char *dot = strrchr(name, '.');
    if (dot) {
        if (!g_ascii_strcasecmp(dot, ".png") || !g_ascii_strcasecmp(dot, ".jpg")
            || !g_ascii_strcasecmp(dot, ".jpeg") || !g_ascii_strcasecmp(dot, ".webp")
            || !g_ascii_strcasecmp(dot, ".gif") || !g_ascii_strcasecmp(dot, ".bmp"))
            return make_file_icon(0.45, 0.75, 0.45);
        if (!g_ascii_strcasecmp(dot, ".mp3") || !g_ascii_strcasecmp(dot, ".wav")
            || !g_ascii_strcasecmp(dot, ".flac") || !g_ascii_strcasecmp(dot, ".ogg"))
            return make_file_icon(0.45, 0.60, 0.85);
        if (!g_ascii_strcasecmp(dot, ".mp4") || !g_ascii_strcasecmp(dot, ".mkv")
            || !g_ascii_strcasecmp(dot, ".avi") || !g_ascii_strcasecmp(dot, ".webm"))
            return make_file_icon(0.75, 0.50, 0.80);
        if (!g_ascii_strcasecmp(dot, ".c") || !g_ascii_strcasecmp(dot, ".h")
            || !g_ascii_strcasecmp(dot, ".py") || !g_ascii_strcasecmp(dot, ".sh")
            || !g_ascii_strcasecmp(dot, ".js"))
            return make_file_icon(0.55, 0.55, 0.68);
        if (!g_ascii_strcasecmp(dot, ".pdf"))
            return make_file_icon(0.90, 0.45, 0.45);
    }
    return make_file_icon(0.90, 0.90, 0.95);
}

/* 图标视图双击/回车打开 */
static void on_icon_activated(GtkIconView *iv, GtkTreePath *path, gpointer ud) {
    (void)iv; (void)ud;
    GtkTreeModel *m = gtk_icon_view_get_model(iv);
    GtkTreeIter it;
    gchar *name = NULL;
    if (gtk_tree_model_get_iter(m, &it, path))
        gtk_tree_model_get(m, &it, 1, &name, -1);
    if (!name) return;
    open_path(name);
    g_free(name);
}

/* 切换列表/图标视图 */
static void on_toggle_view(GtkButton *b, gpointer ud) {
    (void)ud;
    const char *page = stack ? gtk_stack_get_visible_child_name(GTK_STACK(stack)) : "list";
    if (g_strcmp0(page, "list") == 0 || !page) {
        gtk_stack_set_visible_child_name(GTK_STACK(stack), "icon");
        if (b) gtk_button_set_label(b, TR("列表视图"));
        g_printerr("QYFILESDBG: view=icon\n");
    } else {
        gtk_stack_set_visible_child_name(GTK_STACK(stack), "list");
        if (b) gtk_button_set_label(b, TR("图标视图"));
        g_printerr("QYFILESDBG: view=list\n");
    }
}

/* 自动化: QYFILES_VIEW=icon 启动后切换图标视图 */
static gboolean auto_view_icon(gpointer p) {
    on_toggle_view(NULL, p);
    return G_SOURCE_REMOVE;
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
    b_nf = gtk_button_new_with_label(TR("新建文件"));
    add_class(b_nf, "qy-btn");
    g_signal_connect(b_nf, "clicked", G_CALLBACK(do_newfile), NULL);
    b_del = gtk_button_new_with_label(TR("删除"));
    add_class(b_del, "qy-btn");
    g_signal_connect(b_del, "clicked", G_CALLBACK(do_delete), NULL);
    b_ren = gtk_button_new_with_label(TR("重命名"));
    add_class(b_ren, "qy-btn");
    g_signal_connect(b_ren, "clicked", G_CALLBACK(do_rename), NULL);
    b_cp = gtk_button_new_with_label(TR("复制"));
    add_class(b_cp, "qy-btn");
    g_signal_connect(b_cp, "clicked", G_CALLBACK(do_copy), NULL);
    b_prop = gtk_button_new_with_label(TR("属性"));
    add_class(b_prop, "qy-btn");
    g_signal_connect(b_prop, "clicked", G_CALLBACK(do_prop), NULL);
    b_open = gtk_button_new_with_label(TR("打开"));
    add_class(b_open, "qy-btn");
    g_signal_connect(b_open, "clicked", G_CALLBACK(do_open_sel), NULL);
    GtkWidget *b_view = gtk_button_new_with_label(TR("图标视图"));
    add_class(b_view, "qy-btn");
    g_signal_connect(b_view, "clicked", G_CALLBACK(on_toggle_view), NULL);
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
    gtk_box_pack_start(GTK_BOX(hbox), b_nf, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_del, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_ren, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_cp, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_prop, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_view, FALSE, FALSE, 0);
    GtkWidget *search_entry = gtk_search_entry_new();
    gtk_widget_set_size_request(search_entry, 220, -1);
    gtk_entry_set_placeholder_text(GTK_ENTRY(search_entry), TR("搜索当前目录"));
    g_signal_connect(search_entry, "search-changed", G_CALLBACK(on_search_changed), NULL);
    gtk_box_pack_end(GTK_BOX(hbox), search_entry, FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(hbox), b_open, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_res, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_pur, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hbox), b_emp, FALSE, FALSE, 0);

    GtkListStore *store = gtk_list_store_new(4, G_TYPE_STRING, G_TYPE_STRING,
                                             G_TYPE_STRING, GDK_TYPE_PIXBUF);
    view = gtk_tree_view_new_with_model(GTK_TREE_MODEL(store));
    GtkCellRenderer *r1 = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(view), -1, TR("类型/原位置"), r1, "text", 0, NULL);
    GtkCellRenderer *r2 = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(view), -1, TR("名称"), r2, "text", 1, NULL);
    GtkCellRenderer *r3 = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(view), -1, TR("大小"), r3, "text", 2, NULL);
    /* 列头点击排序 */
    GtkTreeViewColumn *c0 = gtk_tree_view_get_column(GTK_TREE_VIEW(view), 0);
    GtkTreeViewColumn *c1 = gtk_tree_view_get_column(GTK_TREE_VIEW(view), 1);
    GtkTreeViewColumn *c2 = gtk_tree_view_get_column(GTK_TREE_VIEW(view), 2);
    gtk_tree_view_column_set_clickable(c0, TRUE);
    gtk_tree_view_column_set_sort_indicator(c0, TRUE);
    gtk_tree_view_column_set_sort_column_id(c0, 0);
    gtk_tree_view_column_set_clickable(c1, TRUE);
    gtk_tree_view_column_set_sort_indicator(c1, TRUE);
    gtk_tree_view_column_set_sort_column_id(c1, 1);
    gtk_tree_view_column_set_clickable(c2, TRUE);
    gtk_tree_view_column_set_sort_indicator(c2, TRUE);
    gtk_tree_view_column_set_sort_column_id(c2, 2);
    /* 默认按名称排序 */
    gtk_tree_sortable_set_sort_column_id(GTK_TREE_SORTABLE(store), 1, GTK_SORT_ASCENDING);
    /* 多选 */
    gtk_tree_selection_set_mode(gtk_tree_view_get_selection(GTK_TREE_VIEW(view)), GTK_SELECTION_MULTIPLE);
    gint sort_col = -1;
    GtkSortType sort_order = GTK_SORT_ASCENDING;
    gtk_tree_sortable_get_sort_column_id(GTK_TREE_SORTABLE(store), &sort_col, &sort_order);
    g_printerr("QYFILESDBG: sort col=%d order=%d multi=1\n", sort_col, (int)sort_order);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(scroll), view);
    g_signal_connect(view, "row-activated", G_CALLBACK(on_activated), NULL);
    g_signal_connect(view, "button-press-event", G_CALLBACK(on_popup), NULL);
    /* 图标视图（与列表共享同一模型，第 3 列 pixbuf） */
    icon_view = gtk_icon_view_new_with_model(GTK_TREE_MODEL(store));
    gtk_icon_view_set_text_column(GTK_ICON_VIEW(icon_view), 1);
    gtk_icon_view_set_pixbuf_column(GTK_ICON_VIEW(icon_view), 3);
    gtk_icon_view_set_item_width(GTK_ICON_VIEW(icon_view), 100);
    gtk_icon_view_set_selection_mode(GTK_ICON_VIEW(icon_view), GTK_SELECTION_MULTIPLE);
    g_signal_connect(icon_view, "item-activated", G_CALLBACK(on_icon_activated), NULL);
    GtkWidget *scroll_icon = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(scroll_icon), icon_view);
    stack = gtk_stack_new();
    gtk_stack_add_named(GTK_STACK(stack), scroll, "list");
    gtk_stack_add_named(GTK_STACK(stack), scroll_icon, "icon");
    gtk_box_pack_start(GTK_BOX(vbox), stack, TRUE, TRUE, 0);

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
    /* 自动化验证: QYFILES_PROP=<文件名> 启动后自动打开属性对话框 */
    const char *pp = g_getenv("QYFILES_PROP");
    if (pp && pp[0])
        g_timeout_add(300, (GSourceFunc)auto_prop, g_strdup(pp));
    /* 自动化验证: QYFILES_RIGHTCLICK=<文件名> 启动后弹出右键菜单 */
    const char *rclk = g_getenv("QYFILES_RIGHTCLICK");
    if (rclk && rclk[0])
        g_timeout_add(800, (GSourceFunc)auto_rightclick, g_strdup(rclk));
    /* 自动化验证: QYFILES_MULTI=file1,file2 选中多行并触发剪切 */
    const char *multi = g_getenv("QYFILES_MULTI");
    if (multi && multi[0])
        g_timeout_add(600, (GSourceFunc)auto_multi, g_strdup(multi));
    /* 自动化验证: QYFILES_VIEW=icon 启动后切换图标视图 */
    const char *qv = g_getenv("QYFILES_VIEW");
    if (qv && g_strcmp0(qv, "icon") == 0)
        g_timeout_add(800, auto_view_icon, NULL);
    /* 自动化验证: QYFILES_SEARCH=/etc:passwd 启动后进入 /etc 并过滤 */
    const char *sf = g_getenv("QYFILES_SEARCH");
    if (sf && sf[0]) {
        char *colon = strchr(sf, ':');
        if (colon) {
            g_strlcpy(g_search, colon + 1, sizeof g_search);
            gchar *dir = g_strndup(sf, (gsize)(colon - sf));
            g_timeout_add(300, (GSourceFunc)auto_search, g_strdup(dir));
            g_free(dir);
        } else {
            g_strlcpy(g_search, sf, sizeof g_search);
            g_timeout_add(300, (GSourceFunc)auto_search, NULL);
        }
    }
    /* 自动化验证: QYFILES_NEWFILE=1 启动后新建未命名.txt */
    if (g_getenv("QYFILES_NEWFILE"))
        g_timeout_add(900, (GSourceFunc)auto_newfile, NULL);
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
