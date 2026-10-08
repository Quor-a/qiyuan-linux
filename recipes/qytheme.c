/* qytheme.c — 启元统一主题助手实现
 * 加载 /usr/share/themes/qiyuan/gtk-3.0/gtk.css（深色桌面主题），
 * 并读取 /etc/qytheme.conf 的 accent= 加载强调色覆盖 CSS。
 * 提供便捷 CSS 类添加函数。
 */
#include "qytheme.h"
#include <stdio.h>
#include <string.h>
#include <glib.h>

void qy_load_theme(void) {
    GtkCssProvider *p = gtk_css_provider_new();
    if (gtk_css_provider_load_from_path(p, "/usr/share/themes/qiyuan/gtk-3.0/gtk.css", NULL)) {
        gtk_style_context_add_provider_for_screen(
            gdk_screen_get_default(), GTK_STYLE_PROVIDER(p),
            GTK_STYLE_PROVIDER_PRIORITY_USER);
    }
    g_object_unref(p);

    /* 强调色: /etc/qytheme.conf accent=orange|purple|blue|green */
    char accent[32] = "orange";
    gchar *content = NULL;
    if (g_file_get_contents("/etc/qytheme.conf", &content, NULL, NULL)) {
        char *line = content;
        while (line && *line) {
            if (strncmp(line, "accent=", 7) == 0) {
                char *nl = strchr(line, '\n');
                if (nl) *nl = 0;
                if (line[7])
                    g_strlcpy(accent, line + 7, sizeof accent);
                break;
            }
            char *nl = strchr(line, '\n');
            line = nl ? nl + 1 : NULL;
        }
        g_free(content);
    }
    const char *color = "#E95420";  /* orange */
    if (!strcmp(accent, "purple")) color = "#77216F";
    else if (!strcmp(accent, "blue")) color = "#1E90FF";
    else if (!strcmp(accent, "green")) color = "#2E9E44";

    /* 覆盖 CSS: 主按钮 / 标题 / 进度条 */
    gchar *css = g_strdup_printf(
        ".qy-btn { background-image: none; background-color: %s; border-color: %s; color: #ffffff; }\n"
        ".qy-btn:hover { background-image: none; background-color: %s; }\n"
        ".qy-mon-cpu { background-color: %s; border-color: %s; color: #ffffff; }\n"
        ".qy-mon-title { color: %s; }\n"
        "progressbar trough { background-color: #222a38; }\n"
        "progressbar progress { background-color: %s; }\n",
        color, color, color, color, color, color, color);
    GtkCssProvider *p2 = gtk_css_provider_new();
    if (gtk_css_provider_load_from_data(p2, css, -1, NULL)) {
        gtk_style_context_add_provider_for_screen(
            gdk_screen_get_default(), GTK_STYLE_PROVIDER(p2),
            GTK_STYLE_PROVIDER_PRIORITY_USER + 1);
    }
    g_object_unref(p2);
    g_free(css);
}

void qy_add_class(GtkWidget *w, const char *cls) {
    gtk_style_context_add_class(gtk_widget_get_style_context(w), cls);
}

/* 可拖动标题栏：GTK HeaderBar 作为 CSD 标题栏。
 * HeaderBar 自带 press/拖动处理（begin_move_drag），
 * 在没有服务端窗口装饰的合成器（如 weston）上也能按住拖动窗口。 */
GtkWidget *qy_make_titlebar(GtkWindow *win, const char *title) {
    GtkWidget *hb = gtk_header_bar_new();
    gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(hb), TRUE);
    if (title && title[0])
        gtk_header_bar_set_title(GTK_HEADER_BAR(hb), title);
    gtk_window_set_titlebar(win, hb);
    g_printerr("QYTHEMEDBG: titlebar=%s\n", title ? title : "");
    return hb;
}