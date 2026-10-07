/* qyview — 启元图片查看器 v1
 * 数据源: GdkPixbuf (PNG/JPEG/BMP 等), cairo 缩放绘制
 * 功能: 打开单图 (argv[1]), 窗口自适应缩放, 滚轮缩放, 拖拽平移, 左右键切换同目录图片
 * 架构: 单文件 GTK3, 与 qyfiles 同款编译方式
 */
#include <gtk/gtk.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <string.h>
#include <glib/gstdio.h>
#include "qytheme.h"

static GdkPixbuf *pix = NULL;          /* 原始图 */
static gchar *cur_dir = NULL;          /* 当前图所在目录 */
static GPtrArray *dir_files = NULL;    /* 同目录图片文件列表 */
static int dir_idx = -1;
static double zoom = 1.0;
static double pan_x = 0, pan_y = 0;

static const char *IMG_EXT[] = {".png",".jpg",".jpeg",".bmp",".gif",".webp",".xpm", NULL};

static gboolean is_img(const char *name) {
    gchar *low = g_ascii_strdown(name, -1);
    gboolean ok = FALSE;
    for (int i = 0; IMG_EXT[i]; i++)
        if (g_str_has_suffix(low, IMG_EXT[i])) { ok = TRUE; break; }
    g_free(low);
    return ok;
}

static void scan_dir(const char *path) {
    if (!dir_files) dir_files = g_ptr_array_new_with_free_func(g_free);
    g_ptr_array_set_size(dir_files, 0);
    dir_idx = -1;
    gchar *dir = g_path_get_dirname(path);
    gchar *base = g_path_get_basename(path);
    GDir *d = g_dir_open(dir, 0, NULL);
    if (d) {
        const gchar *n;
        while ((n = g_dir_read_name(d)))
            if (is_img(n)) {
                g_ptr_array_add(dir_files, g_strdup(n));
                if (!strcmp(n, base)) dir_idx = dir_files->len - 1;
            }
        g_dir_close(d);
    }
    g_free(dir); g_free(base);
}

static gboolean load_path(const char *path) {
    GError *err = NULL;
    GdkPixbuf *p = gdk_pixbuf_new_from_file(path, &err);
    if (!p) {
        g_printerr("qyview: %s\n", err ? err->message : "load failed");
        if (err) g_error_free(err);
        return FALSE;
    }
    if (pix) g_object_unref(pix);
    pix = p;
    zoom = 1.0; pan_x = pan_y = 0;
    return TRUE;
}

static void load_by_index(GtkWidget *da, int idx) {
    if (idx < 0 || idx >= (int)dir_files->len) return;
    gchar *full = g_build_filename(cur_dir, (gchar*)dir_files->pdata[idx], NULL);
    if (load_path(full)) {
        dir_idx = idx;
        gtk_widget_queue_draw(da);
    }
    g_free(full);
}

static gboolean on_draw(GtkWidget *da, cairo_t *cr, gpointer ud) {
    GtkAllocation a; gtk_widget_get_allocation(da, &a);
    cairo_set_source_rgb(cr, 0.1, 0.1, 0.12);
    cairo_paint(cr);
    if (!pix) return FALSE;
    int iw = gdk_pixbuf_get_width(pix), ih = gdk_pixbuf_get_height(pix);
    double fit = 1.0;
    if (iw && ih) fit = 1.0;
    double z = zoom * fit;
    double dw = iw * z, dh = ih * z;
    /* 居中 + 平移 */
    double ox = (a.width - dw) / 2.0 + pan_x;
    double oy = (a.height - dh) / 2.0 + pan_y;
    cairo_set_source_rgb(cr, 0.2, 0.2, 0.22);
    cairo_rectangle(cr, ox - 1, oy - 1, dw + 2, dh + 2);
    cairo_fill(cr);
    cairo_save(cr);
    cairo_translate(cr, ox, oy);
    cairo_scale(cr, z, z);
    gdk_cairo_set_source_pixbuf(cr, pix, 0, 0);
    cairo_paint(cr);
    cairo_restore(cr);
    return FALSE;
}

static gboolean on_scroll(GtkWidget *w, GdkEventScroll *ev, gpointer ud) {
    if (ev->direction == GDK_SCROLL_UP) zoom *= 1.15;
    else if (ev->direction == GDK_SCROLL_DOWN) zoom /= 1.15;
    if (zoom < 0.05) zoom = 0.05;
    if (zoom > 20) zoom = 20;
    gtk_widget_queue_draw(w);
    return TRUE;
}

static gboolean on_key(GtkWidget *w, GdkEventKey *ev, gpointer ud) {
    if (!dir_files || dir_files->len == 0) return FALSE;
    if (ev->keyval == GDK_KEY_Right) {
        int n = (dir_idx + 1) % (int)dir_files->len;
        load_by_index(GTK_WIDGET(ud), n);
    } else if (ev->keyval == GDK_KEY_Left) {
        int n = (dir_idx - 1 + (int)dir_files->len) % (int)dir_files->len;
        load_by_index(GTK_WIDGET(ud), n);
    } else if (ev->keyval == GDK_KEY_0) {
        zoom = 1.0; pan_x = pan_y = 0; gtk_widget_queue_draw(w);
    }
    return FALSE;
}

static gboolean on_button(GtkWidget *w, GdkEventButton *ev, gpointer ud) {
    /* 双击还原 */
    if (ev->type == GDK_2BUTTON_PRESS && ev->button == 1) {
        zoom = 1.0; pan_x = pan_y = 0; gtk_widget_queue_draw(w);
    }
    return FALSE;
}

static void activate(GtkApplication *app, gpointer ud) {
    qy_load_theme();
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), "启元图片查看器");
    gtk_window_set_default_size(GTK_WINDOW(win), 700, 500);
    GtkWidget *da = gtk_drawing_area_new();
    gtk_container_add(GTK_CONTAINER(win), da);
    g_signal_connect(da, "draw", G_CALLBACK(on_draw), NULL);
    g_signal_connect(da, "scroll-event", G_CALLBACK(on_scroll), NULL);
    g_signal_connect(da, "key-press-event", G_CALLBACK(on_key), da);
    g_signal_connect(da, "button-press-event", G_CALLBACK(on_button), NULL);
    gtk_widget_add_events(da, GDK_SCROLL_MASK | GDK_BUTTON_PRESS_MASK | GDK_KEY_PRESS_MASK);
    gtk_widget_set_can_focus(da, TRUE);
    gtk_widget_show_all(win);

    gchar **args = (gchar**)ud;
    if (args && args[0]) {
        if (load_path(args[0])) {
            scan_dir(args[0]);
            g_free(cur_dir);
            cur_dir = g_path_get_dirname(args[0]);
        }
    }
    gtk_widget_grab_focus(da);
}

int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.qiyuan.view", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), argv + 1);
    char *own_argv[2] = { argv[0], NULL };
    int rc = g_application_run(G_APPLICATION(app), 1, own_argv);
    g_object_unref(app);
    return rc;
}