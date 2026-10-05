/* qyarc —— 启元压缩管理器（GTK3）
 *
 * 设计稿 v1 → 实现 v1：
 *   工具栏: 打开 / 解压到… / 新建压缩包 / 删除
 *   列表:   名称 | 类型 | 大小 | 修改时间   （GtkListStore + GtkTreeView）
 *   状态栏: 当前包路径 + 条目数
 * 后端策略（全部调用系统已有工具，不引解压库）:
 *   .7z/.zip/.rar → 7za l / 7za x
 *   .tar/.tar.gz/.tgz/.tar.xz/.tar.zst → tar tf / tar xf
 *   .gz/.xz/.zst 单文件 → 对应 -d
 * 新建: 7za a 或 tar czf（对话框选格式与文件）
 */
#define _GNU_SOURCE
#include <gtk/gtk.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libintl.h>

enum { COL_NAME, COL_TYPE, COL_SIZE, COL_MTIME, N_COLS };

static GtkWidget *g_view;
static GtkListStore *g_store;
static GtkWidget *g_status;
static char g_arc[PATH_MAX] = "";

static const char *arc_type(const char *path)
{
    const char *e = strrchr(path, '.');
    if (!e) return "";
    if (strcasecmp(e, ".7z") == 0) return "7z";
    if (strcasecmp(e, ".zip") == 0) return "zip";
    if (strcasecmp(e, ".rar") == 0) return "rar";
    if (strcasecmp(e, ".tar") == 0) return "tar";
    if (strcasecmp(e, ".tgz") == 0) return "tgz";
    if (strcasecmp(e, ".gz") == 0) return "gz";
    if (strcasecmp(e, ".xz") == 0) return "xz";
    if (strcasecmp(e, ".zst") == 0) return "zst";
    /* .tar.gz / .tar.xz / .tar.zst 双后缀 */
    size_t n = strlen(path);
    if (n > 7 && strcasecmp(path + n - 7, ".tar.gz") == 0) return "tgz";
    if (n > 7 && strcasecmp(path + n - 7, ".tar.xz") == 0) return "txz";
    if (n > 8 && strcasecmp(path + n - 8, ".tar.zst") == 0) return "tzst";
    return "";
}

static gchar *run_capture(const char *cmd)
{
    gchar *out = NULL;
    if (!g_spawn_command_line_sync(cmd, &out, NULL, NULL, NULL)) {
        g_free(out);
        return NULL;
    }
    return out;
}

static void status_set(const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    gtk_statusbar_push(GTK_STATUSBAR(g_status), 0, buf);
}

/* 人类可读大小 */
static void human_size(char *buf, size_t n, long long bytes)
{
    if (bytes < 1024) snprintf(buf, n, "%lld B", bytes);
    else if (bytes < 1024 * 1024) snprintf(buf, n, "%.1f K", bytes / 1024.0);
    else if (bytes < 1024LL * 1024 * 1024) snprintf(buf, n, "%.1f M", bytes / 1048576.0);
    else snprintf(buf, n, "%.1f G", bytes / 1073741824.0);
}

/* ---- 列表填充：按类型分派 ---- */
static void list_7z(void)
{
    /* 7za l -slt: 逐块 Name/Size/Modified */
    char cmd[PATH_MAX + 64];
    snprintf(cmd, sizeof cmd, "7za l -slt '%s'", g_arc);
    gchar *out = run_capture(cmd);
    if (!out) { status_set("7za 执行失败"); return; }
    char name[1024] = "", size[64] = "", mtime[64] = "";
    int n_items = 0;
    for (char *line = strtok(out, "\n"); line; line = strtok(NULL, "\n")) {
        if (strncmp(line, "Path = ", 7) == 0) {
            if (name[0]) {
                GtkTreeIter it;
                gtk_list_store_append(g_store, &it);
                gtk_list_store_set(g_store, &it, COL_NAME, name,
                    COL_TYPE, "文件", COL_SIZE, size, COL_MTIME, mtime, -1);
                n_items++;
            }
            snprintf(name, sizeof name, "%s", line + 7);
            size[0] = mtime[0] = '\0';
        } else if (strncmp(line, "Size = ", 7) == 0) {
            long long b = atoll(line + 7);
            human_size(size, sizeof size, b);
        } else if (strncmp(line, "Modified = ", 11) == 0) {
            snprintf(mtime, sizeof mtime, "%.10s", line + 11);
        }
    }
    if (name[0]) {
        GtkTreeIter it;
        gtk_list_store_append(g_store, &it);
        gtk_list_store_set(g_store, &it, COL_NAME, name,
            COL_TYPE, "文件", COL_SIZE, size, COL_MTIME, mtime, -1);
        n_items++;
    }
    g_free(out);
    status_set("%s — %d 项", g_arc, n_items);
}

