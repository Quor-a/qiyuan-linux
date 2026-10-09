/* qytheme.h — 启元统一主题助手
 * 任何 GTK3 应用调用 qy_load_theme() 即可加载 qytheme.css（深色主题）。
 */
#ifndef QYTHEME_H
#define QYTHEME_H

#include <gtk/gtk.h>
#include "qyicon.h"

void qy_load_theme(void);
void qy_add_class(GtkWidget *w, const char *cls);

/* 为无服务端装饰的窗口添加可拖动标题栏（GTK HeaderBar CSD，支持按住拖动） */
GtkWidget *qy_make_titlebar(GtkWindow *win, const char *title);

/* 创建带线稿图标的无边框按钮（qy_icon_pixbuf 渲染；cls 为空时用 qy-icon-btn） */
GtkWidget *qy_icon_button(QyIconId id, int px, const char *tip, const char *cls);

/* 统一设置窗口默认尺寸、最小尺寸，并可选择启动时居中 */
void qy_window_setup(GtkWindow *win, int w, int h, int min_w, int min_h, gboolean center);

#endif