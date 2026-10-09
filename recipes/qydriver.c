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

/* ---------- 9 类驱动概览：按常见内核模块检测硬件支持 ---------- */
typedef struct { const char *name; const char *mods[4]; } DrvCat;
static const DrvCat drv_cats[] = {
    { "显卡",   { "i915", "nouveau", "amdgpu", "radeon" } },
    { "声卡",   { "snd_hda_intel", "snd_hda_codec", "snd_hda_codec_realtek", NULL } },
    { "网卡",   { "e1000", "r8169", "igb", "i40e" } },
    { "无线",   { "iwlwifi", "ath9k", "rtl8xxxu", "rtl8188ee" } },
    { "蓝牙",   { "bluetooth", "btusb", NULL, NULL } },
    { "USB存储", { "usb_storage", "uas", NULL, NULL } },
    { "摄像头",  { "uvcvideo", NULL, NULL, NULL } },
    { "输入",   { "hid_generic", "usbhid", NULL, NULL } },
    { "文件系统",{ "ext4", "vfat", "ntfs3", "f2fs" } },
};
#define NDRV ((int)(sizeof drv_cats / sizeof drv_cats[0]))

static GtkWidget *cat_label = NULL;

/* 目录存在且非空 */
static gboolean dir_has_entry(const char *path) {
    GDir *d = g_dir_open(path, 0, NULL);
    if (!d) return FALSE;
    gboolean has = g_dir_read_name(d) != NULL;
    g_dir_close(d);
    return has;
}

/* /proc/filesystems 是否支持某文件系统 */
static gboolean fs_supported(const char *fs) {
    gchar *c = NULL;
    g_file_get_contents("/proc/filesystems", &c, NULL, NULL);
    gboolean ok = c && strstr(c, fs);
    g_free(c);
    return ok;
}

/* 检测某一类别是否受支持：优先匹配 /proc/modules 模块名；
 * 未作为模块加载时（驱动编入内核）回退检查 /sys/class 设备。 */
static int cat_supported(int idx) {
    gchar *c = NULL;
    g_file_get_contents("/proc/modules", &c, NULL, NULL);
    for (int k = 0; k < 4 && drv_cats[idx].mods[k]; k++)
        if (c && strstr(c, drv_cats[idx].mods[k])) { g_free(c); return 1; }
    g_free(c);
    switch (idx) {
        case 0: return dir_has_entry("/sys/class/drm");       /* 显卡 */
        case 1: return dir_has_entry("/sys/class/sound");     /* 声卡 */
        case 2: return dir_has_entry("/sys/class/net");       /* 网卡 */
        case 3: { /* 无线: 网卡列表中存在 wlan 或 wlp 前缀 */
            GDir *d = g_dir_open("/sys/class/net", 0, NULL);
            if (!d) return FALSE;
            const char *e; int ok = 0;
            while ((e = g_dir_read_name(d)) != NULL) {
                if (strncmp(e, "wlan", 4) == 0 || strncmp(e, "wlp", 3) == 0) { ok = 1; break; }
            }
            g_dir_close(d);
            return ok;
        }
        case 4: return dir_has_entry("/sys/class/bluetooth");  /* 蓝牙 */
        case 5: return dir_has_entry("/sys/bus/usb/devices");  /* USB 存储 */
        case 6: return dir_has_entry("/sys/class/video4linux");/* 摄像头 */
        case 7: return dir_has_entry("/sys/class/input");      /* 输入 */
        case 8: return fs_supported("ext4") || fs_supported("vfat") ||
                       fs_supported("ntfs3") || fs_supported("f2fs"); /* 文件系统 */
    }
    return 0;
}

/* 统计已检测到的驱动类别数（模块 + 硬件设备） */
static int detect_driver_cats(void) {
    int found = 0;
    for (int i = 0; i < NDRV; i++)
        if (cat_supported(i)) found++;
    return found;
}

/* 刷新类别概览标签 */
static void refresh_driver_cats(void) {
    if (!cat_label) return;
    GString *s = g_string_new(TR("驱动类别: "));
    for (int i = 0; i < NDRV; i++) {
        int ok = cat_supported(i);
        g_string_append_printf(s, "%s %s  ", drv_cats[i].name, ok ? "✓" : "-");
    }
    gchar *txt = g_string_free(s, FALSE);
    gtk_label_set_text(GTK_LABEL(cat_label), txt);
    g_free(txt);
}

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
    qy_make_titlebar(GTK_WINDOW(win), TR("启元驱动管理器"));
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 8);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 驱动类别概览（9 类硬件支持状态） */
    cat_label = gtk_label_new("");
    qy_add_class(cat_label, "qy-mon-info");
    gtk_widget_set_halign(cat_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), cat_label, FALSE, FALSE, 0);

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
    refresh_driver_cats();
    /* 自动化验证: QYDRIVER=1 额外打印类别数 */
    if (g_getenv("QYDRIVER"))
        g_printerr("QYDRIVERDBG: cats=%d/%d\n", detect_driver_cats(), NDRV);
    gtk_main();
    return 0;
}