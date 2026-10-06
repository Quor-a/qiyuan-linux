/* qysettings - 启元系统设置 (GTK3) */
#include <gtk/gtk.h>
#include <sys/utsname.h>
#include <sys/sysinfo.h>

/* ---------- 语言页回调 ---------- */
static void on_lang_zh(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    FILE *f = fopen("/etc/qylang", "w");
    if (f) { fputs("zh", f); fclose(f); }
}
static void on_lang_en(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    FILE *f = fopen("/etc/qylang", "w");
    if (f) { fputs("en", f); fclose(f); }
}


static gboolean vol_changed(GtkRange *r, gpointer ud);
static gboolean br_changed(GtkRange *r, gpointer ud);

static gchar *read_first_line(const char *path) {
    gchar *buf = NULL; gsize len = 0;
    if (g_file_get_contents(path, &buf, &len, NULL)) {
        gchar *nl = strchr(buf, '\n');
        if (nl) *nl = 0;
        gchar *s = g_strdup(buf);
        g_free(buf);
        return s;
    }
    return g_strdup("未知");
}

static GtkWidget *row(const char *k, const char *v) {
    GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *kl = gtk_label_new(k);
    gtk_widget_set_size_request(kl, 150, -1);
    gtk_widget_set_halign(kl, GTK_ALIGN_START);
    GtkWidget *vl = gtk_label_new(v);
    gtk_widget_set_halign(vl, GTK_ALIGN_START);
    gtk_label_set_selectable(GTK_LABEL(vl), TRUE);
    gtk_box_pack_start(GTK_BOX(h), kl, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(h), vl, TRUE, TRUE, 0);
    return h;
}

