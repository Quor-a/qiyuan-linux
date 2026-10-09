/* qynet - 启元网络管理器 (GTK3)
 * 显示网络接口列表: 接口名 / 状态 / IPv4 / MAC
 * 数据源: ip -o link show + ip -o -4 addr show（netlink，不依赖 /sys）
 * 连接: 无 IP 时 ip link up + udhcpc；已有 IP 显示已连接
 * 自动化: QYNET_CONNECT=eth0 启动后自动执行连接动作
 * 架构: 单文件 GTK3，与 qyfiles 同款编译方式
 */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>

enum { C_IF, C_STATE, C_IP, C_MAC, N_COLS };

static GtkListStore *store = NULL;
static GtkWidget *count_label = NULL;
static GtkWidget *status_label = NULL;

/* 读取指定接口的 IPv4 地址（多个用空格分隔） */
static void read_ip(char *buf, size_t n, const char *ifname) {
    buf[0] = 0;
    char cmd[128];
    snprintf(cmd, sizeof cmd, "ip -o -4 addr show %s 2>/dev/null", ifname);
    FILE *f = popen(cmd, "r");
    if (!f) return;
    char line[512];
    while (fgets(line, sizeof line, f)) {
        char *p = strstr(line, "inet ");
        if (p) {
            p += 5;
            char *sp = strchr(p, ' ');
            if (sp) *sp = 0;
            if (buf[0]) strncat(buf, " ", n - strlen(buf) - 1);
            strncat(buf, p, n - strlen(buf) - 1);
        }
    }
    pclose(f);
}

/* 获取当前选中的接口名（没有选中时取第一个非 lo 接口） */
static const char *selected_ifname(void) {
    static char buf[64] = "";
    buf[0] = 0;
    /* 简化：直接读第一个非 lo 接口 */
    FILE *f = popen("ip -o link show 2>/dev/null | grep -v ': lo:' | head -1", "r");
    if (f) {
        char line[256];
        if (fgets(line, sizeof line, f)) {
            char *colon = strchr(line, ':');
            if (colon) {
                char tmp[64];
                if (sscanf(line, "%*d: %63[^:]:", tmp) == 1)
                    snprintf(buf, sizeof buf, "%s", tmp);
            }
        }
        pclose(f);
    }
    return buf;
}

/* 刷新接口列表 */
static void refresh_list(void) {
    gtk_list_store_clear(store);
    FILE *f = popen("ip -o link show 2>/dev/null", "r");
    if (!f) return;
    char line[1024];
    int n_if = 0, n_up = 0;
    while (fgets(line, sizeof line, f)) {
        /* 格式: 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ... state UP ... link/ether 52:54:00:.. brd .. */
        char *colon = strchr(line, ':');
        if (!colon) continue;
        char ifname[64] = "";
        if (sscanf(line, "%*d: %63[^:]:", ifname) != 1 || !ifname[0])
            continue;
        /* 状态: state UP / DOWN / UNKNOWN */
        char state[32] = "-";
        char *st = strstr(line, "state ");
        if (st) {
            st += 6;
            char *sp = strchr(st, ' ');
            if (sp) *sp = 0;
            snprintf(state, sizeof state, "%s", st);
        }
        /* MAC: link/ether 52:54:... 或 link/loopback 00:00:... */
        char mac[64] = "-";
        char *macp = strstr(line, "link/");
        if (macp) {
            macp += 5;
            if (sscanf(macp, "%*s %63s", mac) != 1) {
                char *sp = strchr(macp, ' ');
                if (sp) *sp = 0;
                snprintf(mac, sizeof mac, "%s", macp);
            }
        }
        /* IPv4 */
        char ip[256] = "-";
        read_ip(ip, sizeof ip, ifname);
        if (!ip[0]) snprintf(ip, sizeof ip, "-");
        /* 在线统计: state UP 且非 lo */
        if (strcmp(state, "UP") == 0 && strcmp(ifname, "lo") != 0) n_up++;
        n_if++;
        GtkTreeIter it;
        gtk_list_store_append(store, &it);
        gtk_list_store_set(store, &it, C_IF, ifname, C_STATE, state,
                              C_IP, ip, C_MAC, mac, -1);
    }
    pclose(f);
    if (count_label) {
        gchar *txt = g_strdup_printf(TR("接口 %d 个 · 在线 %d"), n_if, n_up);
        gtk_label_set_text(GTK_LABEL(count_label), txt);
        g_free(txt);
    }
}

