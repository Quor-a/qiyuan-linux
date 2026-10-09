/* qyedit - 启元文本编辑器 (GTK3, 打开/编辑/保存, 中文界面) */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <gdk/gdkkeysyms.h>
#include <string.h>

static GtkWidget *text_view = NULL;
static GtkWidget *win = NULL;
static GtkWidget *status_label = NULL;
static gchar *current_path = NULL;
static int g_font_size = 0;   /* 正文字号（0 = 主题默认） */

/* ---------- 字号调整: 按钮 + / - 与 QYEDIT_FONT_BIGGER 自动化 ---------- */
static void apply_font(void) {
    if (!text_view || g_font_size <= 0) return;
    gchar *desc = g_strdup_printf("monospace %d", g_font_size);
    PangoFontDescription *fd = pango_font_description_from_string(desc);
    gtk_widget_override_font(text_view, fd);
    pango_font_description_free(fd);
    g_free(desc);
}

static void font_bigger(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (g_font_size <= 0) g_font_size = 14;
    g_font_size++;
    apply_font();
}

static void font_smaller(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (g_font_size <= 0) g_font_size = 14;
    if (g_font_size > 6) g_font_size--;
    apply_font();
}

/* 自动化验证: QYEDIT_FONT_BIGGER=1 启动后自动增大两次 */
static gboolean auto_font_bigger(gpointer p) {
    (void)p;
    font_bigger(NULL, NULL);
    font_bigger(NULL, NULL);
    return G_SOURCE_REMOVE;
}

/* 自动化验证: QYEDIT_LINE=3 启动后把光标移到第 3 行并输出行列 */
static void update_status(GtkTextBuffer *b);   /* 前向声明 */
static gboolean auto_goto_line(gpointer p) {
    int line = atoi((const char *)p);
    GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));
    GtkTextIter it;
    gtk_text_buffer_get_start_iter(b, &it);
    if (line > 1)
        gtk_text_iter_forward_lines(&it, line - 1);
    gtk_text_buffer_place_cursor(b, &it);
    gtk_text_view_scroll_to_iter(GTK_TEXT_VIEW(text_view), &it, 0, FALSE, 0, 0);
    int row = gtk_text_iter_get_line(&it) + 1;
    int col = gtk_text_iter_get_line_offset(&it) + 1;
    g_printerr("QYEDITDBG: cursor line=%d col=%d\n", row, col);
    update_status(b);
    return G_SOURCE_REMOVE;
}

/* ---------- 自动保存：有路径时周期性写回文件 ---------- */
static gboolean auto_save_file(gpointer p) {
    (void)p;
    if (!current_path || !current_path[0])
        return G_SOURCE_CONTINUE;
    GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(b, &start, &end);
    gchar *text = gtk_text_buffer_get_text(b, &start, &end, FALSE);
    if (g_file_set_contents(current_path, text, -1, NULL))
        g_printerr("QYEDITDBG: autosaved %s\n", current_path);
    else
        g_printerr("QYEDITDBG: autosave failed %s\n", current_path);
    g_free(text);
    return G_SOURCE_CONTINUE;
}

/* ---------- 查找：从光标处向后查找关键词 ---------- */
static gboolean do_find_next(const char *needle) {
    if (!needle || !needle[0]) return FALSE;
    GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));
    GtkTextIter cur;
    gtk_text_buffer_get_iter_at_mark(b, &cur, gtk_text_buffer_get_insert(b));
    GtkTextIter ms, me;
    if (!gtk_text_iter_forward_search(&cur, needle, GTK_TEXT_SEARCH_TEXT_ONLY, &ms, &me, NULL)) {
        /* 光标处找不到 → 从文档开头环绕再搜一次 */
        gtk_text_buffer_get_start_iter(b, &cur);
        if (!gtk_text_iter_forward_search(&cur, needle, GTK_TEXT_SEARCH_TEXT_ONLY, &ms, &me, NULL)) {
            g_printerr("QYEDITDBG: find '%s' not found\n", needle);
            return FALSE;
        }
    }
    gtk_text_buffer_place_cursor(b, &ms);
    gtk_text_buffer_select_range(b, &ms, &me);
    gtk_text_view_scroll_to_iter(GTK_TEXT_VIEW(text_view), &ms, 0, FALSE, 0, 0);
    g_printerr("QYEDITDBG: find '%s' line=%d\n", needle, gtk_text_iter_get_line(&ms) + 1);
    return TRUE;
}