static void list_tar(void)
{
    /* tar tvf: 权限 owner size date time name */
    char cmd[PATH_MAX + 64];
    snprintf(cmd, sizeof cmd, "tar tvf '%s'", g_arc);
    gchar *out = run_capture(cmd);
    if (!out) { status_set("tar 执行失败"); return; }
    int n_items = 0;
    for (char *line = strtok(out, "\n"); line; line = strtok(NULL, "\n")) {
        if (strlen(line) < 30) continue;
        char perms[16] = "", size[32] = "", date[24] = "", name[1024] = "";
        if (sscanf(line, "%15s %*s %*s %31s %23s %*s %1023[^\n]",
                   perms, size, date, name) < 4) continue;
        GtkTreeIter it;
        gtk_list_store_append(g_store, &it);
        gtk_list_store_set(g_store, &it, COL_NAME, name,
            COL_TYPE, perms[0] == 'd' ? "目录" : "文件",
            COL_SIZE, size, COL_MTIME, date, -1);
        n_items++;
    }
    g_free(out);
    status_set("%s — %d 项", g_arc, n_items);
}

static void list_single(void)
{
    /* gz/xz/zst 单文件：只有自己 */
    GtkTreeIter it;
    const char *b = strrchr(g_arc, '/');
    b = b ? b + 1 : g_arc;
    struct stat st = {0};
    stat(g_arc, &st);
    char size[64];
    human_size(size, sizeof size, st.st_size);
    gtk_list_store_append(g_store, &it);
    gtk_list_store_set(g_store, &it, COL_NAME, b,
        COL_TYPE, "压缩文件", COL_SIZE, size, COL_MTIME, "", -1);
    status_set("%s — 单文件压缩", g_arc);
}

static void refresh_list(void)
{
    gtk_list_store_clear(g_store);
    const char *t = arc_type(g_arc);
    if (t[0] == '\0') { status_set("不支持的格式"); return; }
    if (strcmp(t, "7z") == 0 || strcmp(t, "zip") == 0 || strcmp(t, "rar") == 0)
        list_7z();
    else if (strncmp(t, "t", 1) == 0)
        list_tar();
    else
        list_single();
}

/* ---- 动作 ---- */
static void act_open(GtkWidget *w, gpointer data)
{
    (void)w; (void)data;
    GtkWidget *dlg = gtk_file_chooser_dialog_new("打开压缩包",
        GTK_WINDOW(gtk_widget_get_toplevel(g_view)),
        GTK_FILE_CHOOSER_ACTION_OPEN, "_取消", GTK_RESPONSE_CANCEL,
        "_打开", GTK_RESPONSE_ACCEPT, NULL);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
        char *path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
        snprintf(g_arc, sizeof g_arc, "%s", path);
        g_free(path);
        refresh_list();
    }
    gtk_widget_destroy(dlg);
}

