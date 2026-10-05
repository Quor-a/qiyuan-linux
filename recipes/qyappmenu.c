/* qyappmenu - 启元开始菜单 (ArcMenu 风格: 搜索+固定网格+常用列表+用户区) */
#include <gtk/gtk.h>
#include <string.h>

typedef struct {
    const char *name;
    const char *icon;
    const char *color;      /* 图标底色 (统一主题色板) */
    const char *cmdline;
    int launches;          /* 常用排序 */
} AppEntry;

/* 统一图标主题色板 (v1.7): 每应用固定主色 */
static AppEntry apps[] = {
    { "文件管理器", "▤", "#3b82f6", "qyfiles",         0 },
    { "终端",       ">_", "#334155", "weston-terminal", 0 },
    { "系统设置",   "⚙",  "#6b7280", "qysettings",      0 },
    { "文本编辑",   "✎", "#10b981", "qyedit",          0 },
    { "系统监视",   "▦", "#f59e0b", "qymon",           0 },
    { "图片查看",   "▣", "#8b5cf6", "qyview",          0 },
    { "压缩管理",   "▣", "#ef4444", "qyarc",           0 },
    { "系统安装",   "⬇", "#f97316", "qysetup",         0 },
    { "计算器",     "∑", "#06b6d4", "qysettings",      0 },
};
#define NAPPS ((int)(sizeof apps / sizeof apps[0]))

static GtkWidget *menu_win = NULL;
static GtkWidget *grid_box = NULL;    /* 固定应用网格容器 */
static GtkWidget *freq_box = NULL;    /* 常用列表容器 */
static GtkWidget *search_entry = NULL;

/* ---------- 启动 ---------- */
static void launch_cmd(const char *cmd) {
    GError *err = NULL;
    gchar **argv = NULL;
    if (!g_shell_parse_argv(cmd, NULL, &argv, &err)) { if (err) g_error_free(err); return; }
    g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &err);
    if (err) { g_printerr("launch: %s\n", err->message); g_error_free(err); }
    g_strfreev(argv);
}

/* ---------- 固定区: 图标网格 (4 列) ---------- */
static void on_icon_click(GtkButton *btn, gpointer ud) {
    AppEntry *a = (AppEntry *)ud;
    a->launches++;
    launch_cmd(a->cmdline);
    gtk_widget_hide(menu_win);
}

/* 圆角矩形绘制 (cairo) — 统一图标底 */
static gboolean icon_draw_cb(GtkWidget *w, cairo_t *cr, gpointer ud) {
    AppEntry *a = (AppEntry *)ud;
    GtkAllocation al;
    gtk_widget_get_allocation(w, &al);
    GdkRGBA c;
    gdk_rgba_parse(&c, a->color);
    double r = 10.0, wdt = al.width, h = al.height;
    cairo_new_sub_path(cr);
    cairo_arc(cr, wdt-r, r, r, -G_PI/2, 0);
    cairo_arc(cr, wdt-r, h-r, r, 0, G_PI/2);
    cairo_arc(cr, r, h-r, r, G_PI/2, G_PI);
    cairo_arc(cr, r, r, r, G_PI, 3*G_PI/2);
    cairo_close_path(cr);
    cairo_set_source_rgb(cr, c.red, c.green, c.blue);
    cairo_fill(cr);
    /* 白色字符居中 */
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_select_font_face(cr, "sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, h * 0.48);
    cairo_text_extents_t te;
    cairo_text_extents(cr, a->icon, &te);
    cairo_move_to(cr, (wdt - te.width)/2 - te.x_bearing, (h - te.height)/2 - te.y_bearing);
    cairo_show_text(cr, a->icon);
    return FALSE;
}

static GtkWidget *make_grid_icon(AppEntry *a) {
    GtkWidget *v = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    GtkWidget *btn = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
    /* 图标画布: 56x56 圆角色块 */
    GtkWidget *ic = gtk_drawing_area_new();
    gtk_widget_set_size_request(ic, 56, 56);
    g_signal_connect(ic, "draw", G_CALLBACK(icon_draw_cb), a);
    GtkWidget *lb = gtk_label_new(a->name);
    gtk_label_set_max_width_chars(GTK_LABEL(lb), 8);
    gtk_label_set_line_wrap(GTK_LABEL(lb), TRUE);
    gtk_label_set_justify(GTK_LABEL(lb), GTK_JUSTIFY_CENTER);
    gtk_widget_override_color(lb, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){0.15,0.15,0.18,1});
    gtk_container_add(GTK_CONTAINER(btn), v);
    gtk_box_pack_start(GTK_BOX(v), ic, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v), lb, FALSE, FALSE, 0);
    g_signal_connect(btn, "clicked", G_CALLBACK(on_icon_click), a);
    return btn;
}

/* ---------- 常用区: 双列小列表 ---------- */
static void on_row_click(GtkButton *btn, gpointer ud) {
    AppEntry *a = (AppEntry *)ud;
    a->launches++;
    launch_cmd(a->cmdline);
    gtk_widget_hide(menu_win);
}

static GtkWidget *make_freq_row(AppEntry *a) {
    GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *b = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
    GtkWidget *ic = gtk_label_new(a->icon);
    GtkWidget *lb = gtk_label_new(a->name);
    gtk_widget_set_halign(lb, GTK_ALIGN_START);
    gtk_widget_override_color(lb, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){0.88,0.88,0.92,1});
    gtk_container_add(GTK_CONTAINER(b), h);
    gtk_box_pack_start(GTK_BOX(h), ic, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(h), lb, TRUE, TRUE, 0);
    g_signal_connect(b, "clicked", G_CALLBACK(on_row_click), a);
    return b;
}

