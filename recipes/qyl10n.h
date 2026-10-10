/*
 * qyl10n.h — 澜岫 Linux 轻量多语言框架 (v1.9.1)
 * 用法: 源文件顶部 #include "qyl10n.h"，中文字符串包 TR("...")。
 * 语言来源: 环境变量 QYLANG > /etc/qylang > 默认 zh。
 * 提供 zh 与 en 两张表，表外字符串原样返回（zh 直通）。
 * 链接: qyl10n.c
 */
#ifndef QY_L10N_H
#define QY_L10N_H

const char *qy_tr(const char *zh, const char *en);
#define TR(zh) qy_tr(zh, NULL)      /* 单参: 表查 en, 查不到回 zh */
#define TR2(zh, en) qy_tr(zh, en)   /* 双参: 表查不到时用 en */

#endif