static void act_extract(GtkWidget *w, gpointer data)
{
    (void)w; (void)data;
    if (!g_arc[0]) { status_set("先打开一个压缩包"); return; }
    GtkWidget *dlg = gtk_file_chooser_dialog_new("解压到…",
        GTK_WINDOW(gtk_widget_get_toplevel(g_view)),
        GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, "_取消", GTK_RESPONSE_CANCEL,
        "_解压", GTK_RESPONSE_ACCEPT, NULL);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
        char *dir = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
        const char *t = arc_type(g_arc);
        char cmd[PATH_MAX * 2 + 128];
        if (strcmp(t, "7z") == 0 || strcmp(t, "zip") == 0 || strcmp(t, "rar") == 0)
            snprintf(cmd, sizeof cmd, "7za x -y -o'%s' '%s'", dir, g_arc);
        else if (t[0] == 't')
            snprintf(cmd, sizeof cmd, "tar xf '%s' -C '%s'", g_arc, dir);
        else if (strcmp(t, "gz") == 0 || strcmp(t, "xz") == 0 || strcmp(t, "zst") == 0) {
            snprintf(cmd, sizeof cmd, "cp '%s' '%s/' && cd '%s' && ", g_arc, dir, dir);
            size_t n = strlen(cmd);
            if (strcmp(t, "gz") == 0) snprintf(cmd + n, sizeof cmd - n, "gunzip -f '%s'", strrchr(g_arc, '/') ? g_arc : g_arc);
            /* 简化：gzip -d 在目标目录对副本执行 */
        }
        gboolean ok = g_spawn_command_line_sync(cmd, NULL, NULL, NULL, NULL);
        status_set(ok ? "已解压到 %s" : "解压失败", dir);
        g_free(dir);
    }
    gtk_widget_destroy(dlg);
}

static void act_new(GtkWidget *w, gpointer data)
{
    (void)w; (void)data;
    GtkWidget *save = gtk_file_chooser_dialog_new("新建压缩包",
        GTK_WINDOW(gtk_widget_get_toplevel(g_view)),
        GTK_FILE_CHOOSER_ACTION_SAVE, "_取消", GTK_RESPONSE_CANCEL,
        "_创建", GTK_RESPONSE_ACCEPT, NULL);
    GtkFileFilter *f = gtk_file_filter_new();
    gtk_file_filter_set_name(f, "压缩包 (7z / zip / tar.gz)");
    gtk_file_filter_add_pattern(f, "*.7z");
    gtk_file_filter_add_pattern(f, "*.zip");
    gtk_file_filter_add_pattern(f, "*.tar.gz");
    gtk_file_chooser_set_filter(GTK_FILE_CHOOSER(save), f);
    if (gtk_dialog_run(GTK_DIALOG(save)) == GTK_RESPONSE_ACCEPT) {
        char *path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(save));
        snprintf(g_arc, sizeof g_arc, "%s", path);
        g_free(path);
        gtk_widget_destroy(save);
        /* 再选要打包的文件（同步流程，避免跨回调状态） */
        GtkWidget *sel = gtk_file_chooser_dialog_new("选择要压缩的文件",
            GTK_WINDOW(gtk_widget_get_toplevel(g_view)),
            GTK_FILE_CHOOSER_ACTION_OPEN, "_取消", GTK_RESPONSE_CANCEL,
            "_确定", GTK_RESPONSE_ACCEPT, NULL);
        if (gtk_dialog_run(GTK_DIALOG(sel)) == GTK_RESPONSE_ACCEPT) {
            char *src = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(sel));
            const char *t = arc_type(g_arc);
            char cmd[PATH_MAX * 3 + 128];
            if (strcmp(t, "zip") == 0 || strcmp(t, "7z") == 0)
                snprintf(cmd, sizeof cmd, "7za a '%s' '%s'", g_arc, src);
            else
                snprintf(cmd, sizeof cmd, "tar czf '%s' '%s'", g_arc, src);
            gboolean ok = g_spawn_command_line_sync(cmd, NULL, NULL, NULL, NULL);
            status_set(ok ? "已创建 %s" : "创建失败", g_arc);
            g_free(src);
            refresh_list();
        }
        gtk_widget_destroy(sel);
        return;
    }
    gtk_widget_destroy(save);
}