static void activate(GtkApplication *app, gpointer ud) {
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), "启元系统设置");
    GdkGeometry geo = { .max_width = 1920, .max_height = 1080 };
    gtk_window_set_geometry_hints(GTK_WINDOW(win), NULL, &geo, GDK_HINT_MAX_SIZE);
    gtk_window_set_default_size(GTK_WINDOW(win), 620, 420);

    GtkWidget *nb = gtk_notebook_new();
    gtk_container_add(GTK_CONTAINER(win), nb);

    /* 关于本机 */
    GtkWidget *v1 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v1), 14);
    struct utsname u;
    uname(&u);
    struct sysinfo si;
    sysinfo(&si);
    gchar *mem = g_strdup_printf("%.1f MB", si.totalram / 1024.0 / 1024.0);
    gchar *osrel = read_first_line("/etc/qiyuan-release");
    gtk_box_pack_start(GTK_BOX(v1), row("操作系统", osrel), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row("内核版本", u.release), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row("处理器架构", u.machine), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row("主机名", u.nodename), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row("内存总量", mem), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row("桌面环境", "qydesktop (GTK3)"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row("显示协议", "Wayland (weston)"), FALSE, FALSE, 0);
    g_free(mem); g_free(osrel);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v1, gtk_label_new("关于"));

    /* 显示 */
    GtkWidget *v2 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v2), 14);
    gtk_box_pack_start(GTK_BOX(v2), row("合成器", "weston 14.0.2"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v2), row("后端", "DRM (bochs-drm / pixman)"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v2), row("分辨率", "1280x800"), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v2, gtk_label_new("显示"));

    /* 字体 */
    GtkWidget *v3 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v3), 14);
    gtk_box_pack_start(GTK_BOX(v3), row("西文字体", "DejaVu Sans 2.37"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v3), row("中文字体", "Noto Sans CJK"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v3), row("字体回退", "fontconfig"), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v3, gtk_label_new("字体"));

    /* 服务 */
    GtkWidget *v4 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v4), 14);
    gtk_box_pack_start(GTK_BOX(v4), row("1 号进程", "qyinit"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v4), row("会话管理", "seatd"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v4), row("设备管理", "eudev"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v4), row("单元目录", "/etc/qyinit.d"), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v4, gtk_label_new("服务"));

    /* 声音 (ALSA amixer Master) */
    GtkWidget *v5 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v5), 14);
    GtkWidget *vol = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
    gtk_scale_set_draw_value(GTK_SCALE(vol), TRUE);
    gtk_box_pack_start(GTK_BOX(v5), gtk_label_new("输出音量 (Master)"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v5), vol, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v5), row("音频后端", "ALSA (amixer)"), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v5, gtk_label_new("声音"));

    /* 显示: 亮度 (backlight 探测) */
    GtkWidget *v6 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v6), 14);
    GtkWidget *br = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 1, 100, 1);
    gtk_scale_set_draw_value(GTK_SCALE(br), TRUE);
    gtk_box_pack_start(GTK_BOX(v6), gtk_label_new("屏幕亮度"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v6), br, FALSE, FALSE, 0);
    {
        GDir *bld = g_dir_open("/sys/class/backlight", 0, NULL);
        const gchar *bln = NULL;
        if (bld) { bln = g_dir_read_name(bld); }
        if (bln) {
            gchar *blinfo = g_strdup_printf("%s (/sys/class/backlight)", bln);
            gtk_box_pack_start(GTK_BOX(v6), row("背光设备", blinfo), FALSE, FALSE, 0);
            g_free(blinfo);
        } else {
            gtk_box_pack_start(GTK_BOX(v6), row("背光设备", "无 (虚拟显示不支持)"), FALSE, FALSE, 0);
        }
        if (bld) g_dir_close(bld);
    }
    g_signal_connect(vol, "value-changed", G_CALLBACK(vol_changed), NULL);
    g_signal_connect(br, "value-changed", G_CALLBACK(br_changed), NULL);
    /* 初始音量读取 (amixer get Master → [xx%]) */
    {
        gchar *out = NULL;
        gint v0 = 75;
        if (g_spawn_command_line_sync("amixer get Master", &out, NULL, NULL, NULL) && out) {
            gchar *pct = strstr(out, "[");
            if (pct) {
                gint v = atoi(pct + 1);
                if (v >= 0 && v <= 100) v0 = v;
            }
            g_free(out);
        }
        gtk_range_set_value(GTK_RANGE(vol), v0);
    }
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v6, gtk_label_new("亮度"));

    /* 语言 */
    GtkWidget *vlang = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_set_border_width(GTK_CONTAINER(vlang), 16);
    GtkWidget *llb = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(llb), "<b>界面语言 / Interface Language</b>");
    gtk_widget_set_halign(llb, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vlang), llb, FALSE, FALSE, 0);
    GtkWidget *bzh = gtk_button_new_with_label("简体中文");
    GtkWidget *ben = gtk_button_new_with_label("English");
    g_signal_connect(bzh, "clicked", G_CALLBACK(on_lang_zh), NULL);
    g_signal_connect(ben, "clicked", G_CALLBACK(on_lang_en), NULL);
    gtk_box_pack_start(GTK_BOX(vlang), bzh, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vlang), ben, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vlang), gtk_label_new("切换后重新启动生效 / Takes effect after reboot"), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), vlang, gtk_label_new("语言"));

    gtk_widget_show_all(win);
}

static gboolean vol_changed(GtkRange *r, gpointer ud) {
    gint v = (gint)gtk_range_get_value(r);
    gchar *cmd = g_strdup_printf("amixer -q sset Master %d%% 2>/dev/null", v);
    system(cmd);
    g_free(cmd);
    return FALSE;
}

static gboolean br_changed(GtkRange *r, gpointer ud) {
    gint v = (gint)gtk_range_get_value(r);
    GDir *bld = g_dir_open("/sys/class/backlight", 0, NULL);
    if (bld) {
        const gchar *bln;
        gchar *blpath = NULL;
        while ((bln = g_dir_read_name(bld))) { blpath = g_strdup_printf("/sys/class/backlight/%s", bln); break; }
        g_dir_close(bld);
        if (blpath) {
            gchar *bmaxf = g_strdup_printf("%s/max_brightness", blpath);
            gchar *bcurf = g_strdup_printf("%s/brightness", blpath);
            gchar *mx = read_first_line(bmaxf);
            int maxv = atoi(mx);
            if (maxv > 0) {
                FILE *f = fopen(bcurf, "w");
                if (f) { fprintf(f, "%d", maxv * v / 100); fclose(f); }
            }
            g_free(mx); g_free(bmaxf); g_free(bcurf); g_free(blpath);
        }
    }
    return FALSE;
}


int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.settings", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int rc = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return rc;
}
