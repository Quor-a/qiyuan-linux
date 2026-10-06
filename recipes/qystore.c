/* qystore — 启元软件中心 (v1.9.5)
 * GTK3 GUI: 浏览 /usr/share/qyrepo/index.json (147 包离线仓库)
 * 搜索过滤 / 已装标记 (/var/lib/qypkg/installed/) / 安装·卸载按钮 (qysudo -n)
 */
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "qyl10n.h"

#define REPO_INDEX "/usr/share/qyrepo/index.json"
#define REPO_DIR   "/usr/share/qyrepo/pkgs"
#define INST_DIR   "/var/lib/qypkg/installed"

enum { C_NAME, C_VER, C_SIZE, C_STATUS, C_FILE, C_N };

static GtkListStore *store;
static GtkWidget *info_label;
static GtkWidget *btn_act;
static char g_file[512] = "", g_name[128] = "", g_status[32] = "";

static int is_installed(const char *name) {
    char p[300];
    snprintf(p, sizeof p, INST_DIR "/%s", name);
    return access(p, F_OK) == 0;
}

static char *slurp(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *b = malloc(n + 1);
    if (!b || fread(b, 1, n, f) != (size_t)n) { fclose(f); free(b); return NULL; }
    b[n] = 0;
    fclose(f);
    if (len) *len = n;
    return b;
}

static void human_size(long v, char *out, size_t n) {
    if (v >= 1048576) snprintf(out, n, "%.1f MB", v / 1048576.0);
    else if (v >= 1024) snprintf(out, n, "%ld KB", v / 1024);
    else snprintf(out, n, "%ld B", v);
}

static void load_repo(const char *filter) {
    gtk_list_store_clear(store);
    size_t len = 0;
    char *js = slurp(REPO_INDEX, &len);
    if (!js) {
        gtk_list_store_insert_with_values(store, NULL, -1,
            C_NAME, TR("仓库缺失"), C_FILE, "", -1);
        return;
    }
    /* index.json: {"packagesTR(":[{...}]} 或 [...] — 找 ")filename" 条目逐包扫 */
    const char *p = js;
    while ((p = strstr(p, "\"filename\""))) {
        const char *q = strchr(p, ':');
        while (q && *q != '"') q++;
        if (!q) break;
        q++;
        char file[256]; size_t i = 0;
        while (*q && *q != '"' && i + 1 < sizeof file) file[i++] = *q++;
        file[i] = 0;
        p = q;
        /* 向前找本条目的 name/version/size: 在 filename 之前 600 字节窗口内 */
        const char *win_start = p - 600 < js ? js : p - 600;
        char name[128] = "", ver[64] = "";
        /* 简易: 在窗口内找最后一个 "name":"..." */
        const char *w = win_start, *last = NULL;
        while (w && w < p) {
            w = strstr(w, "\"name\"");
            if (w && w < p) { last = w; w += 6; }
        }
        if (last) {
            const char *k = strchr(last, ':');
            while (k && *k != '"') k++;
            if (k) { k++; size_t j = 0; while (*k && *k != '"' && j + 1 < sizeof name) name[j++] = *k++; }
        }
        last = NULL; w = win_start;
        while (w && w < p) {
            w = strstr(w, "\"version\"");
            if (w && w < p) { last = w; w += 9; }
        }
        if (last) {
            const char *k = strchr(last, ':');
            while (k && *k != '"') k++;
            if (k) { k++; size_t j = 0; while (*k && *k != '"' && j + 1 < sizeof ver) ver[j++] = *k++; }
        }
        long size = 0;
        w = win_start;
        while (w && w < p) {
            w = strstr(w, "\"size\"");
            if (w && w < p) { size = strtol(strchr(w, ':') + 1, NULL, 10); w += 6; }
        }
        if (!name[0] || (filter && filter[0] && !strstr(name, filter))) continue;
        char sz[32], status[64];
        human_size(size, sz, sizeof sz);
        snprintf(status, sizeof status, "%s", is_installed(name) ? TR("✓ 已安装") : TR("可安装"));
        gtk_list_store_insert_with_values(store, NULL, -1,
            C_NAME, name, C_VER, ver, C_SIZE, sz, C_STATUS, status,
            C_FILE, file, -1);
    }
    free(js);
}

static void refresh_row_status(void) {
    /* 重载仓库以刷新已装标记 */
    const gchar *f = NULL;
    load_repo(f);
}

