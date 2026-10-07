/* qytheme.h — 启元统一主题助手
 * 任何 GTK3 应用调用 qy_load_theme() 即可加载 qytheme.css（深色主题）。
 */
#ifndef QYTHEME_H
#define QYTHEME_H

#include <gtk/gtk.h>

void qy_load_theme(void);
void qy_add_class(GtkWidget *w, const char *cls);

#endif