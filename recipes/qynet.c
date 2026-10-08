/* qynet - 启元网络管理器 (GTK3)
 * 显示网络接口列表: 接口名 / 状态 / IPv4 / MAC
 * 数据源: ip -o link show + ip -o -4 addr show（netlink，不依赖 /sys）
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

    /* 底部: 刷新按钮 + 状态栏 */
    GtkWidget *hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *b_refresh = gtk_button_new_with_label(TR("刷新"));
    qy_add_class(b_refresh, "qy-btn");
    g_signal_connect(b_refresh, "clicked", G_CALLBACK(refresh_list), NULL);
    count_label = gtk_label_new("");
    gtk_box_pack_start(GTK_BOX(hb), b_refresh, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hb), count_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), hb, FALSE, FALSE, 0);

    gtk_widget_show_all(win);
    refresh_list();
    gtk_main();
    return 0;
}