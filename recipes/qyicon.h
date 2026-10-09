/*
 * qyicon.h — 启元统一 cairo 图标层
 * 与托盘/通知铃铛同源：1.5px 线宽、圆帽圆角、玻璃底 + 单一强调色。
 * 供 qydesktop / qyappmenu / qyfiles 等复用，替代「彩色块+字符」。
 */
#ifndef QYICON_H
#define QYICON_H

#include <gtk/gtk.h>

/* 图标标识：每个枚举对应一个 cairo 线稿绘制函数 */
typedef enum {
    QY_ICON_TERM,      /* 终端 */
    QY_ICON_BROWSER,   /* 浏览器 */
    QY_ICON_FILES,     /* 文件管理器 */
    QY_ICON_IMAGE,     /* 图片查看 */
    QY_ICON_ARCHIVE,   /* 压缩管理 */
    QY_ICON_TRASH,     /* 回收站 */
    QY_ICON_EDIT,      /* 文本编辑 */
    QY_ICON_STORE,     /* 软件中心 */
    QY_ICON_SHOT,      /* 截图工具 */
    QY_ICON_CLIPBOARD, /* 剪贴板 */
    QY_ICON_LOCK,      /* 锁屏 */
    QY_ICON_SEARCH,    /* 全局搜索 */
    QY_ICON_MUSIC,     /* 音乐播放器 */
    QY_ICON_SWITCHER,  /* 窗口切换器 */
    QY_ICON_DRIVER,    /* 驱动管理器 */
    QY_ICON_GIT,       /* Git 工具 */
    QY_ICON_WELCOME,   /* 欢迎 */
    QY_ICON_HOME,      /* 主文件夹 */
    QY_ICON_SETTINGS,  /* 系统设置 */
    QY_ICON_MONITOR,   /* 系统监视 */
    QY_ICON_SETUP,     /* 系统安装 */
    QY_ICON_USERS,     /* 用户管理 */
    QY_ICON_NETWORK,   /* 网络管理 */
    QY_ICON_VIDEO,     /* 视频 */
    QY_ICON_DOC,       /* PDF/文档 */
    QY_ICON_FILE,      /* 通用文件 */
    QY_ICON_COUNT
} QyIconId;

/* 在 (x,y) 起点的 size×size 区域内绘制线稿图标（24×24 逻辑坐标缩放）。
 * color 为描边颜色（NULL 时用白色）；filled 预留（TRUE 时部分闭合形状填充）。 */
void qy_icon_draw(cairo_t *cr, QyIconId id,
                  double x, double y, double size,
                  gboolean filled, const GdkRGBA *color);

/* 玻璃拟态圆角底 + 白色线稿图标（替代「彩色块+字符」） */
void qy_icon_tile(cairo_t *cr, QyIconId id,
                  double x, double y, double size, double radius,
                  const GdkRGBA *bg, const GdkRGBA *color);

/* 渲染为 GdkPixbuf（供 GtkImage / GtkIconView 使用） */
GdkPixbuf *qy_icon_pixbuf(QyIconId id, int px, const GdkRGBA *bg);

#endif /* QYICON_H */