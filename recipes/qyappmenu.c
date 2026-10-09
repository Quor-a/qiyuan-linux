/* qyappmenu - 启元开始菜单 (ArcMenu 风格: 搜索+固定网格+常用列表+用户区) */
#include "qyl10n.h"
#include <gtk/gtk.h>
#include <gdk/gdkkeysyms.h>
#include <string.h>

typedef struct {
    const char *name;
    const char *icon;
    const char *color;      /* 图标底色 (统一主题色板) */
    const char *cmdline;
    int launches;          /* 常用排序 */
    const char *cat;       /* 分类: 系统/文件/工具 */
} AppEntry;

/* 统一图标主题色板 (v1.7): 每应用固定主色 */
static AppEntry apps[] = {
    { "系统设置",   "⚙",  "#6b7280", "qysettings",      0, "系统" },
    { "系统监视",   "▦", "#f59e0b", "qymon",           0, "系统" },
    { "系统安装",   "⬇", "#f97316", "qysetup",         0, "系统" },
    { "用户管理",   "☻", "#0ea5e9", "qyusers",         0, "系统" },
    { "网络管理",   "⇄", "#22c55e", "qynet",           0, "系统" },
    { "文件管理器", "▤", "#3b82f6", "qyfiles",         0, "文件" },
    { "图片查看",   "▣", "#8b5cf6", "qyview",          0, "文件" },
    { "压缩管理",   "▣", "#ef4444", "qyarc",           0, "文件" },
    { "回收站",     "🗑", "#6b7280", "qyfiles --trash", 0, "文件" },
    { "终端",       ">_", "#334155", "weston-terminal", 0, "工具" },
    { "文本编辑",   "✎", "#10b981", "qyedit",          0, "工具" },
    { "软件中心",   "▦", "#0a7ea4", "qystore",         0, "工具" },
    { "浏览器",     "🌐", "#60a5fa", "qybrowser",       0, "工具" },
    { "截图工具",   "📷", "#f472b6", "qyshot",          0, "工具" },
    { "剪贴板",     "📋", "#f59e0b", "qyclip",          0, "工具" },
    { "锁屏",       "🔒", "#94a3b8", "qylock",          0, "系统" },
    { "全局搜索",   "🔍", "#22d3ee", "qysearch",        0, "系统" },
    { "音乐播放器", "🎵", "#ec4899", "qymedia",         0, "娱乐" },
    { "窗口切换器", "⇥", "#a78bfa", "qyswitcher",     0, "系统" },
    { "驱动管理器", "💾", "#64748b", "qydriver",       0, "系统" },
    { "Git 工具",   "⎇", "#f97316", "qygit",           0, "工具" },
    { "欢迎",       "👋", "#22c55e", "qywelcome",      0, "系统" },
};
#define NAPPS ((int)(sizeof apps / sizeof apps[0]))

static GtkWidget *menu_win = NULL;
static GtkWidget *grid_box = NULL;    /* 固定应用网格容器 */
static GtkWidget *freq_box = NULL;    /* 常用列表容器 */
static GtkWidget *freq_title = NULL;  /* 常用标题(空时隐藏) */
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

/* ---------- 主题 ---------- */
static void load_theme(void) {
    GtkCssProvider *p = gtk_css_provider_new();
    if (gtk_css_provider_load_from_path(p, "/usr/share/themes/qiyuan/gtk-3.0/gtk.css", NULL)) {
        gtk_style_context_add_provider_for_screen(
            gdk_screen_get_default(), GTK_STYLE_PROVIDER(p),
            GTK_STYLE_PROVIDER_PRIORITY_USER);
    }
    g_object_unref(p);
}

static void add_class(GtkWidget *w, const char *cls) {
    gtk_style_context_add_class(gtk_widget_get_style_context(w), cls);
}

/* ---------- 常用列表持久化: ~/.config/qiyuan/appmenu-freq ---------- */
#define FREQ_FILE ".config/qiyuan/appmenu-freq"

static char *freq_path(void) {
    return g_build_filename(g_get_home_dir(), FREQ_FILE, NULL);
}

static void freq_save(void) {
    char *dir = g_build_filename(g_get_home_dir(), ".config/qiyuan", NULL);
    g_mkdir_with_parents(dir, 0700);
    g_free(dir);
    char *path = freq_path();
    FILE *f = fopen(path, "w");
    if (f) {
        for (int i = 0; i < NAPPS; i++)
            if (apps[i].launches > 0)
                fprintf(f, "%s %d\n", apps[i].name, apps[i].launches);
        fclose(f);
    }
    g_free(path);
}