/* 查找按钮：弹出输入框 */
static void on_find_clicked(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    GtkWidget *dlg = gtk_dialog_new_with_buttons("查找", GTK_WINDOW(win),
        GTK_DIALOG_MODAL, "_确定", GTK_RESPONSE_OK, "_取消", GTK_RESPONSE_CANCEL, NULL);
    GtkWidget *entry = gtk_entry_new();
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    gtk_box_pack_start(GTK_BOX(box), entry, FALSE, FALSE, 6);
    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *needle = gtk_entry_get_text(GTK_ENTRY(entry));
        do_find_next(needle);
    }
    gtk_widget_destroy(dlg);
}

/* 自动化验证: QYEDIT_FIND=关键词 启动后查找 */
static gboolean auto_find(gpointer p) {
    const char *needle = (const char *)p;
    do_find_next(needle);
    return G_SOURCE_REMOVE;
}

/* ---------- 状态栏: 行 / 列 / 字符数 ---------- */
static void update_status(GtkTextBuffer *b) {
    GtkTextIter it;
    gtk_text_buffer_get_iter_at_mark(b, &it, gtk_text_buffer_get_insert(b));
    int line = gtk_text_iter_get_line(&it) + 1;
    int col  = gtk_text_iter_get_line_offset(&it) + 1;
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(b, &start, &end);
    int chars = gtk_text_iter_get_offset(&end);
    char buf[128];
    g_snprintf(buf, sizeof buf, TR("行 %d · 列 %d · %d 字符"), line, col, chars);
    gtk_label_set_text(GTK_LABEL(status_label), buf);
}

static void on_mark_set(GtkTextBuffer *b, GtkTextIter *loc, GtkTextMark *mark, gpointer ud) {
    if (mark == gtk_text_buffer_get_insert(b))
        update_status(b);
}

static void set_title(void) {
    gchar *t = g_strdup_printf(TR("%s - 启元文本编辑器"), current_path ? g_path_get_basename(current_path) : TR("未命名"));
    gtk_window_set_title(GTK_WINDOW(win), t);
    g_free(t);
}

static void do_new(GtkWidget *w, gpointer ud) {
    GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));
    gtk_text_buffer_set_text(b, "", -1);
    g_free(current_path);
    current_path = NULL;
    set_title();
}

static void do_open(GtkWidget *w, gpointer ud) {
    GtkWidget *dlg = gtk_file_chooser_dialog_new(TR("打开文件"), GTK_WINDOW(win),
        GTK_FILE_CHOOSER_ACTION_OPEN, TR("_取消"), GTK_RESPONSE_CANCEL, TR("_打开"), GTK_RESPONSE_ACCEPT, NULL);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
        gchar *path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
        gchar *text = NULL; gsize len = 0;
        if (g_file_get_contents(path, &text, &len, NULL)) {
            GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));
            gtk_text_buffer_set_text(b, text ? text : "", -1);
            g_free(current_path);
            current_path = path;
            set_title();
        }
        g_free(text);
    }
    gtk_widget_destroy(dlg);
}