/* 连接以太网：已有 IP 视为已连接；无 IP 则 up + udhcpc */
static void do_connect(GtkWidget *w, gpointer ud) {
    (void)w;
    const char *ifname = ud ? (const char *)ud : selected_ifname();
    if (!ifname || !ifname[0]) return;
    char ip[256] = "-";
    read_ip(ip, sizeof ip, ifname);
    if (ip[0] && strcmp(ip, "-") != 0 && strcmp(ip, "") != 0) {
        g_printerr("QYNETDBG: connect %s already up (%s)\n", ifname, ip);
        if (status_label) {
            gchar *s = g_strdup_printf(TR("已连接 %s（%s）"), ifname, ip);
            gtk_label_set_text(GTK_LABEL(status_label), s);
            g_free(s);
        }
        return;
    }
    g_printerr("QYNETDBG: connect %s (dhcp)\n", ifname);
    if (status_label)
        gtk_label_set_text(GTK_LABEL(status_label), TR("正在连接..."));
    char cmd[256];
    snprintf(cmd, sizeof cmd,
             "ip link set dev %s up 2>/dev/null; udhcpc -i %s >/dev/null 2>&1 &",
             ifname, ifname);
    g_spawn_command_line_async(cmd, NULL);
    g_timeout_add(3000, (GSourceFunc)refresh_list, NULL);
    if (status_label) {
        gchar *s = g_strdup_printf(TR("%s 连接请求已发送"), ifname);
        gtk_label_set_text(GTK_LABEL(status_label), s);
        g_free(s);
    }
}

/* ---------- WiFi 热点连接（wpa_supplicant + udhcpc） ---------- */
static const char *find_wlan_iface(void) {
    static char buf[32] = "wlan0";
    GtkTreeIter it;
    if (gtk_tree_model_get_iter_first(GTK_TREE_MODEL(store), &it)) {
        do {
            gchar *name = NULL;
            gtk_tree_model_get(GTK_TREE_MODEL(store), &it, C_IF, &name, -1);
            if (name && strncmp(name, "wlan", 4) == 0) {
                g_strlcpy(buf, name, sizeof buf);
                g_free(name);
                return buf;
            }
            g_free(name);
        } while (gtk_tree_model_iter_next(GTK_TREE_MODEL(store), &it));
    }
    return buf;
}

static void wifi_connect(const char *ssid, const char *psk) {
    if (!ssid || !ssid[0]) return;
    const char *ifname = find_wlan_iface();
    /* 生成 wpa_supplicant.conf（写入 /tmp，避免污染系统配置） */
    GString *conf = g_string_new("network={\n");
    g_string_append_printf(conf, "    ssid=\"%s\"\n", ssid);
    if (psk && psk[0])
        g_string_append_printf(conf, "    psk=\"%s\"\n", psk);
    else
        g_string_append(conf, "    key_mgmt=NONE\n");
    g_string_append(conf, "}\n");
    g_file_set_contents("/tmp/qywifi.conf", conf->str, conf->len, NULL);
    g_string_free(conf, TRUE);
    g_printerr("QYNETWIFI: connect ssid=%s iface=%s\n", ssid, ifname);
    gchar *cmd = g_strdup_printf(
        "wpa_supplicant -B -i %s -c /tmp/qywifi.conf >/dev/null 2>&1; "
        "udhcpc -i %s >/dev/null 2>&1 &", ifname, ifname);
    g_spawn_command_line_async(cmd, NULL);
    g_free(cmd);
    if (status_label) {
        gchar *s = g_strdup_printf(TR("正在连接 WiFi %s（%s）..."), ssid, ifname);
        gtk_label_set_text(GTK_LABEL(status_label), s);
        g_free(s);
    }
    g_timeout_add(3000, (GSourceFunc)refresh_list, NULL);
}