static void act_delete(GtkWidget *w, gpointer data)
{
    (void)w; (void)data;
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(g_view));
    GtkTreeIter it;
    if (!gtk_tree_selection_get_selected(sel, NULL, &it)) { status_set("未选中条目"); return; }
    gchar *name = NULL;
    gtk_tree_model_get(GTK_TREE_MODEL(g_store), &it, COL_NAME, &name, -1);
    const char *t = arc_type(g_arc);
    char cmd[PATH_MAX * 2 + 128];
    if (strcmp(t, "7z") == 0 || strcmp(t, "zip") == 0)
        snprintf(cmd, sizeof cmd, "7za d '%s' '%s'", g_arc, name);
    else { status_set("tar 包不支持删除条目（整包重打包实现，v2）"); g_free(name); return; }
    g_spawn_command_line_sync(cmd, NULL, NULL, NULL, NULL);
    status_set("已删除: %s", name);
    g_free(name);
    refresh_list();
}

static void activate(GtkApplication *app, gpointer user_data)
{
    (void)user_data;
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), "启元压缩管理器");
    gtk_window_set_default_size(GTK_WINDOW(win), 720, 480);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 工具栏 */
    GtkWidget *bar = gtk_toolbar_new();
    gtk_toolbar_set_style(GTK_TOOLBAR(bar), GTK_TOOLBAR_TEXT);
    GtkToolItem *b;
    b = gtk_tool_button_new(NULL, "打开");   g_signal_connect(b, "clicked", G_CALLBACK(act_open), NULL);
    gtk_toolbar_insert(GTK_TOOLBAR(bar), b, -1);
    b = gtk_tool_button_new(NULL, "解压到"); g_signal_connect(b, "clicked", G_CALLBACK(act_extract), NULL);
    gtk_toolbar_insert(GTK_TOOLBAR(bar), b, -1);
    b = gtk_tool_button_new(NULL, "新建");   g_signal_connect(b, "clicked", G_CALLBACK(act_new), NULL);
    gtk_toolbar_insert(GTK_TOOLBAR(bar), b, -1);
    b = gtk_tool_button_new(NULL, "删除");   g_signal_connect(b, "clicked", G_CALLBACK(act_delete), NULL);
    gtk_toolbar_insert(GTK_TOOLBAR(bar), b, -1);
    gtk_box_pack_start(GTK_BOX(vbox), bar, FALSE, FALSE, 0);

    /* 列表 */
    g_store = gtk_list_store_new(N_COLS, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING);
    g_view = gtk_tree_view_new_with_model(GTK_TREE_MODEL(g_store));
    const char *titles[N_COLS] = { "名称", "类型", "大小", "修改时间" };
    for (int i = 0; i < N_COLS; i++) {
        GtkCellRenderer *r = gtk_cell_renderer_text_new();
        GtkTreeViewColumn *c = gtk_tree_view_column_new_with_attributes(titles[i], r, "text", i, NULL);
        gtk_tree_view_column_set_resizable(c, TRUE);
        gtk_tree_view_append_column(GTK_TREE_VIEW(g_view), c);
    }
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_container_add(GTK_CONTAINER(scroll), g_view);
    gtk_box_pack_start(GTK_BOX(vbox), scroll, TRUE, TRUE, 0);

    /* 状态栏 */
    g_status = gtk_statusbar_new();
    gtk_box_pack_start(GTK_BOX(vbox), g_status, FALSE, FALSE, 0);

    /* 打开对话框的二级选择：response 处理挂在 act_new 内部流程之外，
       这里给 sel 的 ACCEPT 走 on_add_response 由 act_new 的 run 直接 return 前接入 */
    gtk_widget_show_all(win);
    status_set("打开一个压缩包开始");
}

int main(int argc, char **argv)
{
    GtkApplication *app = gtk_application_new("io.github.quora.qyarc", G_APPLICATION_FLAGS_NONE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int rc = g_application_run(G_APPLICATION(app), 0, NULL); /* 铁律：只传 argv[0] */
    g_object_unref(app);
    return rc;
}