static void on_row_activated(GtkTreeView *tv, GtkTreePath *path,
                             GtkTreeViewColumn *col, gpointer ud) {
    (void)tv; (void)col; (void)ud;
    GtkTreeIter it;
    GtkTreeModel *m = gtk_tree_view_get_model(tv);
    if (!gtk_tree_model_get_iter(m, &it, path)) return;
    gchar *name = NULL, *file = NULL, *ver = NULL;
    gtk_tree_model_get(m, &it, C_NAME, &name, C_VER, &ver, C_FILE, &file, -1);
    snprintf(g_name, sizeof g_name, "%s", name ? name : "");
    snprintf(g_file, sizeof g_file, "%s", file ? file : "");
    snprintf(g_status, sizeof g_status, "%s", is_installed(g_name) ? "installed" : "available");
    char txt[512];
    snprintf(txt, sizeof txt, "%s-%s\n%s", g_name, ver ? ver : "",
             g_status[0] == 'i' ? TR("已安装，可卸载") : TR("未安装，可安装"));
    gtk_label_set_text(GTK_LABEL(info_label), txt);
    gtk_button_set_label(GTK_BUTTON(btn_act),
        g_status[0] == 'i' ? TR("卸载") : TR("安装"));
    g_free(name); g_free(ver); g_free(file);
}

static void append_log(const char *msg) {
    char txt[1024];
    snprintf(txt, sizeof txt, "%s\n%s", gtk_label_get_text(GTK_LABEL(info_label)), msg);
    gtk_label_set_text(GTK_LABEL(info_label), txt);
}

static void on_act(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (!g_file[0]) return;
    char cmd[1024];
    int rc;
    if (g_status[0] == 'i') {
        snprintf(cmd, sizeof cmd, "qysudo -n /usr/bin/qypkg-inst -r %s", g_name);
    } else {
        snprintf(cmd, sizeof cmd, "qysudo -n /usr/bin/qypkg-inst '%s'/%s", REPO_DIR, g_file);
    }
    append_log(TR("执行中…"));
    while (gtk_events_pending()) gtk_main_iteration();
    rc = system(cmd);
    char msg[128];
    snprintf(msg, sizeof msg, rc == 0 ? TR("完成 ✓") : TR("失败 (rc=%d)"), rc);
    append_log(msg);
    snprintf(g_status, sizeof g_status, "%s", is_installed(g_name) ? "installed" : "available");
    gtk_button_set_label(GTK_BUTTON(btn_act), g_status[0] == 'i' ? TR("卸载") : TR("安装"));
    refresh_row_status();
}

static void on_search(GtkSearchEntry *e, gpointer ud) {
    (void)ud;
    load_repo(gtk_entry_get_text(GTK_ENTRY(e)));
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元软件中心"));
    gtk_window_set_default_size(GTK_WINDOW(win), 640, 480);
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    GtkWidget *search = gtk_search_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(search), TR("搜索软件包…"));
    g_signal_connect(search, "search-changed", G_CALLBACK(on_search), NULL);
    gtk_box_pack_start(GTK_BOX(vbox), search, FALSE, FALSE, 0);

    store = gtk_list_store_new(C_N, G_TYPE_STRING, G_TYPE_STRING,
                               G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING);
    GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
    gtk_widget_set_vexpand(sw, TRUE);
    GtkTreeView *tv = GTK_TREE_VIEW(gtk_tree_view_new_with_model(GTK_TREE_MODEL(store)));
    const char *titles[C_FILE] = { TR("名称"), TR("版本"), TR("大小"), TR("状态") };
    for (int c = 0; c < C_FILE; c++) {
        GtkCellRenderer *r = gtk_cell_renderer_text_new();
        GtkTreeViewColumn *col = gtk_tree_view_column_new_with_attributes(
            titles[c], r, "text", c, NULL);
        gtk_tree_view_append_column(tv, col);
    }
    gtk_tree_view_set_headers_visible(tv, TRUE);
    g_signal_connect(tv, "row-activated", G_CALLBACK(on_row_activated), NULL);
    gtk_container_add(GTK_CONTAINER(sw), GTK_WIDGET(tv));
    gtk_box_pack_start(GTK_BOX(vbox), sw, TRUE, TRUE, 0);

    info_label = gtk_label_new(TR("选择一个软件包"));
    gtk_label_set_xalign(GTK_LABEL(info_label), 0.0);
    gtk_box_pack_start(GTK_BOX(vbox), info_label, FALSE, FALSE, 0);

    btn_act = gtk_button_new_with_label(TR("安装"));
    g_signal_connect(btn_act, "clicked", G_CALLBACK(on_act), NULL);
    gtk_box_pack_start(GTK_BOX(vbox), btn_act, FALSE, FALSE, 0);

    load_repo(NULL);
    gtk_widget_show_all(win);
    gtk_main();
    return 0;
}
