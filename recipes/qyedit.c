/* qyedit - 启元文本编辑器 (GTK3, 打开/编辑/保存, 中文界面) */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <string.h>

static GtkWidget *text_view = NULL;
static GtkWidget *win = NULL;
static GtkWidget *status_label = NULL;
static gchar *current_path = NULL;

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

    text_view = gtk_text_view_new();
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(text_view), GTK_WRAP_WORD_CHAR);
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
    gtk_widget_show_all(win);
    gtk_main();
    return 0;
}