static void on_wifi_clicked(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    GtkWidget *dlg = gtk_dialog_new_with_buttons(TR("连接 WiFi"), NULL,
        GTK_DIALOG_MODAL, TR("连接"), GTK_RESPONSE_OK,
        TR("取消"), GTK_RESPONSE_CANCEL, NULL);
    GtkWidget *box = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    GtkWidget *ssid_e = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(ssid_e), TR("WiFi 名称 (SSID)"));
    GtkWidget *psk_e = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(psk_e), TR("密码（开放网络留空）"));
    gtk_entry_set_visibility(GTK_ENTRY(psk_e), FALSE);
    gtk_box_pack_start(GTK_BOX(box), ssid_e, FALSE, FALSE, 6);
    gtk_box_pack_start(GTK_BOX(box), psk_e, FALSE, FALSE, 6);
    gtk_widget_show_all(dlg);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_OK) {
        const char *ssid = gtk_entry_get_text(GTK_ENTRY(ssid_e));
        const char *psk = gtk_entry_get_text(GTK_ENTRY(psk_e));
        wifi_connect(ssid, psk);
    }
    gtk_widget_destroy(dlg);
}

/* 自动化: QYNET_WIFI=SSID|密码 */
static gboolean auto_wifi(gpointer p) {
    char *arg = (char *)p;
    char *bar = strchr(arg, '|');
    if (bar) *bar = 0;
    wifi_connect(arg, bar ? bar + 1 : "");
    g_free(arg);
    return G_SOURCE_REMOVE;
}

/* 自动化: QYNET_CONNECT=eth0 */
static gboolean auto_connect(gpointer p) {
    do_connect(NULL, p);
    return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    qy_load_theme();

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元网络管理器"));
    gtk_window_set_default_size(GTK_WINDOW(win), 620, 360);
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 8);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 列表 */
    store = gtk_list_store_new(N_COLS, G_TYPE_STRING, G_TYPE_STRING,
                                G_TYPE_STRING, G_TYPE_STRING);
    GtkWidget *tv = gtk_tree_view_new_with_model(GTK_TREE_MODEL(store));
    const char *titles[N_COLS] = { TR("接口"), TR("状态"), TR("IP 地址"), TR("MAC 地址") };
    for (int i = 0; i < N_COLS; i++) {
        GtkCellRenderer *r = gtk_cell_renderer_text_new();
        GtkTreeViewColumn *c = gtk_tree_view_column_new_with_attributes(
            titles[i], r, "text", i, NULL);
        gtk_tree_view_column_set_resizable(c, TRUE);
        gtk_tree_view_append_column(GTK_TREE_VIEW(tv), c);
    }
    GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(sw), tv);
    gtk_box_pack_start(GTK_BOX(vbox), sw, TRUE, TRUE, 0);

    /* 底部: 连接/刷新按钮 + 状态 */
    GtkWidget *hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *b_conn = gtk_button_new_with_label(TR("连接"));
    qy_add_class(b_conn, "qy-btn");
    g_signal_connect(b_conn, "clicked", G_CALLBACK(do_connect), NULL);
    GtkWidget *b_refresh = gtk_button_new_with_label(TR("刷新"));
    qy_add_class(b_refresh, "qy-btn");
    g_signal_connect(b_refresh, "clicked", G_CALLBACK(refresh_list), NULL);
    GtkWidget *b_wifi = gtk_button_new_with_label(TR("WiFi 连接"));
    qy_add_class(b_wifi, "qy-btn");
    g_signal_connect(b_wifi, "clicked", G_CALLBACK(on_wifi_clicked), NULL);
    count_label = gtk_label_new("");
    status_label = gtk_label_new("");
    gtk_box_pack_start(GTK_BOX(hb), b_conn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hb), b_refresh, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hb), b_wifi, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hb), count_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), hb, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 0);

    gtk_widget_show_all(win);
    refresh_list();

    /* 自动化: QYNET_CONNECT=eth0 自动连接 */
    const char *qc = g_getenv("QYNET_CONNECT");
    if (qc && qc[0])
        g_timeout_add(600, auto_connect, g_strdup(qc));
    /* 自动化: QYNET_WIFI=SSID|密码 自动连接 WiFi */
    const char *qw = g_getenv("QYNET_WIFI");
    if (qw && qw[0])
        g_timeout_add(800, auto_wifi, g_strdup(qw));

    gtk_main();
    return 0;
}