static void freq_load(void) {
    char *path = freq_path();
    FILE *f = fopen(path, "r");
    if (f) {
        char name[96];
        int n;
        while (fscanf(f, "%95s %d", name, &n) == 2) {
            for (int i = 0; i < NAPPS; i++)
                if (strcmp(apps[i].name, name) == 0)
                    apps[i].launches = n;
        }
        fclose(f);
    }
    g_free(path);
}

/* ---------- 固定区: 图标网格 (4 列) ---------- */
static void on_icon_click(GtkButton *btn, gpointer ud) {
    AppEntry *a = (AppEntry *)ud;
    a->launches++;
    freq_save();
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
    GtkWidget *lb = gtk_label_new(TR(a->name));
    gtk_label_set_max_width_chars(GTK_LABEL(lb), 8);
    gtk_label_set_line_wrap(GTK_LABEL(lb), TRUE);
    gtk_label_set_justify(GTK_LABEL(lb), GTK_JUSTIFY_CENTER);
    add_class(lb, "qy-appmenu-icon-label");
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
    freq_save();
    launch_cmd(a->cmdline);
    gtk_widget_hide(menu_win);
}

static GtkWidget *make_freq_row(AppEntry *a) {
    GtkWidget *h = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *b = gtk_button_new();
    gtk_button_set_relief(GTK_BUTTON(b), GTK_RELIEF_NONE);
    GtkWidget *ic = gtk_label_new(a->icon);
    GtkWidget *lb = gtk_label_new(TR(a->name));
    gtk_widget_set_halign(lb, GTK_ALIGN_START);
    add_class(lb, "qy-appmenu-freq-label");
    gtk_container_add(GTK_CONTAINER(b), h);
    gtk_box_pack_start(GTK_BOX(h), ic, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(h), lb, TRUE, TRUE, 0);
    g_signal_connect(b, "clicked", G_CALLBACK(on_row_click), a);
    return b;
}

/* ---------- 搜索匹配: 中文名 + 英文名（大小写不敏感） ---------- */
static gboolean app_matches(const AppEntry *a, const char *q) {
    if (!q || !q[0]) return TRUE;
    if (strstr(a->name, q)) return TRUE;
    const char *en = TR(a->name);
    if (en && strstr(en, q)) return TRUE;
    if (en) {
        size_t ql = strlen(q);
        for (const char *p = en; *p; p++) {
            if (g_ascii_tolower(*p) == g_ascii_tolower(q[0]) &&
                g_ascii_strncasecmp(p, q, ql) == 0)
                return TRUE;
        }
    }
    return FALSE;
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
    static const char *cats[] = { "系统", "文件", "工具" };
    for (int ci = 0; ci < 3; ci++) {
        int col = 0;
        GtkWidget *cur_row = NULL;
        gboolean cat_any = FALSE;
        for (int i = 0; i < NAPPS; i++) {
            if (strcmp(apps[i].cat, cats[ci]) != 0) continue;
            if (filtered && !app_matches(&apps[i], q)) continue;
            if (!cat_any) {
                GtkWidget *catlb = gtk_label_new(NULL);
                gtk_label_set_markup(GTK_LABEL(catlb), g_strdup_printf("<b>%s</b>", TR(cats[ci])));
                gtk_widget_set_halign(catlb, GTK_ALIGN_START);
                add_class(catlb, "qy-appmenu-cat");
                gtk_box_pack_start(GTK_BOX(grid_box), catlb, FALSE, FALSE, 0);
                cat_any = TRUE;
                any = TRUE;
            }
            if (col == 0) {
                cur_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
                gtk_box_pack_start(GTK_BOX(grid_box), cur_row, FALSE, FALSE, 0);
            }
            gtk_box_pack_start(GTK_BOX(cur_row), make_grid_icon(&apps[i]), TRUE, TRUE, 2);
            col = (col + 1) % 4;
        }
    }
    if (!any) {
        gtk_box_pack_start(GTK_BOX(grid_box), gtk_label_new(TR("无匹配应用")), FALSE, FALSE, 4);
    }

    /* Frequent: launches > 0 的按次数排 */
    AppEntry *sorted[NAPPS];
    for (int i = 0; i < NAPPS; i++) sorted[i] = &apps[i];
    for (int i = 0; i < NAPPS; i++)
        for (int j = i + 1; j < NAPPS; j++)
            if (sorted[j]->launches > sorted[i]->launches) {
                AppEntry *t = sorted[i]; sorted[i] = sorted[j]; sorted[j] = t;
            }
    int col = 0; GtkWidget *cur_row = NULL;
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
    gtk_widget_set_visible(freq_title, shown > 0);
    gtk_widget_grab_focus(search_entry);   /* 打开即聚焦搜索框 */
}

