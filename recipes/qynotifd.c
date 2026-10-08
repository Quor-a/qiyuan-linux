/* qynotifd.c — 启元通知/设置守护进程
 * 1) 监控 /etc/qy*.conf 变化：为每个开关写入发送"设置已更改"通知
 *    （让 qysettings 的空壳开关有消费端）
 * 2) 消费 qyautostart.conf：内容每行作为命令启动
 * 3) 消费 qynotif.conf：qynotif=off 时禁用通知；qymon=on/off 控制系统监视通知
 * 4) 网络/防火墙/蓝牙等特殊动作（环境无对应工具时仅记日志）
 * 通知统一走 /tmp/qynotif/latest.msg（qydesktop 顶栏显示）。
 */
#include <glib.h>
#include <gio/gio.h>
#include <string.h>
#include <stdio.h>

static gboolean notif_enabled = TRUE;
static gboolean mon_enabled = FALSE;

/* 发送通知（写入 latest.msg） */
static void send_notif(const char *title, const char *msg) {
    if (!notif_enabled) return;
    g_mkdir_with_parents("/tmp/qynotif", 0755);
    gchar *content = g_strdup_printf("%s|%s\n", title, msg);
    g_file_set_contents("/tmp/qynotif/latest.msg", content, -1, NULL);
    g_free(content);
}

