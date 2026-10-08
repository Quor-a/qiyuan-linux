/* qydriver.c — 启元驱动管理器 (GTK3)
 * 显示已加载内核模块（/proc/modules）+ USB 设备（/sys/bus/usb/devices）
 * 数据源：/proc/modules（模块名/大小/使用数/依赖）、
 *         /sys/bus/usb/devices 下各设备的 product/idVendor/idProduct 文件
 * 自动化：QYDRIVER=1 启动后打印模块数日志
 * 架构：单文件 GTK3，与 qyfiles 同款编译方式
 */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>

enum { C_MOD, C_SIZE, C_USED, C_DEPS, N_COLS };

static GtkListStore *store = NULL;
static GtkWidget *count_label = NULL;
static GtkWidget *usb_label = NULL;

/* 读取 /proc/modules 填充驱动列表 */
static void refresh_modules(void) {
    gtk_list_store_clear(store);
    FILE *f = fopen("/proc/modules", "r");
    int n = 0;
    if (f) {
        char line[1024];
        while (fgets(line, sizeof line, f)) {
            char name[128] = "-";
            long size = 0, used = 0;
            int n_used = 0;
            char deps[512] = "-";
            /* 格式: module 16384 0 - Live 0x... */
            char live[32] = "";
            int parsed = sscanf(line, "%127s %ld %d %d %31s", name, &size, &n_used, &used, live);
            (void)parsed;
            /* 依赖: 第 4 个字段是使用数，第 5 是状态；依赖在更后面
               简化：取第 6 字段起为依赖（逗号分隔） */
            char *p = strchr(line, ']');
            if (p) {
                char *d = p + 1;
                while (*d == ' ' || *d == '\t') d++;
                char *nl = strchr(d, '\n');
                if (nl) *nl = 0;
                if (d[0]) snprintf(deps, sizeof deps, "%s", d);
            }
            char sizestr[32], usedstr[32];
            snprintf(sizestr, sizeof sizestr, "%ld KB", size / 1024);
            snprintf(usedstr, sizeof usedstr, "%ld", used);
            GtkTreeIter it;
            gtk_list_store_append(store, &it);
            gtk_list_store_set(store, &it, C_MOD, name, C_SIZE, sizestr,
                               C_USED, usedstr, C_DEPS, deps, -1);
            n++;
        }
        fclose(f);
    }
    if (count_label) {
        gchar *txt = g_strdup_printf(TR("已加载模块 %d 个"), n);
        gtk_label_set_text(GTK_LABEL(count_label), txt);
        g_free(txt);
    }
    g_printerr("QYDRIVERDBG: modules=%d\n", n);
}

/* 读取 USB 设备列表（/sys/bus/usb/devices 下各设备的 product/idVendor/idProduct 文件） */
static void refresh_usb(void) {
    GString *s = g_string_new(NULL);
    int n = 0;
    GDir *dir = g_dir_open("/sys/bus/usb/devices", 0, NULL);
    if (dir) {
        const gchar *d;
        while ((d = g_dir_read_name(dir))) {
            if (d[0] != '1' && d[0] != '2' && d[0] != '3' && d[0] != '4'
                && d[0] != '5' && d[0] != '6' && d[0] != '7' && d[0] != '8')
                continue;
            gchar *base = g_build_filename("/sys/bus/usb/devices", d, NULL);
            gchar *prod = g_build_filename(base, "product", NULL);
            gchar *vid = g_build_filename(base, "idVendor", NULL);
            gchar *pid = g_build_filename(base, "idProduct", NULL);
            gchar *ptxt = NULL, *vtxt = NULL, *ptxt2 = NULL;
            g_file_get_contents(prod, &ptxt, NULL, NULL);
            g_file_get_contents(vid, &vtxt, NULL, NULL);
            g_file_get_contents(pid, &ptxt2, NULL, NULL);
            if (ptxt) {
                gchar *line = g_strstrip(ptxt);
                g_string_append_printf(s, "· %s (%s:%s)\n", line,
                    vtxt ? g_strstrip(vtxt) : "?",
                    ptxt2 ? g_strstrip(ptxt2) : "?");
                n++;
            }
            g_free(base); g_free(prod); g_free(vid); g_free(pid);
            g_free(ptxt); g_free(vtxt); g_free(ptxt2);
        }
        g_dir_close(dir);
    }
    if (usb_label) {
        if (n == 0)
            gtk_label_set_text(GTK_LABEL(usb_label), TR("USB: 未检测到设备（无硬件或未插拔）"));
        else
            gtk_label_set_text(GTK_LABEL(usb_label), s->str);
    }
    g_string_free(s, TRUE);
}

static void on_refresh(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    refresh_modules();
    refresh_usb();
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    qy_load_theme();

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元驱动管理器"));
    gtk_window_set_default_size(GTK_WINDOW(win), 680, 420);
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 8);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 模块列表 */
    store = gtk_list_store_new(N_COLS, G_TYPE_STRING, G_TYPE_STRING,
                                G_TYPE_STRING, G_TYPE_STRING);
    GtkWidget *tv = gtk_tree_view_new_with_model(GTK_TREE_MODEL(store));
    const char *titles[N_COLS] = { TR("模块"), TR("大小"), TR("使用数"), TR("依赖") };
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

    /* 底部: 刷新 + 模块数 + USB 状态 */
    GtkWidget *hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *b_ref = gtk_button_new_with_label(TR("刷新"));
    qy_add_class(b_ref, "qy-btn");
    g_signal_connect(b_ref, "clicked", G_CALLBACK(on_refresh), NULL);
    count_label = gtk_label_new("");
    gtk_box_pack_start(GTK_BOX(hb), b_ref, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(hb), count_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), hb, FALSE, FALSE, 0);
    usb_label = gtk_label_new("");
    qy_add_class(usb_label, "qy-mon-info");
    gtk_widget_set_halign(usb_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), usb_label, FALSE, FALSE, 0);

    gtk_widget_show_all(win);
    refresh_modules();
    refresh_usb();
    gtk_main();
    return 0;
}