/* ---------- 刷新 (按搜索过滤 + 按启动次数排序常用区) ---------- */
static void rebuild(gboolean filtered) {
    const char *q = gtk_entry_get_text(GTK_ENTRY(search_entry));
    GList *ch;

    ch = gtk_container_get_children(GTK_CONTAINER(grid_box));
    for (GList *it = ch; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(ch);
    ch = gtk_container_get_children(GTK_CONTAINER(freq_box));
    for (GList *it = ch; it; it = it->next) gtk_widget_destroy(GTK_WIDGET(it->data));
    g_list_free(ch);

    gboolean any = FALSE;
    GtkWidget *cur_row = NULL;
    int col = 0;
    for (int i = 0; i < NAPPS; i++) {
        if (filtered && q[0] && !strstr(apps[i].name, q)) continue;
        any = TRUE;
        if (col == 0) {
            cur_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
            gtk_box_pack_start(GTK_BOX(grid_box), cur_row, FALSE, FALSE, 0);
        }
        gtk_box_pack_start(GTK_BOX(cur_row), make_grid_icon(&apps[i]), TRUE, TRUE, 2);
        col = (col + 1) % 4;
    }
    if (!any) {
        gtk_box_pack_start(GTK_BOX(grid_box), gtk_label_new("无匹配应用"), FALSE, FALSE, 4);
    }

    /* Frequent: launches > 0 的按次数排 */
    AppEntry *sorted[NAPPS];
    for (int i = 0; i < NAPPS; i++) sorted[i] = &apps[i];
    for (int i = 0; i < NAPPS; i++)
        for (int j = i + 1; j < NAPPS; j++)
            if (sorted[j]->launches > sorted[i]->launches) {
                AppEntry *t = sorted[i]; sorted[i] = sorted[j]; sorted[j] = t;
            }
    col = 0; cur_row = NULL;
    int shown = 0;
    for (int i = 0; i < NAPPS && shown < 6; i++) {
        if (sorted[i]->launches == 0) break;
        if (col == 0) {
            cur_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
            gtk_box_pack_start(GTK_BOX(freq_box), cur_row, FALSE, FALSE, 0);
        }
        gtk_box_pack_start(GTK_BOX(cur_row), make_freq_row(sorted[i]), TRUE, TRUE, 0);
        col = (col + 1) % 2;
        shown++;
    }
    gtk_widget_show_all(menu_win);
}

static void on_search_changed(GtkEditable *e, gpointer ud) {
    rebuild(TRUE);
}

/* ---------- 电源按钮 ---------- */
static void on_power(GtkButton *b, gpointer ud) {
    system("poweroff -f");
}

static void on_settings_btn(GtkButton *b, gpointer ud) {
    launch_cmd("qysettings");
    gtk_widget_hide(menu_win);
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);

    menu_win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_decorated(GTK_WINDOW(menu_win), FALSE);
    gtk_window_set_default_size(GTK_WINDOW(menu_win), 460, 420);
    gtk_window_move(GTK_WINDOW(menu_win), 6, 32);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 10);
    gtk_container_add(GTK_CONTAINER(menu_win), vbox);

    /* 1. 搜索框 */
    search_entry = gtk_search_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(search_entry), "搜索应用...");
    g_signal_connect(search_entry, "search-changed", G_CALLBACK(on_search_changed), NULL);
    gtk_box_pack_start(GTK_BOX(vbox), search_entry, FALSE, FALSE, 0);

    /* 2. Pinned 固定应用 */
    GtkWidget *pl = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(pl), "<b>固 定</b>");
    gtk_widget_set_halign(pl, GTK_ALIGN_START);
    gtk_widget_override_color(pl, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){0.95,0.95,0.95,1});
    gtk_box_pack_start(GTK_BOX(vbox), pl, FALSE, FALSE, 0);
    grid_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_box_pack_start(GTK_BOX(vbox), grid_box, FALSE, FALSE, 0);

    /* 3. Frequent 常用 */
    GtkWidget *fl = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(fl), "<b>常 用</b>");
    gtk_widget_set_halign(fl, GTK_ALIGN_START);
    gtk_widget_override_color(fl, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){0.95,0.95,0.95,1});
    gtk_box_pack_start(GTK_BOX(vbox), fl, FALSE, FALSE, 0);
    freq_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 3);
    gtk_box_pack_start(GTK_BOX(vbox), freq_box, FALSE, FALSE, 0);

    /* 4. 底部用户区 */
    gtk_box_pack_start(GTK_BOX(vbox), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 2);
    GtkWidget *bottom = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *user = gtk_label_new("● root");
    gtk_widget_set_halign(user, GTK_ALIGN_START);
    gtk_widget_override_color(user, GTK_STATE_FLAG_NORMAL, &(GdkRGBA){0.9,0.9,0.9,1});
    gtk_box_pack_start(GTK_BOX(bottom), user, TRUE, TRUE, 0);
    GtkWidget *set_btn = gtk_button_new_with_label("⚙");
    gtk_button_set_relief(GTK_BUTTON(set_btn), GTK_RELIEF_NONE);
    g_signal_connect(set_btn, "clicked", G_CALLBACK(on_settings_btn), NULL);
    gtk_box_pack_start(GTK_BOX(bottom), set_btn, FALSE, FALSE, 0);
    GtkWidget *pwr_btn = gtk_button_new_with_label("⏻");
    gtk_button_set_relief(GTK_BUTTON(pwr_btn), GTK_RELIEF_NONE);
    g_signal_connect(pwr_btn, "clicked", G_CALLBACK(on_power), NULL);
    gtk_box_pack_start(GTK_BOX(bottom), pwr_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), bottom, FALSE, FALSE, 0);

    g_printerr("QYAPPMENU-START toplevel\n");
    rebuild(FALSE);
    gtk_main();
    return 0;
}