/* 读取简单键值 conf（如 qynotif.conf 的 qymon=off） */
static gboolean conf_flag(const char *path, const char *key) {
    gchar *c = NULL;
    if (!g_file_get_contents(path, &c, NULL, NULL) || !c) {
        g_free(c);
        return FALSE;
    }
    gboolean on = FALSE;
    gchar *line = c;
    while (line && *line) {
        if (strncmp(line, key, strlen(key)) == 0 && line[strlen(key)] == '=') {
            on = (line[strlen(key) + 1] == 'o' && line[strlen(key) + 2] == 'n');
            break;
        }
        gchar *nl = strchr(line, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(c);
    return on;
}

/* 执行自动启动项（qyautostart.conf 格式：应用名=on/off） */
static void run_autostart(void) {
    gchar *c = NULL;
    if (!g_file_get_contents("/etc/qyautostart.conf", &c, NULL, NULL) || !c) {
        g_free(c);
        return;
    }
    gchar **lines = g_strsplit(c, "\n", 0);
    g_free(c);
    for (int i = 0; lines && lines[i]; i++) {
        gchar *line = g_strstrip(lines[i]);
        if (!line[0] || line[0] == '#') continue;
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = 0;
        const char *name = line;
        gboolean on = (eq[1] == 'o' && eq[2] == 'n');
        if (on && g_str_has_prefix(name, "qy")) {
            gchar *cmd = g_strdup_printf("%s &", name);
            g_spawn_command_line_async(cmd, NULL);
            g_free(cmd);
            g_printerr("qynotifd: autostart %s\n", name);
        }
    }
    g_strfreev(lines);
}

/* 处理单个 conf 变化 */
static void handle_conf(const char *basename) {
    gchar path[512];
    g_snprintf(path, sizeof path, "/etc/%s", basename);
    const char *title = "设置";

    if (g_str_has_prefix(basename, "qyautostart")) {
        run_autostart();
        send_notif("自动启动", "启动项配置已更新");
        return;
    }
    if (g_str_has_prefix(basename, "qynotif")) {
        gchar *c = NULL;
        g_file_get_contents(path, &c, NULL, NULL);
        notif_enabled = !(c && strstr(c, "qynotif=off"));
        mon_enabled = conf_flag(path, "qymon");
        g_free(c);
        send_notif("通知", notif_enabled ? "通知服务已启用" : "通知服务已关闭");
        return;
    }
    if (g_str_has_prefix(basename, "qywifi")) {
        gboolean on = conf_flag(path, "wifi");
        gchar cmd[128];
        g_snprintf(cmd, sizeof cmd, "ip link set dev wlan0 %s 2>/dev/null", on ? "up" : "down");
        g_spawn_command_line_async(cmd, NULL);
        send_notif("WiFi", on ? "WiFi 已开启" : "WiFi 已关闭");
        return;
    }
    if (g_str_has_prefix(basename, "qybluetooth")) {
        gboolean on = conf_flag(path, "bluetooth");
        gchar cmd[128];
        g_snprintf(cmd, sizeof cmd, "rfkill unblock bluetooth 2>/dev/null; %s", on ? "hciconfig hci0 up 2>/dev/null" : "hciconfig hci0 down 2>/dev/null");
        g_spawn_command_line_async(cmd, NULL);
        send_notif("蓝牙", on ? "蓝牙已开启" : "蓝牙已关闭");
        return;
    }
    if (g_str_has_prefix(basename, "qyfirewall")) {
        gboolean on = conf_flag(path, "firewall");
        if (on)
            g_spawn_command_line_async("iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null", NULL);
        else
            g_spawn_command_line_async("iptables -F 2>/dev/null", NULL);
        send_notif("防火墙", on ? "防火墙已启用" : "防火墙已关闭");
        return;
    }
    if (g_str_has_prefix(basename, "qyprinter")) {
        send_notif("打印机", "打印机设置已保存");
        return;
    }
    if (g_str_has_prefix(basename, "qydisplay") || g_str_has_prefix(basename, "qyhdr")
        || g_str_has_prefix(basename, "qygraphics") || g_str_has_prefix(basename, "qypen")) {
        send_notif("显示", "显示设置已保存（重启桌面后生效）");
        return;
    }
    /* 通用 */
    gchar *n = g_strdup(basename + 2); /* 去掉 qy 前缀 */
    gchar *dot = strrchr(n, '.');
    if (dot) *dot = 0;
    gchar *msg = g_strdup_printf("%s 设置已更新", n);
    send_notif(title, msg);
    g_free(n);
    g_free(msg);
}

static void on_dir_changed(GFileMonitor *mon, GFile *file, GFile *other,
                           GFileMonitorEvent evt, gpointer ud) {
    (void)mon; (void)other; (void)ud;
    if (evt != G_FILE_MONITOR_EVENT_CHANGED &&
        evt != G_FILE_MONITOR_EVENT_CREATED)
        return;
    if (!file) return;
    char *basename = g_file_get_basename(file);
    if (basename && g_str_has_prefix(basename, "qy") && g_str_has_suffix(basename, ".conf")) {
        g_printerr("qynotifd: conf changed: %s\n", basename);
        handle_conf(basename);
    }
    g_free(basename);
}

static gboolean load_initial_conf(gpointer ud) {
    (void)ud;
    /* 启动时消费已有配置 */
    gchar *c = NULL;
    g_file_get_contents("/etc/qynotif.conf", &c, NULL, NULL);
    notif_enabled = !(c && strstr(c, "qynotif=off"));
    mon_enabled = conf_flag("/etc/qynotif.conf", "qymon");
    g_free(c);
    run_autostart();
    if (mon_enabled)
        send_notif("系统监视", "系统监视通知已开启");
    return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    GMainLoop *loop = g_main_loop_new(NULL, FALSE);
    g_mkdir_with_parents("/tmp/qynotif", 0755);

    GFile *dir = g_file_new_for_path("/etc");
    GError *err = NULL;
    GFileMonitor *mon = g_file_monitor_directory(dir, G_FILE_MONITOR_NONE, NULL, &err);
    if (!mon) {
        g_printerr("qynotifd: monitor /etc: %s\n", err ? err->message : "?");
        g_clear_error(&err);
        return 1;
    }
    g_signal_connect(mon, "changed", G_CALLBACK(on_dir_changed), NULL);
    g_object_unref(dir);

    g_timeout_add(500, load_initial_conf, NULL);
    g_printerr("qynotifd: started\n");
    g_main_loop_run(loop);
    g_object_unref(mon);
    return 0;
}