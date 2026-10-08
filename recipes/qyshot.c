/* qyshot.c — 启元截图工具
 * 在 X11 显示后端下截取整个屏幕（gdk_get_default_root_window），
 * 支持保存 PNG / 复制到剪贴板 / 自动截图（QYSHOT_AUTO）。
 */
#include <gtk/gtk.h>
#include <gdk/gdk.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "qytheme.h"
#include "qyl10n.h"

static GtkWidget *preview = NULL;      /* 截图预览 */
static GdkPixbuf *shot_pixbuf = NULL;
static GtkWidget *status_label = NULL;
static char last_path[512] = "";

static gboolean on_capture_wrap(gpointer p);   /* 前向声明 */

/* 解析 qyshot-capture 输出的 24-bit BMP（gdk-pixbuf 无 BMP 加载器时自解析） */
static GdkPixbuf *bmp_to_pixbuf(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    unsigned char hdr[54];
    if (fread(hdr, 1, 54, f) != 54 || hdr[0] != 'B' || hdr[1] != 'M') {
        fclose(f);
        return NULL;
    }
    int w = hdr[18] | (hdr[19] << 8) | (hdr[20] << 16) | (hdr[21] << 24);
    int h = hdr[22] | (hdr[23] << 8) | (hdr[24] << 16) | (hdr[25] << 24);
    int offset = hdr[10] | (hdr[11] << 8) | (hdr[12] << 16) | (hdr[13] << 24);
    if (w <= 0 || h <= 0 || w > 20000 || h > 20000 || offset < 54) {
        fclose(f);
        return NULL;
    }
    fseek(f, offset, SEEK_SET);
    int row_size = (w * 3 + 3) & ~3;
    unsigned char *row = malloc(row_size);
    GdkPixbuf *pb = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, w, h);
    if (!row || !pb) {
        free(row);
        if (pb) g_object_unref(pb);
        fclose(f);
        return NULL;
    }
    int n_channels = gdk_pixbuf_get_n_channels(pb);
    int rowstride = gdk_pixbuf_get_rowstride(pb);
    guchar *pixels = gdk_pixbuf_get_pixels(pb);
    for (int y = 0; y < h; y++) {
        if (fread(row, 1, row_size, f) != (size_t)row_size) break;
        guchar *dst = pixels + (h - 1 - y) * rowstride;   /* BMP 自底向上 */
        for (int x = 0; x < w; x++) {
            dst[x * n_channels]     = row[x * 3 + 2];    /* R */
            dst[x * n_channels + 1] = row[x * 3 + 1];    /* G */
            dst[x * n_channels + 2] = row[x * 3];        /* B */
        }
    }
    free(row);
    fclose(f);
    return pb;
}

/* 截取整个屏幕: 调用 qyshot-capture（纯 X11）抓根窗口保存 BMP 后加载 */
static GdkPixbuf *capture_screen(void) {
    const char *disp = g_getenv("QYSHOT_DISPLAY");
    if (!disp) disp = ":0";
    char tmp[96];
    g_snprintf(tmp, sizeof tmp, "/tmp/qyshot-%d.bmp", (int)getpid());
    char cmd[640];
    g_snprintf(cmd, sizeof cmd, "DISPLAY=%s /usr/bin/qyshot-capture %s 2>/dev/null", disp, tmp);
    int rc = system(cmd);
    GdkPixbuf *pb = NULL;
    if (rc == 0)
        pb = bmp_to_pixbuf(tmp);
    unlink(tmp);
    return pb;
}

/* 生成默认文件名: 截图_年月日_时分秒.png */
static void make_default_path(char *buf, size_t sz) {
    time_t t = time(NULL);
    struct tm *tm = localtime(&t);
    g_snprintf(buf, sz, "%s/截图_%04d%02d%02d_%02d%02d%02d.png",
               g_get_user_special_dir(G_USER_DIRECTORY_PICTURES),
               tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday,
               tm->tm_hour, tm->tm_min, tm->tm_sec);
}

static void update_preview(void) {
    if (preview && shot_pixbuf) {
        int w = gdk_pixbuf_get_width(shot_pixbuf);
        int h = gdk_pixbuf_get_height(shot_pixbuf);
        /* 缩放到预览区（最大 560x360） */
        GdkPixbuf *scaled = NULL;
        if (w > 560 || h > 360) {
            double s = 560.0 / w < 360.0 / h ? 560.0 / w : 360.0 / h;
            scaled = gdk_pixbuf_scale_simple(shot_pixbuf, (int)(w * s), (int)(h * s),
                                             GDK_INTERP_BILINEAR);
        }
        gtk_image_set_from_pixbuf(GTK_IMAGE(preview), scaled ? scaled : shot_pixbuf);
        if (scaled) g_object_unref(scaled);
    }
}