static void on_search_changed(GtkEditable *e, gpointer ud) {
    rebuild(TRUE);
}

/* 回车启动第一个匹配应用 */
static void on_search_activate(GtkEntry *e, gpointer ud) {
    const char *q = gtk_entry_get_text(e);
    if (!q || !q[0]) return;
    for (int i = 0; i < NAPPS; i++) {
        if (app_matches(&apps[i], q)) {
            apps[i].launches++;
            freq_save();
            launch_cmd(apps[i].cmdline);
            gtk_widget_hide(menu_win);
            return;
        }
    }
}

/* ---------- 电源按钮 ---------- */
static void on_power(GtkButton *b, gpointer ud) {
    launch_cmd("busybox poweroff");
}

static void on_settings_btn(GtkButton *b, gpointer ud) {
    launch_cmd("qysettings");
    gtk_widget_hide(menu_win);
}

static void on_close_clicked(GtkButton *b, gpointer ud) {
    gtk_widget_hide(menu_win);
}

static gboolean on_menu_keypress(GtkWidget *w, GdkEventKey *ev, gpointer ud) {
    if (ev->keyval == GDK_KEY_Escape) {
        gtk_widget_hide(menu_win);
        return TRUE;
    }
    return FALSE;
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    load_theme();

    menu_win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_decorated(GTK_WINDOW(menu_win), FALSE);
    gtk_window_set_default_size(GTK_WINDOW(menu_win), 460, 420);
    gtk_window_move(GTK_WINDOW(menu_win), 6, 32);
    g_signal_connect(menu_win, "key-press-event", G_CALLBACK(on_menu_keypress), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 10);
    gtk_container_add(GTK_CONTAINER(menu_win), vbox);

    /* 1. 搜索框 + 关闭按钮 */
    GtkWidget *search_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    search_entry = gtk_search_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(search_entry), TR("搜索应用..."));
    g_signal_connect(search_entry, "search-changed", G_CALLBACK(on_search_changed), NULL);
    g_signal_connect(search_entry, "activate", G_CALLBACK(on_search_activate), NULL);
    gtk_box_pack_start(GTK_BOX(search_row), search_entry, TRUE, TRUE, 0);
    GtkWidget *close_btn = gtk_button_new_with_label("✕");
    gtk_button_set_relief(GTK_BUTTON(close_btn), GTK_RELIEF_NONE);
    add_class(close_btn, "qy-appmenu-close");
    g_signal_connect(close_btn, "clicked", G_CALLBACK(on_close_clicked), NULL);
    gtk_box_pack_start(GTK_BOX(search_row), close_btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), search_row, FALSE, FALSE, 0);

    /* 2. Pinned 固定应用 */
    GtkWidget *pl = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(pl), g_strdup_printf("<b>%s</b>", TR("固定")));
    gtk_widget_set_halign(pl, GTK_ALIGN_START);
    add_class(pl, "qy-appmenu-title");
    gtk_box_pack_start(GTK_BOX(vbox), pl, FALSE, FALSE, 0);
    grid_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_box_pack_start(GTK_BOX(vbox), grid_box, FALSE, FALSE, 0);

    /* 3. Frequent 常用 */
    GtkWidget *fl = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(fl), g_strdup_printf("<b>%s</b>", TR("常用")));
    gtk_widget_set_halign(fl, GTK_ALIGN_START);
    add_class(fl, "qy-appmenu-title");
    freq_title = fl;
    gtk_box_pack_start(GTK_BOX(vbox), fl, FALSE, FALSE, 0);
    freq_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 3);
    gtk_box_pack_start(GTK_BOX(vbox), freq_box, FALSE, FALSE, 0);

    /* 4. 底部用户区 */
    gtk_box_pack_start(GTK_BOX(vbox), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), FALSE, FALSE, 2);
    GtkWidget *bottom = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *user = gtk_label_new("● root");
    gtk_widget_set_halign(user, GTK_ALIGN_START);
    add_class(user, "qy-appmenu-user");
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
    freq_load();      /* 载入历史常用计数 */
    rebuild(FALSE);
    gtk_main();
    return 0;
}
