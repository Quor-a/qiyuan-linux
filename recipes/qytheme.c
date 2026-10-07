/* qytheme.c — 启元统一主题助手实现
 * 加载 /usr/share/themes/qiyuan/gtk-3.0/gtk.css（深色桌面主题），
 * 并提供便捷 CSS 类添加函数。
 */
#include "qytheme.h"

void qy_load_theme(void) {
    GtkCssProvider *p = gtk_css_provider_new();
    if (gtk_css_provider_load_from_path(p, "/usr/share/themes/qiyuan/gtk-3.0/gtk.css", NULL)) {
        gtk_style_context_add_provider_for_screen(
            gdk_screen_get_default(), GTK_STYLE_PROVIDER(p),
            GTK_STYLE_PROVIDER_PRIORITY_USER);
    }
    g_object_unref(p);
}

void qy_add_class(GtkWidget *w, const char *cls) {
    gtk_style_context_add_class(gtk_widget_get_style_context(w), cls);
}