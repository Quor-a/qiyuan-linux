/* qynotify.c — 启元通知发送 CLI
 * 用法: qynotify <标题> <消息>
 * 写入 /tmp/qynotif/latest.msg（qydesktop 顶栏气泡读取），并记录日志。
 */
#include <stdio.h>
#include <string.h>
#include <glib.h>

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: qynotify <title> <message>\n");
        return 1;
    }
    g_mkdir_with_parents("/tmp/qynotif", 0755);
    gchar *content = g_strdup_printf("%s|%s\n", argv[1], argv[2]);
    GError *err = NULL;
    if (!g_file_set_contents("/tmp/qynotif/latest.msg", content, -1, &err)) {
        fprintf(stderr, "qynotify: %s\n", err ? err->message : "write failed");
        g_clear_error(&err);
        g_free(content);
        return 1;
    }
    g_free(content);
    /* 追加日志 */
    gchar *logline = g_strdup_printf("%s|%s\n", argv[1], argv[2]);
    g_file_set_contents("/var/log/qynotify.log", logline, -1, NULL); /* 覆盖式简单日志 */
    g_free(logline);
    return 0;
}