/* 全屏截图 */
static void on_capture(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (shot_pixbuf) { g_object_unref(shot_pixbuf); shot_pixbuf = NULL; }
    shot_pixbuf = capture_screen();
    if (!shot_pixbuf) {
        gtk_label_set_text(GTK_LABEL(status_label), TR("截图失败：无法访问屏幕"));
        return;
    }
    update_preview();
    char st[128];
    g_snprintf(st, sizeof st, "%d×%d %s",
               gdk_pixbuf_get_width(shot_pixbuf), gdk_pixbuf_get_height(shot_pixbuf),
               TR("截图完成"));
    gtk_label_set_text(GTK_LABEL(status_label), st);
}

/* 保存 */
static void on_save(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (!shot_pixbuf) return;
    char def[512];
    make_default_path(def, sizeof def);
    GtkWidget *dlg = gtk_file_chooser_dialog_new(
        TR("保存截图"), NULL, GTK_FILE_CHOOSER_ACTION_SAVE,
        TR("取消"), GTK_RESPONSE_CANCEL, TR("保存"), GTK_RESPONSE_ACCEPT, NULL);
    gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(dlg), g_path_get_basename(def));
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
        char *path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
        if (path) {
            GError *err = NULL;
            if (gdk_pixbuf_save(shot_pixbuf, path, "png", &err, NULL)) {
                g_strlcpy(last_path, path, sizeof last_path);
                char st[512];
                g_snprintf(st, sizeof st, "%s: %s", TR("已保存"), path);
                gtk_label_set_text(GTK_LABEL(status_label), st);
            } else {
                gtk_label_set_text(GTK_LABEL(status_label), err ? err->message : TR("保存失败"));
                g_clear_error(&err);
            }
            g_free(path);
        }
    }
    gtk_widget_destroy(dlg);
}

/* 复制到剪贴板 */
static void on_copy(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (!shot_pixbuf) return;
    GtkClipboard *cb = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    gtk_clipboard_set_image(cb, shot_pixbuf);
    gtk_label_set_text(GTK_LABEL(status_label), TR("已复制到剪贴板"));
}

/* 自动化: QYSHOT_AUTO=保存路径 启动后自动截图保存退出 */
static gboolean auto_shot(gpointer p) {
    (void)p;
    const char *path = g_getenv("QYSHOT_AUTO");
    if (shot_pixbuf) { g_object_unref(shot_pixbuf); shot_pixbuf = NULL; }
    shot_pixbuf = capture_screen();
    if (!shot_pixbuf) return G_SOURCE_REMOVE;
    GError *err = NULL;
    if (gdk_pixbuf_save(shot_pixbuf, path, "png", &err, NULL)) {
        g_printerr("QYSHOT_AUTO: saved %s\n", path);
        exit(0);
    } else {
        g_printerr("QYSHOT_AUTO: fail %s\n", err ? err->message : "?");
        g_clear_error(&err);
        exit(1);
    }
    return G_SOURCE_REMOVE;
}

static void activate(GtkApplication *app, gpointer ud) {
    (void)ud;
    qy_load_theme();
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元截图"));
    gtk_window_set_default_size(GTK_WINDOW(win), 640, 480);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_margin_start(vbox, 10);
    gtk_widget_set_margin_end(vbox, 10);
    gtk_widget_set_margin_top(vbox, 10);
    gtk_widget_set_margin_bottom(vbox, 10);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 预览区 */
    GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sw), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_set_min_content_height(GTK_SCROLLED_WINDOW(sw), 360);
    preview = gtk_image_new();
    gtk_container_add(GTK_CONTAINER(sw), preview);
    gtk_box_pack_start(GTK_BOX(vbox), sw, TRUE, TRUE, 0);

    /* 按钮行 */
    GtkWidget *bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *b_cap = gtk_button_new_with_label(TR("全屏截图"));
    qy_add_class(b_cap, "qy-btn");
    GtkWidget *b_save = gtk_button_new_with_label(TR("保存"));
    GtkWidget *b_copy = gtk_button_new_with_label(TR("复制到剪贴板"));
    g_signal_connect(b_cap, "clicked", G_CALLBACK(on_capture), NULL);
    g_signal_connect(b_save, "clicked", G_CALLBACK(on_save), NULL);
    g_signal_connect(b_copy, "clicked", G_CALLBACK(on_copy), NULL);
    gtk_box_pack_start(GTK_BOX(bar), b_cap, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(bar), b_save, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(bar), b_copy, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), bar, FALSE, FALSE, 0);

    /* 状态栏 */
    status_label = gtk_label_new(TR("就绪"));
    qy_add_class(status_label, "qy-mon-info");
    gtk_widget_set_halign(status_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 0);

    const char *auto_path = g_getenv("QYSHOT_AUTO");
    if (auto_path)
        g_timeout_add(800, auto_shot, NULL);

    gtk_widget_show_all(win);
    /* 启动后自动截一帧（X11 后端需窗口就绪后） */
    g_timeout_add(400, (GSourceFunc)on_capture_wrap, NULL);
}

/* 包装: 返回 FALSE 的一次性回调 */
static gboolean on_capture_wrap(gpointer p) {
    (void)p;
    on_capture(NULL, NULL);
    return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.shot", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    char *own_argv[2] = { argv[0], NULL };
    int rc = g_application_run(G_APPLICATION(app), 1, own_argv);
    g_object_unref(app);
    return rc;
}