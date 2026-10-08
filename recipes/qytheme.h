/* qytheme.h — 启元统一主题助手
 * 任何 GTK3 应用调用 qy_load_theme() 即可加载 qytheme.css（深色主题）。
 */
#ifndef QYTHEME_H
#define QYTHEME_H

#include <gtk/gtk.h>

void qy_load_theme(void);
void qy_add_class(GtkWidget *w, const char *cls);

/* 为无服务端装饰的窗口添加可拖动标题栏（GTK HeaderBar CSD，支持按住拖动） */
GtkWidget *qy_make_titlebar(GtkWindow *win, const char *title);

#endif