static void do_save(GtkWidget *w, gpointer ud) {
    if (!current_path) {
        GtkWidget *dlg = gtk_file_chooser_dialog_new(TR("保存文件"), GTK_WINDOW(win),
            GTK_FILE_CHOOSER_ACTION_SAVE, TR("_取消"), GTK_RESPONSE_CANCEL, TR("_保存"), GTK_RESPONSE_ACCEPT, NULL);
        gtk_file_chooser_set_do_overwrite_confirmation(GTK_FILE_CHOOSER(dlg), TRUE);
        if (gtk_dialog_run(GTK_DIALOG(dlg)) != GTK_RESPONSE_ACCEPT) { gtk_widget_destroy(dlg); return; }
        current_path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
        gtk_widget_destroy(dlg);
    }
    GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(b, &start, &end);
    gchar *text = gtk_text_buffer_get_text(b, &start, &end, FALSE);
    if (g_file_set_contents(current_path, text, -1, NULL)) set_title();
    g_free(text);
}

static void do_save_as(GtkWidget *w, gpointer ud) {
    gchar *old = current_path;
    current_path = NULL;
    do_save(w, ud);
    if (!current_path) current_path = old; /* 取消则恢复 */
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    qy_load_theme();

    win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_default_size(GTK_WINDOW(win), 720, 520);
    if (argc > 1) { current_path = g_strdup(argv[1]); }

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    GtkWidget *mb = gtk_menu_bar_new();
    GtkWidget *file_item = gtk_menu_item_new_with_label(TR("文件"));
    GtkWidget *file_menu = gtk_menu_new();
    GtkWidget *mi_open = gtk_menu_item_new_with_label(TR("打开..."));
    GtkWidget *mi_save = gtk_menu_item_new_with_label(TR("保存"));
    GtkWidget *mi_sas  = gtk_menu_item_new_with_label(TR("另存为..."));
    GtkWidget *mi_quit = gtk_menu_item_new_with_label(TR("退出"));
    g_signal_connect(mi_open, "activate", G_CALLBACK(do_open), NULL);
    g_signal_connect(mi_save, "activate", G_CALLBACK(do_save), NULL);
    g_signal_connect(mi_sas,  "activate", G_CALLBACK(do_save_as), NULL);
    g_signal_connect(mi_quit, "activate", G_CALLBACK(gtk_main_quit), NULL);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), mi_open);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), mi_save);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), mi_sas);
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), gtk_separator_menu_item_new());
    gtk_menu_shell_append(GTK_MENU_SHELL(file_menu), mi_quit);
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(file_item), file_menu);
    gtk_menu_shell_append(GTK_MENU_SHELL(mb), file_item);
    gtk_box_pack_start(GTK_BOX(vbox), mb, FALSE, FALSE, 0);

    /* 工具栏：新建 / 打开 / 保存 */
    GtkWidget *tb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *b_new  = gtk_button_new_with_label(TR("新建"));
    GtkWidget *b_open = gtk_button_new_with_label(TR("打开"));
    GtkWidget *b_save = gtk_button_new_with_label(TR("保存"));
    GtkWidget *b_fbig = gtk_button_new_with_label(TR("字号 +"));
    GtkWidget *b_fsmall = gtk_button_new_with_label(TR("字号 -"));
    qy_add_class(b_new, "qy-editor-btn");
    qy_add_class(b_open, "qy-editor-btn");
    qy_add_class(b_save, "qy-editor-btn");
    qy_add_class(b_fbig, "qy-editor-btn");
    qy_add_class(b_fsmall, "qy-editor-btn");
    g_signal_connect(b_new,  "clicked", G_CALLBACK(do_new), NULL);
    g_signal_connect(b_open, "clicked", G_CALLBACK(do_open), NULL);
    g_signal_connect(b_save, "clicked", G_CALLBACK(do_save), NULL);
    g_signal_connect(b_fbig, "clicked", G_CALLBACK(font_bigger), NULL);
    g_signal_connect(b_fsmall, "clicked", G_CALLBACK(font_smaller), NULL);
    gtk_box_pack_start(GTK_BOX(tb), b_new, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tb), b_open, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tb), b_save, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tb), b_fbig, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(tb), b_fsmall, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), tb, FALSE, FALSE, 3);

    text_view = gtk_text_view_new();
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(text_view), GTK_WRAP_WORD_CHAR);
    /* 支持环境变量 QYEDIT_FONT_SIZE 调整正文字号（自动化验证用） */
    {
        const char *fs = getenv("QYEDIT_FONT_SIZE");
        int sz = fs ? atoi(fs) : 0;
        if (sz > 0) {
            gchar *desc = g_strdup_printf("monospace %d", sz);
            PangoFontDescription *fd = pango_font_description_from_string(desc);
            gtk_widget_override_font(text_view, fd);
            pango_font_description_free(fd);
            g_free(desc);
        }
    }
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(scroll), text_view);
    gtk_box_pack_start(GTK_BOX(vbox), scroll, TRUE, TRUE, 0);

    status_label = gtk_label_new("");
    qy_add_class(status_label, "qy-editor-status");
    gtk_widget_set_halign(status_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 2);

    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));
    g_signal_connect(buffer, "changed", G_CALLBACK(update_status), NULL);
    g_signal_connect(buffer, "mark-set", G_CALLBACK(on_mark_set), NULL);

    if (current_path) {
        gchar *text = NULL;
        if (g_file_get_contents(current_path, &text, NULL, NULL)) {
            gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view)), text ? text : "", -1);
        }
        g_free(text);
    }
    set_title();
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);
    /* ---------- 文本编辑器标准快捷键 ---------- */
    GtkAccelGroup *accel = gtk_accel_group_new();
    gtk_window_add_accel_group(GTK_WINDOW(win), accel);
    gtk_widget_add_accelerator(b_save, "clicked", accel, GDK_KEY_s, GDK_CONTROL_MASK, GTK_ACCEL_VISIBLE); /* Ctrl+S 保存 */
    gtk_widget_add_accelerator(b_open, "clicked", accel, GDK_KEY_o, GDK_CONTROL_MASK, GTK_ACCEL_VISIBLE); /* Ctrl+O 打开 */
    gtk_widget_add_accelerator(b_new, "clicked", accel, GDK_KEY_n, GDK_CONTROL_MASK, GTK_ACCEL_VISIBLE);  /* Ctrl+N 新建 */
    GtkWidget *b_find = gtk_button_new();
    g_signal_connect(b_find, "clicked", G_CALLBACK(on_find_clicked), NULL);
    gtk_widget_add_accelerator(b_find, "clicked", accel, GDK_KEY_f, GDK_CONTROL_MASK, GTK_ACCEL_VISIBLE); /* Ctrl+F 查找 */
    g_printerr("QYEDITDBG: accel 4 keys\n");
    gtk_widget_show_all(win);

    /* 自动化验证: QYEDIT_FONT_BIGGER=1 启动后自动增大字号两次 */
    if (getenv("QYEDIT_FONT_BIGGER")) {
        const char *fs = getenv("QYEDIT_FONT_SIZE");
        g_font_size = fs && atoi(fs) > 0 ? atoi(fs) : 14;
        g_timeout_add(500, auto_font_bigger, NULL);
    }
    /* 自动化验证: QYEDIT_LINE=3 启动后定位光标到第 3 行 */
    const char *line_env = getenv("QYEDIT_LINE");
    if (line_env && atoi(line_env) > 0)
        g_timeout_add(700, auto_goto_line, g_strdup(line_env));
    /* 自动化验证: QYEDIT_TEXT=新内容 启动后写入 buffer（配合自动保存测试） */
    const char *text_env = getenv("QYEDIT_TEXT");
    if (text_env) {
        GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));
        gtk_text_buffer_set_text(b, text_env, -1);
    }
    /* 自动保存：默认 30 秒；QYEDIT_AUTOSAVE=1 时 2 秒（自动化验证） */
    if (getenv("QYEDIT_AUTOSAVE"))
        g_timeout_add(2000, auto_save_file, NULL);
    else
        g_timeout_add_seconds(30, auto_save_file, NULL);
    /* 自动化验证: QYEDIT_FIND=关键词 启动后查找 */
    const char *find_env = getenv("QYEDIT_FIND");
    if (find_env && find_env[0])
        g_timeout_add(1000, auto_find, g_strdup(find_env));
    gtk_main();
    return 0;
}
