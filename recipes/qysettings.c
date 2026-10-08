/* qysettings - 启元系统设置 (GTK3) */
#include "qyl10n.h"
#include "qytheme.h"
#include <gtk/gtk.h>
#include <sys/utsname.h>
#include <sys/sysinfo.h>
#include <unistd.h>
#include <time.h>
#include <dirent.h>

/* ---------- 语言页回调 ---------- */
/* 同步 weston 顶栏时钟格式（顶栏由 weston 补丁渲染，读 weston.ini 的
   clock-format-string，不经 qyl10n）：en → %m/%d %H:%M，zh → %m月%d日 %H:%M */
static void write_weston_clock(const char *fmt) {
    const char *ini = "/etc/xdg/weston/weston.ini";
    gchar *buf = NULL; gsize len = 0;
    if (!g_file_get_contents(ini, &buf, &len, NULL)) return;
    GString *s = g_string_new(NULL);
    gchar **lines = g_strsplit(buf, "\n", -1);
    gboolean replaced = FALSE;
    for (int i = 0; lines[i]; i++) {
        if (g_str_has_prefix(lines[i], "clock-format-string=")) {
            g_string_append_printf(s, "clock-format-string=%s\n", fmt);
            replaced = TRUE;
        } else {
            g_string_append(s, lines[i]);
            g_string_append_c(s, '\n');
        }
    }
    if (!replaced)
        g_string_append_printf(s, "[shell]\nclock-format-string=%s\n", fmt);
    g_file_set_contents(ini, s->str, (gssize)s->len, NULL);
    g_string_free(s, TRUE);
    g_strfreev(lines);
    g_free(buf);
}

static void on_lang_zh(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    FILE *f = fopen("/etc/qylang", "w");
    if (f) { fputs("zh", f); fclose(f); }
    write_weston_clock("%m月%d日 %H:%M");
}
static void on_lang_en(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    FILE *f = fopen("/etc/qylang", "w");
    if (f) { fputs("en", f); fclose(f); }
    write_weston_clock("%m/%d %H:%M");
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
    return g_strdup(TR("未知"));
}

static gchar *read_cpu_model(void) {
    FILE *f = fopen("/proc/cpuinfo", "r");
    if (!f) return g_strdup(TR("未知"));
    gchar *line = NULL;
    size_t cap = 0;
    ssize_t n;
    gchar *model = g_strdup(TR("未知"));
    while ((n = getline(&line, &cap, f)) != -1) {
        if (g_str_has_prefix(line, "model name")) {
            char *v = strchr(line, ':');
            if (v) {
                v++;
                while (*v == ' ' || *v == '\t') v++;
                char *p = strchr(v, '\n');
                if (p) *p = 0;
                g_free(model);
                model = g_strdup(v);
            }
            break;
        }
    }
    g_free(line);
    fclose(f);
    return model;
}

static gchar *read_uptime(void) {
    FILE *f = fopen("/proc/uptime", "r");
    if (!f) return g_strdup("--");
    double up = 0;
    fscanf(f, "%lf", &up);
    fclose(f);
    int d = (int)up;
    return g_strdup_printf("%d%s %02d:%02d:%02d", d / 86400, TR("天"),
                            (d % 86400) / 3600, (d % 3600) / 60, d % 60);
}

static gchar *read_load(void) {
    FILE *f = fopen("/proc/loadavg", "r");
    if (!f) return g_strdup("--");
    double l1 = 0, l5 = 0, l15 = 0;
    fscanf(f, "%lf %lf %lf", &l1, &l5, &l15);
    fclose(f);
    return g_strdup_printf("%.2f  %.2f  %.2f", l1, l5, l15);
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

/* 从设置启动其他应用 */
static void launch_app(GtkButton *b, gpointer cmd) {
    char buf[128];
    g_snprintf(buf, sizeof buf, "%s &", (const char *)cmd);
    g_spawn_command_line_async(buf, NULL);
}

/* 应用桌面分辨率: 改写 /etc/xdg/weston/weston.ini 的 mode= */
static void on_res_apply(GtkWidget *w, gpointer ud) {
    (void)w;
    GtkWidget *combo = GTK_WIDGET(ud);
    const char *sel = gtk_combo_box_text_get_active_text(GTK_COMBO_BOX_TEXT(combo));
    if (!sel || !*sel) return;
    const char *path = "/etc/xdg/weston/weston.ini";
    gchar *content = NULL;
    if (!g_file_get_contents(path, &content, NULL, NULL)) return;
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "mode=", 5) == 0) {
            g_string_append_printf(out, "mode=%s", sel);
            if (nl) g_string_append_c(out, '\n');
            replaced = 1;
        } else {
            g_string_append_len(out, line, len);
            if (nl) g_string_append_c(out, '\n');
        }
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "\n[output]\nname=Virtual-1\nmode=%s\n", sel);
    g_file_set_contents(path, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

/* 自动化验证: QY_SETTINGS_RES=N 启动后自动应用分辨率 */
static gboolean auto_res_apply(gpointer p) {
    on_res_apply(NULL, p);
    return G_SOURCE_REMOVE;
}

/* ---------- 电源: 熄屏时间 ---------- */
static const int idle_secs[] = { 0, 60, 300, 600, 1800, 3600 };

static void on_idle_apply(GtkWidget *w, gpointer ud) {
    (void)w;
    int idx = GPOINTER_TO_INT(ud);
    int secs = idle_secs[idx];
    const char *path = "/etc/xdg/weston/weston.ini";
    gchar *content = NULL;
    if (!g_file_get_contents(path, &content, NULL, NULL)) return;
    GString *out = g_string_new(NULL);
    char *line = content;
    int in_core = 0, replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        char line2[256];
        snprintf(line2, sizeof line2, "%.*s", (int)len, line);
        int is_core = strncmp(line2, "[core]", 6) == 0;
        if (is_core) {
            g_string_append_printf(out, "%s\nidle-time=%d", line2, secs);
            replaced = 1;
        } else if (in_core && strncmp(line2, "idle-time=", 11) == 0) {
            g_string_append_printf(out, "idle-time=%d", secs);
            replaced = 1;
        } else {
            g_string_append_len(out, line, len);
        }
        if (nl) g_string_append_c(out, '\n');
        in_core = is_core;
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    g_file_set_contents(path, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

/* 自动化验证: QY_SETTINGS_IDLE=N 秒启动后自动应用 */
static gboolean auto_idle_apply(gpointer p) {
    on_idle_apply(NULL, p);
    return G_SOURCE_REMOVE;
}

/* ---------- 隐私: 应用权限开关 ---------- */
#define PERM_CONF "/etc/qyperm.conf"
static int g_perm_loading = 0;

static const char *perm_read(const char *key, const char *def) {
    static char val[16];
    snprintf(val, sizeof val, "%s", def);
    FILE *f = fopen(PERM_CONF, "r");
    if (f) {
        char line[128];
        while (fgets(line, sizeof line, f)) {
            char *nl = strchr(line, '\n');
            if (nl) *nl = 0;
            char *eq = strchr(line, '=');
            if (eq && strncmp(line, key, strlen(key)) == 0 &&
                eq - line == (long)strlen(key)) {
                snprintf(val, sizeof val, "%s", eq + 1);
            }
        }
        fclose(f);
    }
    return val;
}

static void perm_write(const char *key, int on) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(PERM_CONF, &content, &len, NULL); /* 不存在则 content=NULL */
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    size_t klen = strlen(key);
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
            g_string_append_printf(out, "%s=%s", key, on ? "on" : "off");
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "%s=%s\n", key, on ? "on" : "off");
    g_file_set_contents(PERM_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_perm_toggled(GtkWidget *sw, gpointer ud) {
    if (g_perm_loading) return;
    const char *key = (const char *)ud;
    perm_write(key, gtk_switch_get_active(GTK_SWITCH(sw)));
}

/* 自动化验证: QY_SETTINGS_PERM=camera:off 启动后关闭对应开关 */
static gboolean auto_perm_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_PERM");
    if (env) {
        char key[64] = "", mode[16] = "";
        if (sscanf(env, "%63[^:]:%15s", key, mode) == 2) {
            perm_write(key, strcmp(mode, "off") != 0);
        }
    }
    return G_SOURCE_REMOVE;
}

/* ---------- HD Color: HDR + 颜色配置 ---------- */
#define HDR_CONF "/etc/qyhdr.conf"
static int g_hdr_loading = 0;
static GtkWidget *g_hdr_combo = NULL;

static void hdr_write(const char *key, const char *val) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(HDR_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    size_t klen = strlen(key);
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
            g_string_append_printf(out, "%s=%s", key, val);
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "%s=%s\n", key, val);
    g_file_set_contents(HDR_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_hdr_toggled(GtkWidget *sw, gpointer ud) {
    if (g_hdr_loading) return;
    (void)ud;
    hdr_write("hdr", gtk_switch_get_active(GTK_SWITCH(sw)) ? "on" : "off");
}

static void on_hdr_profile_apply(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    const char *profiles[] = { "srgb", "p3", "vivid" };
    int act = gtk_combo_box_get_active(GTK_COMBO_BOX(g_hdr_combo));
    if (act < 0) act = 0;
    if (act > 2) act = 2;
    hdr_write("profile", profiles[act]);
}

/* 自动化验证: QY_SETTINGS_HDR=off 启动后关闭 */
static gboolean auto_hdr_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_HDR");
    if (env) hdr_write("hdr", strcmp(env, "off") == 0 ? "off" : "on");
    return G_SOURCE_REMOVE;
}

/* ---------- 投影: 模式写 /etc/qyproject.conf ---------- */
#define PROJECT_CONF "/etc/qyproject.conf"
static GtkWidget *g_proj_combo = NULL;

static void on_project_apply(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    const char *modes[] = { "pc_only", "mirror", "extend", "second_only" };
    int act = gtk_combo_box_get_active(GTK_COMBO_BOX(g_proj_combo));
    if (act < 0) act = 0;
    if (act > 3) act = 3;
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(PROJECT_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "mode=", 5) == 0) {
            g_string_append_printf(out, "mode=%s", modes[act]);
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "mode=%s\n", modes[act]);
    g_file_set_contents(PROJECT_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

/* 自动化验证: QY_SETTINGS_PROJECT=mode:extend 启动后写入 */
static gboolean auto_project_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_PROJECT");
    if (env && strstr(env, "mode:")) {
        const char *mode = strstr(env, "mode:") + 5;
        gchar *content = NULL;
        gsize len = 0;
        g_file_get_contents(PROJECT_CONF, &content, &len, NULL);
        GString *out = g_string_new(NULL);
        if (content) g_string_append(out, content);
        g_free(content);
        if (strstr(out->str, "mode=")) {
            GString *tmp = g_string_new(NULL);
            char *line = out->str;
            while (line && *line) {
                char *nl = strchr(line, '\n');
                size_t llen = nl ? (size_t)(nl - line) : strlen(line);
                if (strncmp(line, "mode=", 5) == 0)
                    g_string_append_printf(tmp, "mode=%s", mode);
                else
                    g_string_append_len(tmp, line, llen);
                if (nl) g_string_append_c(tmp, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_string_free(out, TRUE);
            out = tmp;
        } else {
            g_string_append_printf(out, "mode=%s\n", mode);
        }
        g_file_set_contents(PROJECT_CONF, out->str, out->len, NULL);
        g_string_free(out, TRUE);
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 远程桌面: 开关写 /etc/qyremotedesktop.conf ---------- */
#define RDP_CONF "/etc/qyremotedesktop.conf"
static int g_rdp_loading = 0;

static void rdp_write(int on) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(RDP_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "rdp=", 4) == 0) {
            g_string_append_printf(out, "rdp=%s", on ? "on" : "off");
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "rdp=%s\n", on ? "on" : "off");
    g_file_set_contents(RDP_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_rdp_toggled(GtkWidget *sw, gpointer ud) {
    if (g_rdp_loading) return;
    (void)ud;
    rdp_write(gtk_switch_get_active(GTK_SWITCH(sw)));
}

/* 自动化验证: QY_SETTINGS_RDP=off 启动后关闭 */
static gboolean auto_rdp_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_RDP");
    if (env) rdp_write(strcmp(env, "off") == 0 ? 0 : 1);
    return G_SOURCE_REMOVE;
}

/* ---------- 图形: 模式写 /etc/qygraphics.conf ---------- */
#define GRAPHICS_CONF "/etc/qygraphics.conf"
static GtkWidget *g_gfx_combo = NULL;

static void on_graphics_apply(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    const char *mode = "default";
    int act = gtk_combo_box_get_active(GTK_COMBO_BOX(g_gfx_combo));
    if (act == 1) mode = "performance";
    else if (act == 2) mode = "power_saver";
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(GRAPHICS_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "mode=", 5) == 0) {
            g_string_append_printf(out, "mode=%s", mode);
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "mode=%s\n", mode);
    g_file_set_contents(GRAPHICS_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

/* 自动化验证: QY_SETTINGS_GRAPHICS=mode:performance 启动后写入 */
static gboolean auto_graphics_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_GRAPHICS");
    if (env && strstr(env, "mode:")) {
        const char *mode = strstr(env, "mode:") + 5;
        gchar *content = NULL;
        gsize len = 0;
        g_file_get_contents(GRAPHICS_CONF, &content, &len, NULL);
        GString *out = g_string_new(NULL);
        if (content) g_string_append(out, content);
        g_free(content);
        if (strstr(out->str, "mode=")) {
            GString *tmp = g_string_new(NULL);
            char *line = out->str;
            while (line && *line) {
                char *nl = strchr(line, '\n');
                size_t llen = nl ? (size_t)(nl - line) : strlen(line);
                if (strncmp(line, "mode=", 5) == 0)
                    g_string_append_printf(tmp, "mode=%s", mode);
                else
                    g_string_append_len(tmp, line, llen);
                if (nl) g_string_append_c(tmp, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_string_free(out, TRUE);
            out = tmp;
        } else {
            g_string_append_printf(out, "mode=%s\n", mode);
        }
        g_file_set_contents(GRAPHICS_CONF, out->str, out->len, NULL);
        g_string_free(out, TRUE);
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 触摸板: 开关+灵敏度 ---------- */
#define TOUCHPAD_CONF "/etc/qytouchpad.conf"
static int g_tp_loading = 0;
static GtkWidget *g_tp_scale = NULL;

static void touchpad_write(const char *key, const char *val) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(TOUCHPAD_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    size_t klen = strlen(key);
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
            g_string_append_printf(out, "%s=%s", key, val);
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "%s=%s\n", key, val);
    g_file_set_contents(TOUCHPAD_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_touchpad_toggled(GtkWidget *sw, gpointer ud) {
    if (g_tp_loading) return;
    (void)ud;
    touchpad_write("touchpad", gtk_switch_get_active(GTK_SWITCH(sw)) ? "on" : "off");
}

static void on_touchpad_apply(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    int v = (int)gtk_range_get_value(GTK_RANGE(g_tp_scale));
    gchar *s = g_strdup_printf("%d", v);
    touchpad_write("sensitivity", s);
    g_free(s);
}

/* 自动化验证: QY_SETTINGS_TOUCHPAD=off 启动后关闭 */
static gboolean auto_touchpad_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_TOUCHPAD");
    if (env) touchpad_write("touchpad", strcmp(env, "off") == 0 ? "off" : "on");
    return G_SOURCE_REMOVE;
}

/* ---------- 蓝牙: 开关写 /etc/qybluetooth.conf ---------- */
#define BT_CONF "/etc/qybluetooth.conf"
static int g_bt_loading = 0;

static void bt_write(int on) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(BT_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "bluetooth=", 11) == 0) {
            g_string_append_printf(out, "bluetooth=%s", on ? "on" : "off");
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "bluetooth=%s\n", on ? "on" : "off");
    g_file_set_contents(BT_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_bt_toggled(GtkWidget *sw, gpointer ud) {
    if (g_bt_loading) return;
    (void)ud;
    bt_write(gtk_switch_get_active(GTK_SWITCH(sw)));
}

/* 自动化验证: QY_SETTINGS_BT=off 启动后关闭 */
static gboolean auto_bt_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_BT");
    if (env) bt_write(strcmp(env, "off") == 0 ? 0 : 1);
    return G_SOURCE_REMOVE;
}

/* ---------- 多显示器: 布局写 /etc/qydisplay.conf ---------- */
#define DISPLAY_CONF "/etc/qydisplay.conf"
static GtkWidget *g_disp_combo = NULL;

static void on_display_apply(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    const char *layout = gtk_combo_box_get_active(GTK_COMBO_BOX(g_disp_combo)) == 1 ? "mirror" : "extend";
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(DISPLAY_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "layout=", 8) == 0) {
            g_string_append_printf(out, "layout=%s", layout);
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "layout=%s\n", layout);
    g_file_set_contents(DISPLAY_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

/* 自动化验证: QY_SETTINGS_DISPLAY=layout:mirror 启动后写入 */
static gboolean auto_display_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_DISPLAY");
    if (env && strstr(env, "layout:mirror")) {
        gchar *content = NULL;
        gsize len = 0;
        g_file_get_contents(DISPLAY_CONF, &content, &len, NULL);
        GString *out = g_string_new(NULL);
        if (content) g_string_append(out, content);
        g_free(content);
        if (strstr(out->str, "layout=")) {
            GString *tmp = g_string_new(NULL);
            char *line = out->str;
            while (line && *line) {
                char *nl = strchr(line, '\n');
                size_t llen = nl ? (size_t)(nl - line) : strlen(line);
                if (strncmp(line, "layout=", 8) == 0)
                    g_string_append(tmp, "layout=mirror");
                else
                    g_string_append_len(tmp, line, llen);
                if (nl) g_string_append_c(tmp, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_string_free(out, TRUE);
            out = tmp;
        } else {
            g_string_append(out, "layout=mirror\n");
        }
        g_file_set_contents(DISPLAY_CONF, out->str, out->len, NULL);
        g_string_free(out, TRUE);
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 网络重置: 记录日志 ---------- */
static void on_net_reset(GtkWidget *w, gpointer ud) {
    (void)ud;
    GDateTime *dt = g_date_time_new_now_local();
    gchar *ts = g_date_time_format(dt, "%Y-%m-%d %H:%M:%S");
    gchar *log = g_strdup_printf("network reset at %s\n", ts);
    g_file_set_contents("/etc/qynetreset.log", log, -1, NULL);
    g_free(log);
    g_date_time_unref(dt);
    if (w) {
        GtkWidget *dlg = gtk_message_dialog_new(
            GTK_WINDOW(gtk_widget_get_toplevel(w)),
            GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_OK,
            "%s", TR("网络已重置"));
        gtk_dialog_run(GTK_DIALOG(dlg));
        gtk_widget_destroy(dlg);
    }
}

/* 自动化验证: QY_SETTINGS_NETRESET=1 启动后重置 */
static gboolean auto_net_reset(gpointer p) {
    on_net_reset(NULL, p);
    return G_SOURCE_REMOVE;
}

/* ---------- 鼠标: 设置写 /etc/qymouse.conf ---------- */
#define MOUSE_CONF "/etc/qymouse.conf"
static GtkWidget *g_mouse_combo = NULL;
static GtkWidget *g_mouse_scale = NULL;
static GtkWidget *g_mouse_spin = NULL;

static void mouse_write(const char *key, const char *val) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(MOUSE_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    size_t klen = strlen(key);
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
            g_string_append_printf(out, "%s=%s", key, val);
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "%s=%s\n", key, val);
    g_file_set_contents(MOUSE_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_mouse_apply(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    const char *primary = gtk_combo_box_get_active(GTK_COMBO_BOX(g_mouse_combo)) == 1 ? "right" : "left";
    mouse_write("primary", primary);
    int speed = (int)gtk_range_get_value(GTK_RANGE(g_mouse_scale));
    gchar *spd = g_strdup_printf("%d", speed);
    mouse_write("double_speed", spd);
    g_free(spd);
    int lines = gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(g_mouse_spin));
    gchar *lins = g_strdup_printf("%d", lines);
    mouse_write("scroll_lines", lins);
    g_free(lins);
}

/* 自动化验证: QY_SETTINGS_MOUSE=primary:right 启动后写入 */
static gboolean auto_mouse_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_MOUSE");
    if (env) {
        char key[64] = "", mode[32] = "";
        if (sscanf(env, "%63[^:]:%31s", key, mode) == 2)
            mouse_write(key, mode);
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 自动播放: 配置 ---------- */
#define AUTOPLAY_CONF "/etc/qyautoplay.conf"
static int g_autoplay_loading = 0;

static void autoplay_write(const char *key, const char *val) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(AUTOPLAY_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    size_t klen = strlen(key);
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
            g_string_append_printf(out, "%s=%s", key, val);
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "%s=%s\n", key, val);
    g_file_set_contents(AUTOPLAY_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_autoplay_toggled(GtkWidget *sw, gpointer ud) {
    if (g_autoplay_loading) return;
    (void)ud;
    autoplay_write("autoplay", gtk_switch_get_active(GTK_SWITCH(sw)) ? "on" : "off");
}

static void on_autoplay_action(GtkWidget *w, gpointer ud) {
    (void)w;
    const char *val = (const char *)ud;
    autoplay_write("action", val);
}

/* 自动化验证: QY_SETTINGS_AUTOPLAY=off 启动后关闭 */
static gboolean auto_autoplay_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_AUTOPLAY");
    if (env) {
        autoplay_write("autoplay", strcmp(env, "off") == 0 ? "off" : "on");
        autoplay_write("action", strcmp(env, "none") == 0 ? "none" : "open");
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 多任务: 开关 ---------- */
#define MULTI_CONF "/etc/qymultitask.conf"
static int g_multi_loading = 0;

static void multi_write(const char *key, int on) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(MULTI_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    size_t klen = strlen(key);
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
            g_string_append_printf(out, "%s=%s", key, on ? "on" : "off");
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "%s=%s\n", key, on ? "on" : "off");
    g_file_set_contents(MULTI_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_multi_toggled(GtkWidget *sw, gpointer ud) {
    if (g_multi_loading) return;
    const char *key = (const char *)ud;
    multi_write(key, gtk_switch_get_active(GTK_SWITCH(sw)));
}

/* 自动化验证: QY_SETTINGS_MULTI=snap:off 启动后写入 */
static gboolean auto_multi_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_MULTI");
    if (env) {
        char key[64] = "", mode[16] = "";
        if (sscanf(env, "%63[^:]:%15s", key, mode) == 2)
            multi_write(key, strcmp(mode, "off") != 0);
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 代理: 写入 /etc/environment ---------- */
#define ENV_CONF "/etc/environment"

static void proxy_write_env(const char *key, const char *value) {
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(ENV_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    size_t klen = strlen(key);
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, key, klen) == 0) {
            g_string_append_printf(out, "%s=%s", key, value);
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "%s=%s\n", key, value);
    g_file_set_contents(ENV_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

static void on_proxy_apply(GtkWidget *w, gpointer ud) {
    (void)w;
    const char *url = (const char *)ud;
    if (!url || !*url) return;
    proxy_write_env("http_proxy", url);
    proxy_write_env("https_proxy", url);
    proxy_write_env("HTTP_PROXY", url);
    proxy_write_env("HTTPS_PROXY", url);
}

/* 自动化验证: QY_SETTINGS_PROXY=http://host:port 启动后写入 */
static gboolean auto_proxy_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_PROXY");
    if (env) {
        proxy_write_env("http_proxy", env);
        proxy_write_env("https_proxy", env);
        proxy_write_env("HTTP_PROXY", env);
        proxy_write_env("HTTPS_PROXY", env);
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 防火墙: 开关 ---------- */
#define FIREWALL_CONF "/etc/qyfirewall.conf"

static void on_firewall_toggled(GtkWidget *sw, gpointer ud) {
    (void)ud;
    int on = gtk_switch_get_active(GTK_SWITCH(sw));
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(FIREWALL_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "firewall=", 10) == 0) {
            g_string_append_printf(out, "firewall=%s", on ? "on" : "off");
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "firewall=%s\n", on ? "on" : "off");
    g_file_set_contents(FIREWALL_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

/* 自动化验证: QY_SETTINGS_FIREWALL=on 启动后开启 */
static gboolean auto_firewall_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_FIREWALL");
    if (env) {
        gchar *content = NULL;
        gsize len = 0;
        g_file_get_contents(FIREWALL_CONF, &content, &len, NULL);
        GString *out = g_string_new(NULL);
        if (content) g_string_append(out, content);
        g_free(content);
        if (strstr(out->str, "firewall=")) {
            GString *tmp = g_string_new(NULL);
            char *line = out->str;
            while (line && *line) {
                char *nl = strchr(line, '\n');
                size_t llen = nl ? (size_t)(nl - line) : strlen(line);
                if (strncmp(line, "firewall=", 10) == 0)
                    g_string_append_printf(tmp, "firewall=%s", strcmp(env, "on") == 0 ? "on" : "off");
                else
                    g_string_append_len(tmp, line, llen);
                if (nl) g_string_append_c(tmp, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_string_free(out, TRUE);
            out = tmp;
        } else {
            g_string_append_printf(out, "firewall=%s\n", strcmp(env, "on") == 0 ? "on" : "off");
        }
        g_file_set_contents(FIREWALL_CONF, out->str, out->len, NULL);
        g_string_free(out, TRUE);
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 通知: 应用通知开关 ---------- */
#define NOTIF_CONF "/etc/qynotif.conf"
static int g_notif_loading = 0;

static void on_notif_toggled(GtkWidget *sw, gpointer ud) {
    if (g_notif_loading) return;
    const char *app = (const char *)ud;
    int on = gtk_switch_get_active(GTK_SWITCH(sw));
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(NOTIF_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    size_t klen = strlen(app);
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, app, klen) == 0 && line[klen] == '=') {
            g_string_append_printf(out, "%s=%s", app, on ? "on" : "off");
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "%s=%s\n", app, on ? "on" : "off");
    g_file_set_contents(NOTIF_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

/* 自动化验证: QY_SETTINGS_NOTIF=qymon:off 启动后关闭对应应用通知 */
static gboolean auto_notif_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_NOTIF");
    if (env) {
        char app[64] = "", mode[16] = "";
        if (sscanf(env, "%63[^:]:%15s", app, mode) == 2) {
            gchar *content = NULL;
            gsize len = 0;
            g_file_get_contents(NOTIF_CONF, &content, &len, NULL);
            GString *out = g_string_new(NULL);
            char *line = content;
            int replaced = 0;
            size_t klen = strlen(app);
            while (line && *line) {
                char *nl = strchr(line, '\n');
                size_t llen = nl ? (size_t)(nl - line) : strlen(line);
                if (strncmp(line, app, klen) == 0 && line[klen] == '=') {
                    g_string_append_printf(out, "%s=%s", app, strcmp(mode, "off") != 0 ? "on" : "off");
                    replaced = 1;
                } else {
                    g_string_append_len(out, line, llen);
                }
                if (nl) g_string_append_c(out, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_free(content);
            if (!replaced)
                g_string_append_printf(out, "%s=%s\n", app, strcmp(mode, "off") != 0 ? "on" : "off");
            g_file_set_contents(NOTIF_CONF, out->str, out->len, NULL);
            g_string_free(out, TRUE);
        }
    }
    return G_SOURCE_REMOVE;
}

/* ---------- 应用页: 启动已安装应用 ---------- */
static void on_app_launch(GtkWidget *w, gpointer ud) {
    (void)w;
    const char *cmd = (const char *)ud;
    gchar *full = g_strdup_printf("/usr/bin/%s", cmd);
    g_spawn_command_line_async(full, NULL);
    g_free(full);
}

/* ---------- 专注助手: 免打扰模式 ---------- */
#define FOCUS_CONF "/etc/qyfocus.conf"

static void on_focus_toggled(GtkWidget *sw, gpointer ud) {
    (void)ud;
    int on = gtk_switch_get_active(GTK_SWITCH(sw));
    gchar *content = NULL;
    gsize len = 0;
    g_file_get_contents(FOCUS_CONF, &content, &len, NULL);
    GString *out = g_string_new(NULL);
    char *line = content;
    int replaced = 0;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        size_t llen = nl ? (size_t)(nl - line) : strlen(line);
        if (strncmp(line, "dnd=", 4) == 0) {
            g_string_append_printf(out, "dnd=%s", on ? "on" : "off");
            replaced = 1;
        } else {
            g_string_append_len(out, line, llen);
        }
        if (nl) g_string_append_c(out, '\n');
        line = nl ? nl + 1 : NULL;
    }
    g_free(content);
    if (!replaced)
        g_string_append_printf(out, "dnd=%s\n", on ? "on" : "off");
    g_file_set_contents(FOCUS_CONF, out->str, out->len, NULL);
    g_string_free(out, TRUE);
}

/* 自动化验证: QY_SETTINGS_FOCUS=on 启动后开启免打扰 */
static gboolean auto_focus_apply(gpointer p) {
    (void)p;
    const char *env = g_getenv("QY_SETTINGS_FOCUS");
    if (env) {
        gchar *content = NULL;
        gsize len = 0;
        g_file_get_contents(FOCUS_CONF, &content, &len, NULL);
        GString *out = g_string_new(NULL);
        if (content) g_string_append(out, content);
        g_free(content);
        if (strstr(out->str, "dnd=")) {
            GString *tmp = g_string_new(NULL);
            char *line = out->str;
            while (line && *line) {
                char *nl = strchr(line, '\n');
                size_t llen = nl ? (size_t)(nl - line) : strlen(line);
                if (strncmp(line, "dnd=", 4) == 0)
                    g_string_append_printf(tmp, "dnd=%s", strcmp(env, "on") == 0 ? "on" : "off");
                else
                    g_string_append_len(tmp, line, llen);
                if (nl) g_string_append_c(tmp, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_string_free(out, TRUE);
            out = tmp;
        } else {
            g_string_append_printf(out, "dnd=%s\n", strcmp(env, "on") == 0 ? "on" : "off");
        }
        g_file_set_contents(FOCUS_CONF, out->str, out->len, NULL);
        g_string_free(out, TRUE);
    }
    return G_SOURCE_REMOVE;
}

/* 日期时间标签每秒刷新 */
static gboolean update_dt(gpointer p)
{
    GtkWidget *l = (GtkWidget *)p;
    if (!l) return G_SOURCE_REMOVE;
    time_t t = time(NULL);
    struct tm *tm = localtime(&t);
    if (!tm) return G_SOURCE_CONTINUE;
    char buf[64];
    strftime(buf, sizeof buf, "%Y-%m-%d %H:%M:%S", tm);
    gtk_label_set_text(GTK_LABEL(l), buf);
    return G_SOURCE_CONTINUE;
}

static void activate(GtkApplication *app, gpointer ud) {
    qy_load_theme();
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元系统设置"));
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
    gchar *deskver = read_first_line("/usr/share/qydesktop-version");
    gchar *cpumodel = read_cpu_model();
    gchar *cpucores = g_strdup_printf("%ld", sysconf(_SC_NPROCESSORS_ONLN));
    gchar *uptime = read_uptime();
    gchar *load = read_load();
    GtkWidget *logo = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(logo), "<span size='xx-large' weight='bold'>启元 Qiyuan</span>");
    gtk_widget_set_halign(logo, GTK_ALIGN_CENTER);
    qy_add_class(logo, "qy-about-logo");
    gtk_box_pack_start(GTK_BOX(v1), logo, FALSE, FALSE, 8);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("操作系统"), osrel), FALSE, FALSE, 0);
    {
        gchar *platform = g_strdup_printf("启元 Linux %s", u.machine);
        gtk_box_pack_start(GTK_BOX(v1), row(TR("系统平台"), platform), FALSE, FALSE, 0);
        g_free(platform);
    }
    gtk_box_pack_start(GTK_BOX(v1), row(TR("内核版本"), u.release), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("处理器架构"), u.machine), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("CPU 型号"), cpumodel), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("CPU 核心数"), cpucores), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("主机名"), u.nodename), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("内存总量"), mem), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("运行时间"), uptime), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("负载均值"), load), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("桌面环境"), "qydesktop (GTK3)"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("桌面版本"), deskver ? deskver : TR("未知")), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), row(TR("显示协议"), "Wayland (weston)"), FALSE, FALSE, 0);
    g_free(mem); g_free(osrel); g_free(deskver); g_free(cpumodel); g_free(cpucores);
    g_free(uptime); g_free(load);

    /* 关于页快捷启动 */
    GtkWidget *btn_hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *b_mon = gtk_button_new_with_label(TR("打开系统监视"));
    qy_add_class(b_mon, "qy-about-btn");
    g_signal_connect(b_mon, "clicked", G_CALLBACK(launch_app), (gpointer)"qymon");
    GtkWidget *b_store = gtk_button_new_with_label(TR("打开软件中心"));
    qy_add_class(b_store, "qy-about-btn");
    g_signal_connect(b_store, "clicked", G_CALLBACK(launch_app), (gpointer)"qystore");
    GtkWidget *b_files = gtk_button_new_with_label(TR("打开文件管理器"));
    qy_add_class(b_files, "qy-about-btn");
    g_signal_connect(b_files, "clicked", G_CALLBACK(launch_app), (gpointer)"qyfiles");
    gtk_box_pack_start(GTK_BOX(btn_hb), b_mon, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(btn_hb), b_store, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(btn_hb), b_files, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v1), btn_hb, FALSE, FALSE, 10);

    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v1, gtk_label_new(TR("关于")));

    /* 显示 */
    GtkWidget *v2 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v2), 14);
    gtk_box_pack_start(GTK_BOX(v2), row(TR("合成器"), "weston 14.0.2"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v2), row(TR("后端"), "DRM (bochs-drm / pixman)"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v2), row(TR("壁纸"), TR("程序化生成 · 自动轮换")), FALSE, FALSE, 0);
    /* 桌面分辨率: 下拉选择并写入 weston.ini 的 mode= */
    {
        static const char *res_choices[] = {"1024x768", "1280x720", "1280x800",
                                             "1366x768", "1600x900", "1920x1080",
                                             "2560x1440", "3840x2160", NULL};
        char cur_res[64] = "1280x800";
        FILE *wf = fopen("/etc/xdg/weston/weston.ini", "r");
        if (wf) {
            char line[256];
            while (fgets(line, sizeof line, wf)) {
                if (strncmp(line, "mode=", 5) == 0) {
                    char *nl = strchr(line, '\n');
                    if (nl) *nl = 0;
                    snprintf(cur_res, sizeof cur_res, "%s", line + 5);
                }
            }
            fclose(wf);
        }
        GtkWidget *res_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *rl = gtk_label_new(TR("桌面分辨率"));
        gtk_widget_set_size_request(rl, 150, -1);
        gtk_widget_set_halign(rl, GTK_ALIGN_START);
        GtkWidget *res_combo = gtk_combo_box_text_new();
        int cur_idx = 0;
        for (int i = 0; res_choices[i]; i++) {
            gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(res_combo), res_choices[i]);
            if (strcmp(res_choices[i], cur_res) == 0) cur_idx = i;
        }
        /* 环境变量 QY_SETTINGS_RES 强制选择（自动化验证） */
        const char *env_res = g_getenv("QY_SETTINGS_RES");
        if (env_res) {
            for (int i = 0; res_choices[i]; i++)
                if (strcmp(res_choices[i], env_res) == 0) { cur_idx = i; break; }
        }
        gtk_combo_box_set_active(GTK_COMBO_BOX(res_combo), cur_idx);
        GtkWidget *b_res = gtk_button_new_with_label(TR("应用"));
        qy_add_class(b_res, "qy-btn");
        g_signal_connect(b_res, "clicked", G_CALLBACK(on_res_apply), res_combo);
        gtk_box_pack_start(GTK_BOX(res_row), rl, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(res_row), res_combo, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(res_row), b_res, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(v2), res_row, FALSE, FALSE, 0);
        /* 自动化验证: 启动后自动应用所选分辨率 */
        if (env_res)
            g_timeout_add(600, auto_res_apply, res_combo);
    }
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v2, gtk_label_new(TR("显示")));

    /* 字体 */
    GtkWidget *v3 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v3), 14);
    gtk_box_pack_start(GTK_BOX(v3), row(TR("西文字体"), "DejaVu Sans 2.37"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v3), row(TR("中文字体"), "Noto Sans CJK"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v3), row(TR("字体回退"), "fontconfig"), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v3, gtk_label_new(TR("字体")));

    /* 服务 */
    GtkWidget *v4 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v4), 14);
    gtk_box_pack_start(GTK_BOX(v4), row(TR("1 号进程"), "qyinit"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v4), row(TR("会话管理"), "seatd"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v4), row(TR("设备管理"), "eudev"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v4), row(TR("单元目录"), "/etc/qyinit.d"), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v4, gtk_label_new(TR("服务")));

    /* 声音 (ALSA amixer Master) */
    GtkWidget *v5 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v5), 14);
    GtkWidget *vol = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
    gtk_scale_set_draw_value(GTK_SCALE(vol), TRUE);
    gtk_box_pack_start(GTK_BOX(v5), gtk_label_new(TR("输出音量 (Master)")), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v5), vol, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v5), row(TR("音频后端"), "ALSA (amixer)"), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v5, gtk_label_new(TR("声音")));

    /* 显示: 亮度 (backlight 探测) */
    GtkWidget *v6 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(v6), 14);
    GtkWidget *br = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 1, 100, 1);
    gtk_scale_set_draw_value(GTK_SCALE(br), TRUE);
    gtk_box_pack_start(GTK_BOX(v6), gtk_label_new(TR("屏幕亮度")), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(v6), br, FALSE, FALSE, 0);
    {
        GDir *bld = g_dir_open("/sys/class/backlight", 0, NULL);
        const gchar *bln = NULL;
        if (bld) { bln = g_dir_read_name(bld); }
        if (bln) {
            gchar *blinfo = g_strdup_printf("%s (/sys/class/backlight)", bln);
            gtk_box_pack_start(GTK_BOX(v6), row(TR("背光设备"), blinfo), FALSE, FALSE, 0);
            g_free(blinfo);
        } else {
            gtk_box_pack_start(GTK_BOX(v6), row(TR("背光设备"), TR("无 (虚拟显示不支持)")), FALSE, FALSE, 0);
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
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), v6, gtk_label_new(TR("亮度")));

    /* 日期时间（每秒刷新） */
    GtkWidget *vdt = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_set_border_width(GTK_CONTAINER(vdt), 16);
    GtkWidget *dt_label = gtk_label_new(NULL);
    gtk_widget_set_halign(dt_label, GTK_ALIGN_START);
    gtk_label_set_xalign(GTK_LABEL(dt_label), 0.0);
    gtk_box_pack_start(GTK_BOX(vdt), dt_label, FALSE, FALSE, 0);
    /* 时区: /etc/timezone 内容（缺失时回退 UTC） */
    {
        char tz[128] = "UTC";
        FILE *tzf = fopen("/etc/timezone", "r");
        if (tzf) {
            if (fgets(tz, sizeof tz, tzf)) {
                char *nl = strchr(tz, '\n');
                if (nl) *nl = 0;
            }
            fclose(tzf);
        }
        gchar *tzl = g_strdup_printf("%s: %s", TR("时区"), tz);
        GtkWidget *l = gtk_label_new(tzl);
        gtk_widget_set_halign(l, GTK_ALIGN_START);
        gtk_box_pack_start(GTK_BOX(vdt), l, FALSE, FALSE, 0);
        g_free(tzl);
    }
    /* NTP 状态: 探测 chrony/ntpd/systemd-timesyncd 任一启用 */
    {
        gboolean ntp = FALSE;
        const char *probes[] = { "/usr/sbin/chronyd", "/usr/sbin/ntpd",
                                 "/usr/lib/systemd/systemd-timesyncd" };
        for (unsigned i = 0; i < G_N_ELEMENTS(probes); i++) {
            if (access(probes[i], X_OK) == 0) { ntp = TRUE; break; }
        }
        GtkWidget *l = gtk_label_new(TR("NTP 时间同步"));
        gtk_widget_set_halign(l, GTK_ALIGN_START);
        GtkWidget *s = gtk_label_new(ntp ? TR("可用（已安装服务）") : TR("未安装"));
        gtk_widget_set_halign(s, GTK_ALIGN_START);
        gtk_box_pack_start(GTK_BOX(vdt), l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vdt), s, FALSE, FALSE, 0);
    }
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), vdt, gtk_label_new(TR("日期时间")));

    /* 语言 */
    GtkWidget *vlang = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_set_border_width(GTK_CONTAINER(vlang), 16);
    GtkWidget *llb = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(llb), TR("<b>界面语言 / Interface Language</b>"));
    gtk_widget_set_halign(llb, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vlang), llb, FALSE, FALSE, 0);
    /* 当前语言（/etc/qylang: zh/en，默认 zh） */
    {
        char lang[16] = "zh";
        FILE *lf = fopen("/etc/qylang", "r");
        if (lf) {
            if (fgets(lang, sizeof lang, lf)) {
                char *nl = strchr(lang, '\n');
                if (nl) *nl = 0;
            }
            fclose(lf);
        }
        gchar *cur = g_strdup_printf("%s: %s", TR("当前语言"),
                                     strncmp(lang, "en", 2) == 0
                                         ? "English" : TR("简体中文"));
        GtkWidget *cl = gtk_label_new(cur);
        gtk_widget_set_halign(cl, GTK_ALIGN_START);
        qy_add_class(cl, "qy-settings-curlang");
        gtk_box_pack_start(GTK_BOX(vlang), cl, FALSE, FALSE, 0);
        g_free(cur);
    }
    GtkWidget *bzh = gtk_button_new_with_label(TR("简体中文"));
    GtkWidget *ben = gtk_button_new_with_label("English");
    g_signal_connect(bzh, "clicked", G_CALLBACK(on_lang_zh), NULL);
    g_signal_connect(ben, "clicked", G_CALLBACK(on_lang_en), NULL);
    gtk_box_pack_start(GTK_BOX(vlang), bzh, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vlang), ben, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vlang), gtk_label_new(TR("切换后重新启动生效 / Takes effect after reboot")), FALSE, FALSE, 0);
    gtk_notebook_append_page(GTK_NOTEBOOK(nb), vlang, gtk_label_new(TR("语言")));

    /* 驱动页: 已加载内核模块 (/proc/modules) */
    {
        GtkWidget *vdrv = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        GtkWidget *drv_text = gtk_text_view_new();
        gtk_text_view_set_editable(GTK_TEXT_VIEW(drv_text), FALSE);
        gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(drv_text), GTK_WRAP_NONE);
        GtkTextBuffer *db = gtk_text_view_get_buffer(GTK_TEXT_VIEW(drv_text));
        GtkWidget *drv_sw = gtk_scrolled_window_new(NULL, NULL);
        gtk_container_add(GTK_CONTAINER(drv_sw), drv_text);
        gtk_box_pack_start(GTK_BOX(vdrv), drv_sw, TRUE, TRUE, 0);
        FILE *mf = fopen("/proc/modules", "r");
        GString *s = g_string_new(NULL);
        char line[1024];
        int nm = 0;
        if (mf) {
            while (fgets(line, sizeof line, mf)) {
                char name[128] = ""; unsigned long sz = 0; int refs = 0;
                if (sscanf(line, "%127s %lu %d", name, &sz, &refs) == 3) {
                    g_string_append_printf(s, "%s  %lu KB  refs=%d\n",
                                           name, sz / 1024, refs);
                    nm++;
                }
            }
            fclose(mf);
        }
        if (!nm) g_string_append(s, TR("无已加载模块"));
        gchar *txt = g_strdup_printf(TR("已加载内核模块 %d 个：\n\n%s"), nm, s->str);
        gtk_text_buffer_set_text(db, txt, -1);
        g_free(txt);
        g_string_free(s, TRUE);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vdrv, gtk_label_new(TR("驱动")));
    }

    /* 存储页: df -kP 磁盘占用（挂载点/容量/已用/进度条） */
    {
        GtkWidget *vst = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        GtkWidget *tip = gtk_label_new(TR("磁盘占用（df 实时数据）"));
        gtk_widget_set_halign(tip, GTK_ALIGN_START);
        qy_add_class(tip, "qy-settings-curlang");
        gtk_box_pack_start(GTK_BOX(vst), tip, FALSE, FALSE, 0);
        FILE *df = popen("df -kP 2>/dev/null", "r");
        char line[1024];
        int first = 1;
        if (df) {
            while (fgets(line, sizeof line, df)) {
                if (first) { first = 0; continue; } /* 跳过表头 */
                char fs[128] = "", mp[128] = "";
                unsigned long blocks = 0, used = 0, avail = 0;
                int pct = 0;
                if (sscanf(line, "%127s %lu %lu %lu %d%% %127s",
                           fs, &blocks, &used, &avail, &pct, mp) == 6) {
                    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
                    GtkWidget *l = gtk_label_new(mp);
                    gtk_widget_set_size_request(l, 110, -1);
                    gtk_widget_set_halign(l, GTK_ALIGN_START);
                    GtkWidget *pb = gtk_progress_bar_new();
                    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(pb),
                                                  used / (double)(blocks + 1));
                    gchar *info = g_strdup_printf("%d%% · %lu MB / %lu MB",
                                                  pct, used / 1024, blocks / 1024);
                    GtkWidget *il = gtk_label_new(info);
                    g_free(info);
                    gtk_box_pack_start(GTK_BOX(row), l, FALSE, FALSE, 0);
                    gtk_box_pack_start(GTK_BOX(row), pb, TRUE, TRUE, 0);
                    gtk_box_pack_start(GTK_BOX(row), il, FALSE, FALSE, 0);
                    gtk_box_pack_start(GTK_BOX(vst), row, FALSE, FALSE, 0);
                }
            }
            pclose(df);
        }
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vst, gtk_label_new(TR("存储")));
    }

    /* 电源页: 熄屏时间（写 weston.ini [core] idle-time=） */
    {
        static const char *idle_choices[] = { "从不", "1 分钟", "5 分钟",
                                               "10 分钟", "30 分钟", "1 小时" };
        GtkWidget *vpo = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        GtkWidget *tip = gtk_label_new(TR("屏幕熄灭时间（合成器空闲超时）"));
        gtk_widget_set_halign(tip, GTK_ALIGN_START);
        qy_add_class(tip, "qy-settings-curlang");
        gtk_box_pack_start(GTK_BOX(vpo), tip, FALSE, FALSE, 0);
        GtkWidget *po_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *pl = gtk_label_new(TR("熄屏时间"));
        gtk_widget_set_size_request(pl, 150, -1);
        gtk_widget_set_halign(pl, GTK_ALIGN_START);
        GtkWidget *idle_combo = gtk_combo_box_text_new();
        int cur_idx = 2; /* 默认 5 分钟 */
        for (int i = 0; i < (int)G_N_ELEMENTS(idle_choices); i++) {
            gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(idle_combo),
                                           TR(idle_choices[i]));
        }
        /* 读当前 idle-time（0=从不） */
        FILE *wf = fopen("/etc/xdg/weston/weston.ini", "r");
        if (wf) {
            char line[256];
            while (fgets(line, sizeof line, wf)) {
                if (strncmp(line, "idle-time=", 11) == 0) {
                    int cur = atoi(line + 11);
                    for (int i = 0; i < (int)G_N_ELEMENTS(idle_secs); i++)
                        if (idle_secs[i] == cur) cur_idx = i;
                }
            }
            fclose(wf);
        }
        /* 环境变量 QY_SETTINGS_IDLE=N 强制选择（自动化验证） */
        const char *env_idle = g_getenv("QY_SETTINGS_IDLE");
        if (env_idle) {
            int want = atoi(env_idle);
            for (int i = 0; i < (int)G_N_ELEMENTS(idle_secs); i++)
                if (idle_secs[i] == want) cur_idx = i;
        }
        gtk_combo_box_set_active(GTK_COMBO_BOX(idle_combo), cur_idx);
        GtkWidget *b_idle = gtk_button_new_with_label(TR("应用"));
        qy_add_class(b_idle, "qy-btn");
        g_signal_connect(b_idle, "clicked", G_CALLBACK(on_idle_apply),
                         GINT_TO_POINTER(cur_idx));
        gtk_box_pack_start(GTK_BOX(po_row), pl, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(po_row), idle_combo, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(po_row), b_idle, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vpo), po_row, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vpo, gtk_label_new(TR("电源")));
        /* 自动化验证: 启动后自动应用 */
        if (env_idle)
            g_timeout_add(700, auto_idle_apply, GINT_TO_POINTER(cur_idx));
    }

    /* 网络页: 当前网络概况（默认接口/IP/MAC/网关/DNS） */
    {
        GtkWidget *vnet = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vnet), 14);
        char main_if[64] = "eth0";
        char rline[256];
        FILE *rf = popen("ip route show default 2>/dev/null", "r");
        if (rf) {
            if (fgets(rline, sizeof rline, rf)) {
                char *devp = strstr(rline, "dev ");
                if (devp) {
                    devp += 4;
                    char *sp = strchr(devp, ' ');
                    if (sp) *sp = 0;
                    snprintf(main_if, sizeof main_if, "%s", devp);
                }
            }
            pclose(rf);
        }
        char ip[128] = "-";
        char cmd[160];
        snprintf(cmd, sizeof cmd, "ip -o -4 addr show %s 2>/dev/null", main_if);
        FILE *ipf = popen(cmd, "r");
        if (ipf) {
            if (fgets(rline, sizeof rline, ipf)) {
                char *p = strstr(rline, "inet ");
                if (p) {
                    p += 5;
                    char *sp = strchr(p, ' ');
                    if (sp) *sp = 0;
                    snprintf(ip, sizeof ip, "%s", p);
                }
            }
            pclose(ipf);
        }
        char mac[64] = "-";
        snprintf(cmd, sizeof cmd, "ip -o link show %s 2>/dev/null", main_if);
        FILE *mf = popen(cmd, "r");
        if (mf) {
            if (fgets(rline, sizeof rline, mf)) {
                char *mp = strstr(rline, "link/");
                if (mp) {
                    mp += 5;
                    if (sscanf(mp, "%*s %63s", mac) != 1) {
                        char *sp = strchr(mp, ' ');
                        if (sp) *sp = 0;
                        snprintf(mac, sizeof mac, "%s", mp);
                    }
                }
            }
            pclose(mf);
        }
        char gw[128] = "-";
        FILE *gf = popen("ip route show default 2>/dev/null", "r");
        if (gf) {
            if (fgets(rline, sizeof rline, gf)) {
                char *p = strstr(rline, "default via ");
                if (p) {
                    p += 12;
                    char *sp = strchr(p, ' ');
                    if (sp) *sp = 0;
                    snprintf(gw, sizeof gw, "%s", p);
                }
            }
            pclose(gf);
        }
        char dns[128] = "-";
        FILE *dnf = fopen("/etc/resolv.conf", "r");
        if (dnf) {
            int n = 0;
            while (fgets(rline, sizeof rline, dnf) && n < 4) {
                if (strncmp(rline, "nameserver", 10) == 0) {
                    char *p = rline + 10;
                    while (*p == ' ') p++;
                    char *nl = strchr(p, '\n');
                    if (nl) *nl = 0;
                    if (n == 0) snprintf(dns, sizeof dns, "%s", p);
                    else {
                        strncat(dns, ", ", sizeof dns - strlen(dns) - 1);
                        strncat(dns, p, sizeof dns - strlen(dns) - 1);
                    }
                    n++;
                }
            }
            fclose(dnf);
        }
        gtk_box_pack_start(GTK_BOX(vnet), row(TR("网络接口"), main_if), FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vnet), row(TR("IP 地址"), ip), FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vnet), row(TR("MAC 地址"), mac), FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vnet), row(TR("默认网关"), gw), FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vnet), row(TR("DNS 服务器"), dns), FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vnet, gtk_label_new(TR("网络")));
    }

    /* 隐私页: 应用权限开关（写 /etc/qyperm.conf） */
    {
        static const char *perm_keys[] = {
            "location", "camera", "microphone",
            "notifications", "background", "filesystem"
        };
        static const char *perm_labels[] = {
            "位置", "摄像头", "麦克风",
            "通知", "后台应用", "文件系统访问"
        };
        GtkWidget *vpr = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vpr), 14);
        gtk_box_pack_start(GTK_BOX(vpr), row(TR("允许应用访问"), "（写 /etc/qyperm.conf）"), FALSE, FALSE, 0);
        g_perm_loading = 1;
        for (int i = 0; i < 6; i++) {
            GtkWidget *r = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
            GtkWidget *l = gtk_label_new(TR(perm_labels[i]));
            gtk_widget_set_size_request(l, 180, -1);
            gtk_widget_set_halign(l, GTK_ALIGN_START);
            GtkWidget *sw = gtk_switch_new();
            const char *cur = perm_read(perm_keys[i], "on");
            gtk_switch_set_active(GTK_SWITCH(sw), strcmp(cur, "off") != 0);
            g_signal_connect(sw, "state-set", G_CALLBACK(on_perm_toggled),
                             (gpointer)perm_keys[i]);
            /* 自动化: QY_SETTINGS_PERM=camera:off 强制关闭对应开关 */
            const char *env = g_getenv("QY_SETTINGS_PERM");
            if (env) {
                char key[64] = "", mode[16] = "";
                if (sscanf(env, "%63[^:]:%15s", key, mode) == 2 &&
                    strcmp(key, perm_keys[i]) == 0) {
                    gtk_switch_set_active(GTK_SWITCH(sw), strcmp(mode, "off") != 0);
                }
            }
            gtk_box_pack_start(GTK_BOX(r), l, FALSE, FALSE, 0);
            gtk_box_pack_start(GTK_BOX(r), sw, FALSE, FALSE, 0);
            gtk_box_pack_start(GTK_BOX(vpr), r, FALSE, FALSE, 0);
        }
        g_perm_loading = 0;
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vpr, gtk_label_new(TR("隐私")));
        /* 自动化验证: 启动后把配置写入文件 */
        if (g_getenv("QY_SETTINGS_PERM"))
            g_timeout_add(800, auto_perm_apply, NULL);
    }

    /* 应用页: 已安装应用列表（可启动） */
    {
        static const char *apps_installed[][2] = {
            { "系统设置", "qysettings" }, { "系统监视", "qymon" },
            { "系统安装", "qysetup" },    { "用户管理", "qyusers" },
            { "网络管理", "qynet" },      { "文件管理器", "qyfiles" },
            { "图片查看", "qyview" },     { "压缩管理", "qyarc" },
            { "回收站", "qyfiles --trash" }, { "终端", "weston-terminal" },
            { "文本编辑", "qyedit" },     { "软件中心", "qystore" },
        };
        GtkWidget *vap = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vap), 14);
        GtkWidget *tip = gtk_label_new(TR("已安装应用（点击启动）"));
        gtk_widget_set_halign(tip, GTK_ALIGN_START);
        qy_add_class(tip, "qy-settings-curlang");
        gtk_box_pack_start(GTK_BOX(vap), tip, FALSE, FALSE, 0);
        GtkWidget *ap_scroll = gtk_scrolled_window_new(NULL, NULL);
        gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(ap_scroll),
                                       GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
        GtkWidget *ap_list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
        for (int i = 0; i < 12; i++) {
            GtkWidget *r = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
            GtkWidget *l = gtk_label_new(TR(apps_installed[i][0]));
            gtk_widget_set_size_request(l, 180, -1);
            gtk_widget_set_halign(l, GTK_ALIGN_START);
            gchar *cmd0;
            const char *cmdname = apps_installed[i][1];
            if (strchr(cmdname, ' ')) {
                char bin_path[128];
                sscanf(cmdname, "%127s", bin_path);
                cmd0 = g_strdup_printf("/usr/bin/%s", bin_path);
            } else {
                cmd0 = g_strdup_printf("/usr/bin/%s", cmdname);
            }
            gboolean exists = g_file_test(cmd0, G_FILE_TEST_EXISTS);
            g_free(cmd0);
            GtkWidget *cmdl = gtk_label_new(apps_installed[i][1]);
            gtk_widget_set_halign(cmdl, GTK_ALIGN_START);
            qy_add_class(cmdl, "qy-dim");
            GtkWidget *b = gtk_button_new_with_label(TR("启动"));
            gtk_widget_set_sensitive(b, exists);
            if (exists)
                g_signal_connect(b, "clicked", G_CALLBACK(on_app_launch),
                                 (gpointer)apps_installed[i][1]);
            gtk_box_pack_start(GTK_BOX(r), l, FALSE, FALSE, 0);
            gtk_box_pack_start(GTK_BOX(r), cmdl, TRUE, TRUE, 0);
            gtk_box_pack_start(GTK_BOX(r), b, FALSE, FALSE, 0);
            gtk_box_pack_start(GTK_BOX(ap_list), r, FALSE, FALSE, 0);
        }
        gtk_container_add(GTK_CONTAINER(ap_scroll), ap_list);
        gtk_box_pack_start(GTK_BOX(vap), ap_scroll, TRUE, TRUE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vap, gtk_label_new(TR("应用程序")));
    }

    /* 专注助手页: 免打扰模式开关（写 /etc/qyfocus.conf） */
    {
        GtkWidget *vfo = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vfo), 14);
        gtk_box_pack_start(GTK_BOX(vfo), row(TR("专注助手"), TR("免打扰时屏蔽通知弹窗")), FALSE, FALSE, 0);
        GtkWidget *fo_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *fo_l = gtk_label_new(TR("免打扰模式"));
        gtk_widget_set_size_request(fo_l, 180, -1);
        gtk_widget_set_halign(fo_l, GTK_ALIGN_START);
        GtkWidget *fo_sw = gtk_switch_new();
        FILE *ff = fopen(FOCUS_CONF, "r");
        int dnd = 0;
        if (ff) {
            char line[64];
            while (fgets(line, sizeof line, ff))
                if (strncmp(line, "dnd=", 4) == 0)
                    dnd = strncmp(line + 4, "on", 2) == 0;
            fclose(ff);
        }
        gtk_switch_set_active(GTK_SWITCH(fo_sw), dnd);
        const char *env_f = g_getenv("QY_SETTINGS_FOCUS");
        if (env_f)
            gtk_switch_set_active(GTK_SWITCH(fo_sw), strcmp(env_f, "on") == 0);
        g_signal_connect(fo_sw, "state-set", G_CALLBACK(on_focus_toggled), NULL);
        gtk_box_pack_start(GTK_BOX(fo_row), fo_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(fo_row), fo_sw, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vfo), fo_row, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vfo, gtk_label_new(TR("专注")));
        if (env_f)
            g_timeout_add(900, auto_focus_apply, NULL);
    }

    /* 通知页: 应用通知开关（写 /etc/qynotif.conf） */
    {
        static const char *notif_apps[][2] = {
            { "系统监视", "qymon" },   { "文件管理器", "qyfiles" },
            { "软件中心", "qystore" },  { "文本编辑", "qyedit" },
            { "图片查看", "qyview" }, { "网络管理", "qynet" },
        };
        GtkWidget *vno = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vno), 14);
        GtkWidget *tip = gtk_label_new(TR("哪些应用可以发送通知"));
        gtk_widget_set_halign(tip, GTK_ALIGN_START);
        qy_add_class(tip, "qy-settings-curlang");
        gtk_box_pack_start(GTK_BOX(vno), tip, FALSE, FALSE, 0);
        g_notif_loading = 1;
        for (int i = 0; i < 6; i++) {
            GtkWidget *r = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
            GtkWidget *l = gtk_label_new(TR(notif_apps[i][0]));
            gtk_widget_set_size_request(l, 180, -1);
            gtk_widget_set_halign(l, GTK_ALIGN_START);
            GtkWidget *sw = gtk_switch_new();
            /* 读当前配置 */
            gchar *content = NULL;
            gsize len = 0;
            int cur_on = 1;
            if (g_file_get_contents(NOTIF_CONF, &content, &len, NULL)) {
                char *line = content;
                size_t klen = strlen(notif_apps[i][1]);
                while (line && *line) {
                    if (strncmp(line, notif_apps[i][1], klen) == 0 &&
                        line[klen] == '=') {
                        cur_on = strncmp(line + klen + 1, "off", 3) != 0;
                        break;
                    }
                    char *nl = strchr(line, '\n');
                    line = nl ? nl + 1 : NULL;
                }
                g_free(content);
            }
            gtk_switch_set_active(GTK_SWITCH(sw), cur_on);
            /* 自动化: QY_SETTINGS_NOTIF=app:off */
            const char *env = g_getenv("QY_SETTINGS_NOTIF");
            if (env) {
                char app[64] = "", mode[16] = "";
                if (sscanf(env, "%63[^:]:%15s", app, mode) == 2 &&
                    strcmp(app, notif_apps[i][1]) == 0) {
                    gtk_switch_set_active(GTK_SWITCH(sw), strcmp(mode, "off") != 0);
                }
            }
            g_signal_connect(sw, "state-set", G_CALLBACK(on_notif_toggled),
                             (gpointer)notif_apps[i][1]);
            gtk_box_pack_start(GTK_BOX(r), l, FALSE, FALSE, 0);
            gtk_box_pack_start(GTK_BOX(r), sw, FALSE, FALSE, 0);
            gtk_box_pack_start(GTK_BOX(vno), r, FALSE, FALSE, 0);
        }
        g_notif_loading = 0;
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vno, gtk_label_new(TR("通知")));
        if (g_getenv("QY_SETTINGS_NOTIF"))
            g_timeout_add(950, auto_notif_apply, NULL);
    }

    /* 防火墙页: 状态 + 开关（写 /etc/qyfirewall.conf） */
    {
        GtkWidget *vfw = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vfw), 14);
        int rules = -1;
        FILE *it = popen("iptables -L -n 2>/dev/null | grep -vc '^Chain\\|^$\\|^target'", "r");
        if (it) {
            char buf[32];
            if (fgets(buf, sizeof buf, it))
                rules = atoi(buf);
            pclose(it);
        }
        gchar *fw_status;
        if (rules >= 0)
            fw_status = g_strdup_printf(TR("防火墙规则 %d 条"), rules);
        else
            fw_status = g_strdup_printf("%s", TR("未检测到 iptables"));
        gtk_box_pack_start(GTK_BOX(vfw), row(TR("防火墙状态"), fw_status), FALSE, FALSE, 0);
        g_free(fw_status);
        GtkWidget *fw_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *fw_l = gtk_label_new(TR("启用防火墙"));
        gtk_widget_set_size_request(fw_l, 180, -1);
        gtk_widget_set_halign(fw_l, GTK_ALIGN_START);
        GtkWidget *fw_sw = gtk_switch_new();
        FILE *fwf = fopen(FIREWALL_CONF, "r");
        int fw_on = 0;
        if (fwf) {
            char line[64];
            while (fgets(line, sizeof line, fwf))
                if (strncmp(line, "firewall=", 10) == 0)
                    fw_on = strncmp(line + 10, "on", 2) == 0;
            fclose(fwf);
        }
        gtk_switch_set_active(GTK_SWITCH(fw_sw), fw_on);
        const char *env_fw = g_getenv("QY_SETTINGS_FIREWALL");
        if (env_fw)
            gtk_switch_set_active(GTK_SWITCH(fw_sw), strcmp(env_fw, "on") == 0);
        g_signal_connect(fw_sw, "state-set", G_CALLBACK(on_firewall_toggled), NULL);
        gtk_box_pack_start(GTK_BOX(fw_row), fw_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(fw_row), fw_sw, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vfw), fw_row, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vfw, gtk_label_new(TR("防火墙")));
        if (env_fw)
            g_timeout_add(1000, auto_firewall_apply, NULL);
    }

    /* 代理页: HTTP/HTTPS 代理（写 /etc/environment） */
    {
        GtkWidget *vpx = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vpx), 14);
        gtk_box_pack_start(GTK_BOX(vpx), row(TR("代理服务器"), TR("写入 /etc/environment，重启应用生效")), FALSE, FALSE, 0);
        GtkWidget *px_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *px_l = gtk_label_new(TR("代理地址"));
        gtk_widget_set_size_request(px_l, 150, -1);
        gtk_widget_set_halign(px_l, GTK_ALIGN_START);
        GtkWidget *px_entry = gtk_entry_new();
        gtk_entry_set_placeholder_text(GTK_ENTRY(px_entry), "http://主机:端口");
        gtk_widget_set_size_request(px_entry, 320, -1);
        GtkWidget *px_btn = gtk_button_new_with_label(TR("应用"));
        qy_add_class(px_btn, "qy-btn");
        g_signal_connect(px_btn, "clicked", G_CALLBACK(on_proxy_apply), px_entry);
        gtk_box_pack_start(GTK_BOX(px_row), px_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(px_row), px_entry, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(px_row), px_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vpx), px_row, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vpx, gtk_label_new(TR("代理")));
        if (g_getenv("QY_SETTINGS_PROXY"))
            g_timeout_add(1050, auto_proxy_apply, NULL);
    }

    /* 设备页: USB 与输入设备 */
    {
        GtkWidget *vdev = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vdev), 14);
        GtkWidget *tip = gtk_label_new(TR("USB 与输入设备"));
        gtk_widget_set_halign(tip, GTK_ALIGN_START);
        qy_add_class(tip, "qy-settings-curlang");
        gtk_box_pack_start(GTK_BOX(vdev), tip, FALSE, FALSE, 0);
        GtkWidget *dev_scroll = gtk_scrolled_window_new(NULL, NULL);
        gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(dev_scroll),
                                       GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
        GtkWidget *dev_list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
        int n = 0;
        FILE *inf = fopen("/proc/bus/input/devices", "r");
        if (inf) {
            char line[256];
            while (fgets(line, sizeof line, inf)) {
                if (strncmp(line, "N: Name=", 8) == 0) {
                    char *p = line + 8;
                    char *nl = strchr(p, '\n');
                    if (nl) *nl = 0;
                    gchar *txt = g_strdup_printf("🖱 %s", p);
                    GtkWidget *il = gtk_label_new(txt);
                    gtk_widget_set_halign(il, GTK_ALIGN_START);
                    gtk_box_pack_start(GTK_BOX(dev_list), il, FALSE, FALSE, 0);
                    g_free(txt);
                    n++;
                }
            }
            fclose(inf);
        }
        DIR *ud = opendir("/sys/bus/usb/devices");
        if (ud) {
            struct dirent *de;
            while ((de = readdir(ud))) {
                if (de->d_name[0] == '.') continue;
                char mp[160];
                char vendor[128] = "", product[128] = "";
                snprintf(mp, sizeof mp, "/sys/bus/usb/devices/%s/manufacturer",
                         de->d_name);
                FILE *vf = fopen(mp, "r");
                if (vf) {
                    if (fgets(vendor, sizeof vendor, vf)) {
                        char *nl = strchr(vendor, '\n');
                        if (nl) *nl = 0;
                    }
                    fclose(vf);
                }
                snprintf(mp, sizeof mp, "/sys/bus/usb/devices/%s/product",
                         de->d_name);
                FILE *pf = fopen(mp, "r");
                if (pf) {
                    if (fgets(product, sizeof product, pf)) {
                        char *nl = strchr(product, '\n');
                        if (nl) *nl = 0;
                    }
                    fclose(pf);
                }
                if (vendor[0] || product[0]) {
                    gchar *txt = g_strdup_printf("🔌 %s %s (%s)", vendor,
                                                 product, de->d_name);
                    GtkWidget *ul = gtk_label_new(txt);
                    gtk_widget_set_halign(ul, GTK_ALIGN_START);
                    gtk_box_pack_start(GTK_BOX(dev_list), ul, FALSE, FALSE, 0);
                    g_free(txt);
                    n++;
                }
            }
            closedir(ud);
        }
        if (n == 0) {
            GtkWidget *empty = gtk_label_new(TR("未检测到外接设备"));
            gtk_widget_set_halign(empty, GTK_ALIGN_START);
            gtk_box_pack_start(GTK_BOX(dev_list), empty, FALSE, FALSE, 0);
        }
        gtk_container_add(GTK_CONTAINER(dev_scroll), dev_list);
        gtk_box_pack_start(GTK_BOX(vdev), dev_scroll, TRUE, TRUE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vdev, gtk_label_new(TR("设备")));
    }

    /* 多任务页: 分屏/贴靠/虚拟桌面开关（写 /etc/qymultitask.conf） */
    {
        static const char *multi_keys[] = { "split", "snap", "vd" };
        static const char *multi_labels[] = { "分屏", "窗口贴靠", "虚拟桌面" };
        GtkWidget *vmt = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vmt), 14);
        GtkWidget *tip = gtk_label_new(TR("多任务处理"));
        gtk_widget_set_halign(tip, GTK_ALIGN_START);
        qy_add_class(tip, "qy-settings-curlang");
        gtk_box_pack_start(GTK_BOX(vmt), tip, FALSE, FALSE, 0);
        g_multi_loading = 1;
        for (int i = 0; i < 3; i++) {
            GtkWidget *r = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
            GtkWidget *l = gtk_label_new(TR(multi_labels[i]));
            gtk_widget_set_size_request(l, 180, -1);
            gtk_widget_set_halign(l, GTK_ALIGN_START);
            GtkWidget *sw = gtk_switch_new();
            gchar *content = NULL;
            gsize len = 0;
            int cur_on = 1;
            if (g_file_get_contents(MULTI_CONF, &content, &len, NULL)) {
                char *line = content;
                size_t klen = strlen(multi_keys[i]);
                while (line && *line) {
                    if (strncmp(line, multi_keys[i], klen) == 0 &&
                        line[klen] == '=') {
                        cur_on = strncmp(line + klen + 1, "off", 3) != 0;
                        break;
                    }
                    char *nl = strchr(line, '\n');
                    line = nl ? nl + 1 : NULL;
                }
                g_free(content);
            }
            gtk_switch_set_active(GTK_SWITCH(sw), cur_on);
            const char *env = g_getenv("QY_SETTINGS_MULTI");
            if (env) {
                char key[64] = "", mode[16] = "";
                if (sscanf(env, "%63[^:]:%15s", key, mode) == 2 &&
                    strcmp(key, multi_keys[i]) == 0) {
                    gtk_switch_set_active(GTK_SWITCH(sw), strcmp(mode, "off") != 0);
                }
            }
            g_signal_connect(sw, "state-set", G_CALLBACK(on_multi_toggled),
                             (gpointer)multi_keys[i]);
            gtk_box_pack_start(GTK_BOX(r), l, FALSE, FALSE, 0);
            gtk_box_pack_start(GTK_BOX(r), sw, FALSE, FALSE, 0);
            gtk_box_pack_start(GTK_BOX(vmt), r, FALSE, FALSE, 0);
        }
        g_multi_loading = 0;
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vmt, gtk_label_new(TR("多任务")));
        if (g_getenv("QY_SETTINGS_MULTI"))
            g_timeout_add(1100, auto_multi_apply, NULL);
    }

    /* 自动播放页: U 盘/光盘插入行为（写 /etc/qyautoplay.conf） */
    {
        static const char *ap_actions[] = { "open", "ask", "none" };
        static const char *ap_labels[] = { "打开文件管理器", "每次询问", "不操作" };
        GtkWidget *vap2 = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vap2), 14);
        GtkWidget *tip = gtk_label_new(TR("自动播放"));
        gtk_widget_set_halign(tip, GTK_ALIGN_START);
        qy_add_class(tip, "qy-settings-curlang");
        gtk_box_pack_start(GTK_BOX(vap2), tip, FALSE, FALSE, 0);
        /* 自动播放开关 */
        GtkWidget *ap_row1 = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *ap_l1 = gtk_label_new(TR("插入可移动设备时自动播放"));
        gtk_widget_set_size_request(ap_l1, 240, -1);
        gtk_widget_set_halign(ap_l1, GTK_ALIGN_START);
        GtkWidget *ap_sw = gtk_switch_new();
        g_autoplay_loading = 1;
        gchar *content = NULL;
        gsize len = 0;
        int cur_on = 1;
        if (g_file_get_contents(AUTOPLAY_CONF, &content, &len, NULL)) {
            char *line = content;
            while (line && *line) {
                if (strncmp(line, "autoplay=", 10) == 0) {
                    cur_on = strncmp(line + 10, "off", 3) != 0;
                    break;
                }
                char *nl = strchr(line, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_free(content);
        }
        gtk_switch_set_active(GTK_SWITCH(ap_sw), cur_on);
        const char *env_ap = g_getenv("QY_SETTINGS_AUTOPLAY");
        if (env_ap)
            gtk_switch_set_active(GTK_SWITCH(ap_sw), strcmp(env_ap, "off") != 0);
        g_signal_connect(ap_sw, "state-set", G_CALLBACK(on_autoplay_toggled), NULL);
        gtk_box_pack_start(GTK_BOX(ap_row1), ap_l1, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(ap_row1), ap_sw, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vap2), ap_row1, FALSE, FALSE, 0);
        /* 动作选择 */
        GtkWidget *ap_row2 = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *ap_l2 = gtk_label_new(TR("插入 U 盘时"));
        gtk_widget_set_size_request(ap_l2, 150, -1);
        gtk_widget_set_halign(ap_l2, GTK_ALIGN_START);
        GtkWidget *ap_combo = gtk_combo_box_text_new();
        int cur_act = 0;
        for (int i = 0; i < 3; i++)
            gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(ap_combo),
                                           TR(ap_labels[i]));
        if (1) {
            gchar *c2 = NULL;
            gsize l2 = 0;
            if (g_file_get_contents(AUTOPLAY_CONF, &c2, &l2, NULL)) {
                char *line = c2;
                while (line && *line) {
                    if (strncmp(line, "action=", 7) == 0) {
                        char *p = line + 7;
                        char *nl = strchr(p, '\n');
                        if (nl) *nl = 0;
                        for (int i = 0; i < 3; i++)
                            if (strcmp(p, ap_actions[i]) == 0) cur_act = i;
                        break;
                    }
                    char *nl = strchr(line, '\n');
                    line = nl ? nl + 1 : NULL;
                }
                g_free(c2);
            }
        }
        gtk_combo_box_set_active(GTK_COMBO_BOX(ap_combo), cur_act);
        GtkWidget *ap_btn = gtk_button_new_with_label(TR("应用"));
        qy_add_class(ap_btn, "qy-btn");
        g_signal_connect(ap_btn, "clicked", G_CALLBACK(on_autoplay_action),
                         (gpointer)ap_actions[cur_act]);
        gtk_box_pack_start(GTK_BOX(ap_row2), ap_l2, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(ap_row2), ap_combo, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(ap_row2), ap_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vap2), ap_row2, FALSE, FALSE, 0);
        g_autoplay_loading = 0;
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vap2, gtk_label_new(TR("自动播放")));
        if (env_ap)
            g_timeout_add(1150, auto_autoplay_apply, NULL);
    }

    /* 鼠标页: 主按键/双击速度/滚轮行数（写 /etc/qymouse.conf） */
    {
        GtkWidget *vms = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vms), 14);
        gtk_box_pack_start(GTK_BOX(vms), row(TR("鼠标"), TR("设置写入 /etc/qymouse.conf")), FALSE, FALSE, 0);
        /* 主按键 */
        GtkWidget *mb_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *mb_l = gtk_label_new(TR("主按键"));
        gtk_widget_set_size_request(mb_l, 150, -1);
        gtk_widget_set_halign(mb_l, GTK_ALIGN_START);
        g_mouse_combo = gtk_combo_box_text_new();
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_mouse_combo), TR("右手（默认）"));
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_mouse_combo), TR("左手"));
        gtk_combo_box_set_active(GTK_COMBO_BOX(g_mouse_combo), 0);
        const char *env_ms = g_getenv("QY_SETTINGS_MOUSE");
        if (env_ms && strstr(env_ms, "primary:right"))
            gtk_combo_box_set_active(GTK_COMBO_BOX(g_mouse_combo), 1);
        gtk_box_pack_start(GTK_BOX(mb_row), mb_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(mb_row), g_mouse_combo, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vms), mb_row, FALSE, FALSE, 0);
        /* 双击速度 */
        GtkWidget *ds_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *ds_l = gtk_label_new(TR("双击速度"));
        gtk_widget_set_size_request(ds_l, 150, -1);
        gtk_widget_set_halign(ds_l, GTK_ALIGN_START);
        g_mouse_scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 10, 1);
        gtk_widget_set_size_request(g_mouse_scale, 260, -1);
        gtk_scale_set_value_pos(GTK_SCALE(g_mouse_scale), GTK_POS_RIGHT);
        gtk_range_set_value(GTK_RANGE(g_mouse_scale), 5);
        gtk_box_pack_start(GTK_BOX(ds_row), ds_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(ds_row), g_mouse_scale, TRUE, TRUE, 0);
        gtk_box_pack_start(GTK_BOX(vms), ds_row, FALSE, FALSE, 0);
        /* 滚轮行数 */
        GtkWidget *sw_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *sw_l = gtk_label_new(TR("滚轮行数"));
        gtk_widget_set_size_request(sw_l, 150, -1);
        gtk_widget_set_halign(sw_l, GTK_ALIGN_START);
        g_mouse_spin = gtk_spin_button_new_with_range(1, 20, 1);
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(g_mouse_spin), 3);
        gtk_box_pack_start(GTK_BOX(sw_row), sw_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(sw_row), g_mouse_spin, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vms), sw_row, FALSE, FALSE, 0);
        /* 应用 */
        GtkWidget *ms_btn = gtk_button_new_with_label(TR("应用"));
        qy_add_class(ms_btn, "qy-btn");
        g_signal_connect(ms_btn, "clicked", G_CALLBACK(on_mouse_apply), NULL);
        GtkWidget *ms_hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
        gtk_box_pack_start(GTK_BOX(ms_hb), ms_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vms), ms_hb, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vms, gtk_label_new(TR("鼠标")));
        if (env_ms)
            g_timeout_add(1200, auto_mouse_apply, NULL);
    }

    /* 网络重置页: 危险操作 + 确认（写 /etc/qynetreset.log） */
    {
        GtkWidget *vnr = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vnr), 14);
        gtk_box_pack_start(GTK_BOX(vnr), row(TR("网络重置"), TR("恢复网卡出厂设置（危险）")), FALSE, FALSE, 0);
        GtkWidget *nr_btn = gtk_button_new_with_label(TR("重置网络"));
        qy_add_class(nr_btn, "qy-btn");
        g_signal_connect(nr_btn, "clicked", G_CALLBACK(on_net_reset), NULL);
        GtkWidget *nr_hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
        gtk_box_pack_start(GTK_BOX(nr_hb), nr_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vnr), nr_hb, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vnr, gtk_label_new(TR("网络重置")));
        if (g_getenv("QY_SETTINGS_NETRESET"))
            g_timeout_add(1250, auto_net_reset, NULL);
    }

    /* 多显示器页: 输出列表 + 布局（写 /etc/qydisplay.conf） */
    {
        GtkWidget *vd = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vd), 14);
        gtk_box_pack_start(GTK_BOX(vd), row(TR("检测到的显示器"), "Virtual-1 (1280x800)"), FALSE, FALSE, 0);
        GtkWidget *dl_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *dl_l = gtk_label_new(TR("多显示器模式"));
        gtk_widget_set_size_request(dl_l, 150, -1);
        gtk_widget_set_halign(dl_l, GTK_ALIGN_START);
        g_disp_combo = gtk_combo_box_text_new();
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_disp_combo), TR("扩展桌面"));
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_disp_combo), TR("复制屏幕"));
        gtk_combo_box_set_active(GTK_COMBO_BOX(g_disp_combo), 0);
        GtkWidget *dl_btn = gtk_button_new_with_label(TR("应用"));
        qy_add_class(dl_btn, "qy-btn");
        g_signal_connect(dl_btn, "clicked", G_CALLBACK(on_display_apply), NULL);
        gtk_box_pack_start(GTK_BOX(dl_row), dl_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(dl_row), g_disp_combo, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(dl_row), dl_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vd), dl_row, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vd, gtk_label_new(TR("多显示器")));
        if (g_getenv("QY_SETTINGS_DISPLAY"))
            g_timeout_add(1300, auto_display_apply, NULL);
    }

    /* 蓝牙页: 开关 + 适配器检测（写 /etc/qybluetooth.conf） */
    {
        GtkWidget *vbt = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vbt), 14);
        GtkWidget *bt_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *bt_l = gtk_label_new(TR("蓝牙"));
        gtk_widget_set_size_request(bt_l, 180, -1);
        gtk_widget_set_halign(bt_l, GTK_ALIGN_START);
        GtkWidget *bt_sw = gtk_switch_new();
        g_bt_loading = 1;
        gchar *content = NULL;
        gsize len = 0;
        int cur_on = 0;
        if (g_file_get_contents(BT_CONF, &content, &len, NULL)) {
            char *line = content;
            while (line && *line) {
                if (strncmp(line, "bluetooth=", 11) == 0) {
                    cur_on = strncmp(line + 11, "off", 3) != 0;
                    break;
                }
                char *nl = strchr(line, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_free(content);
        }
        const char *env_bt = g_getenv("QY_SETTINGS_BT");
        if (env_bt)
            cur_on = strcmp(env_bt, "off") != 0;
        gtk_switch_set_active(GTK_SWITCH(bt_sw), cur_on);
        g_signal_connect(bt_sw, "state-set", G_CALLBACK(on_bt_toggled), NULL);
        gtk_box_pack_start(GTK_BOX(bt_row), bt_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(bt_row), bt_sw, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vbt), bt_row, FALSE, FALSE, 0);
        g_bt_loading = 0;
        int n = 0;
        DIR *btd = opendir("/sys/class/bluetooth");
        if (btd) {
            struct dirent *de;
            while ((de = readdir(btd))) {
                if (strncmp(de->d_name, "hci", 3) == 0) {
                    gchar *txt = g_strdup_printf("🖥 %s", de->d_name);
                    GtkWidget *bl = gtk_label_new(txt);
                    gtk_widget_set_halign(bl, GTK_ALIGN_START);
                    gtk_box_pack_start(GTK_BOX(vbt), bl, FALSE, FALSE, 0);
                    g_free(txt);
                    n++;
                }
            }
            closedir(btd);
        }
        if (n == 0) {
            GtkWidget *empty = gtk_label_new(TR("未检测到蓝牙适配器"));
            gtk_widget_set_halign(empty, GTK_ALIGN_START);
            gtk_box_pack_start(GTK_BOX(vbt), empty, FALSE, FALSE, 0);
        }
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vbt, gtk_label_new(TR("蓝牙")));
        if (env_bt)
            g_timeout_add(1350, auto_bt_apply, NULL);
    }

    /* 触摸板页: 开关 + 灵敏度（写 /etc/qytouchpad.conf） */
    {
        GtkWidget *vtp = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vtp), 14);
        GtkWidget *tp_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *tp_l = gtk_label_new(TR("启用触摸板"));
        gtk_widget_set_size_request(tp_l, 180, -1);
        gtk_widget_set_halign(tp_l, GTK_ALIGN_START);
        GtkWidget *tp_sw = gtk_switch_new();
        g_tp_loading = 1;
        gchar *content = NULL;
        gsize len = 0;
        int cur_on = 1;
        if (g_file_get_contents(TOUCHPAD_CONF, &content, &len, NULL)) {
            char *line = content;
            while (line && *line) {
                if (strncmp(line, "touchpad=", 10) == 0) {
                    cur_on = strncmp(line + 10, "off", 3) != 0;
                    break;
                }
                char *nl = strchr(line, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_free(content);
        }
        const char *env_tp = g_getenv("QY_SETTINGS_TOUCHPAD");
        if (env_tp)
            cur_on = strcmp(env_tp, "off") != 0;
        gtk_switch_set_active(GTK_SWITCH(tp_sw), cur_on);
        g_signal_connect(tp_sw, "state-set", G_CALLBACK(on_touchpad_toggled), NULL);
        gtk_box_pack_start(GTK_BOX(tp_row), tp_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(tp_row), tp_sw, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vtp), tp_row, FALSE, FALSE, 0);
        g_tp_loading = 0;
        GtkWidget *sen_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *sen_l = gtk_label_new(TR("灵敏度"));
        gtk_widget_set_size_request(sen_l, 180, -1);
        gtk_widget_set_halign(sen_l, GTK_ALIGN_START);
        g_tp_scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 1, 5, 1);
        gtk_widget_set_size_request(g_tp_scale, 260, -1);
        gtk_scale_set_value_pos(GTK_SCALE(g_tp_scale), GTK_POS_RIGHT);
        gtk_range_set_value(GTK_RANGE(g_tp_scale), 3);
        gtk_box_pack_start(GTK_BOX(sen_row), sen_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(sen_row), g_tp_scale, TRUE, TRUE, 0);
        gtk_box_pack_start(GTK_BOX(vtp), sen_row, FALSE, FALSE, 0);
        GtkWidget *tp_btn = gtk_button_new_with_label(TR("应用"));
        qy_add_class(tp_btn, "qy-btn");
        g_signal_connect(tp_btn, "clicked", G_CALLBACK(on_touchpad_apply), NULL);
        GtkWidget *tp_hb = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
        gtk_box_pack_start(GTK_BOX(tp_hb), tp_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vtp), tp_hb, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vtp, gtk_label_new(TR("触摸板")));
        if (env_tp)
            g_timeout_add(1400, auto_touchpad_apply, NULL);
    }

    /* 图形页: 显卡信息 + 模式（写 /etc/qygraphics.conf） */
    {
        GtkWidget *vg = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vg), 14);
        gtk_box_pack_start(GTK_BOX(vg), row(TR("显卡"), TR("未检测到独立显卡")), FALSE, FALSE, 0);
        GtkWidget *gfx_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *gfx_l = gtk_label_new(TR("图形模式"));
        gtk_widget_set_size_request(gfx_l, 150, -1);
        gtk_widget_set_halign(gfx_l, GTK_ALIGN_START);
        g_gfx_combo = gtk_combo_box_text_new();
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_gfx_combo), TR("默认"));
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_gfx_combo), TR("高性能"));
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_gfx_combo), TR("省电"));
        gtk_combo_box_set_active(GTK_COMBO_BOX(g_gfx_combo), 0);
        const char *env_gfx = g_getenv("QY_SETTINGS_GRAPHICS");
        if (env_gfx && strstr(env_gfx, "mode:performance"))
            gtk_combo_box_set_active(GTK_COMBO_BOX(g_gfx_combo), 1);
        GtkWidget *gfx_btn = gtk_button_new_with_label(TR("应用"));
        qy_add_class(gfx_btn, "qy-btn");
        g_signal_connect(gfx_btn, "clicked", G_CALLBACK(on_graphics_apply), NULL);
        gtk_box_pack_start(GTK_BOX(gfx_row), gfx_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(gfx_row), g_gfx_combo, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(gfx_row), gfx_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vg), gfx_row, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vg, gtk_label_new(TR("图形")));
        if (env_gfx)
            g_timeout_add(1450, auto_graphics_apply, NULL);
    }

    /* 远程桌面页: 开关 + 端口（写 /etc/qyremotedesktop.conf） */
    {
        GtkWidget *vrd = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vrd), 14);
        gtk_box_pack_start(GTK_BOX(vrd), row(TR("远程桌面"), TR("允许远程连接到这台电脑")), FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vrd), row(TR("端口"), "3389"), FALSE, FALSE, 0);
        GtkWidget *rdp_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *rdp_l = gtk_label_new(TR("启用远程桌面"));
        gtk_widget_set_size_request(rdp_l, 180, -1);
        gtk_widget_set_halign(rdp_l, GTK_ALIGN_START);
        GtkWidget *rdp_sw = gtk_switch_new();
        g_rdp_loading = 1;
        gchar *content = NULL;
        gsize len = 0;
        int cur_on = 0;
        if (g_file_get_contents(RDP_CONF, &content, &len, NULL)) {
            char *line = content;
            while (line && *line) {
                if (strncmp(line, "rdp=", 4) == 0) {
                    cur_on = strncmp(line + 4, "off", 3) != 0;
                    break;
                }
                char *nl = strchr(line, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_free(content);
        }
        const char *env_rdp = g_getenv("QY_SETTINGS_RDP");
        if (env_rdp)
            cur_on = strcmp(env_rdp, "off") != 0;
        gtk_switch_set_active(GTK_SWITCH(rdp_sw), cur_on);
        g_signal_connect(rdp_sw, "state-set", G_CALLBACK(on_rdp_toggled), NULL);
        gtk_box_pack_start(GTK_BOX(rdp_row), rdp_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(rdp_row), rdp_sw, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vrd), rdp_row, FALSE, FALSE, 0);
        g_rdp_loading = 0;
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vrd, gtk_label_new(TR("远程桌面")));
        if (env_rdp)
            g_timeout_add(1500, auto_rdp_apply, NULL);
    }

    /* 投影页: 投影模式（写 /etc/qyproject.conf） */
    {
        GtkWidget *vpj = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vpj), 14);
        gtk_box_pack_start(GTK_BOX(vpj), row(TR("投影"), TR("选择第二屏幕的投影模式")), FALSE, FALSE, 0);
        GtkWidget *pj_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *pj_l = gtk_label_new(TR("投影模式"));
        gtk_widget_set_size_request(pj_l, 150, -1);
        gtk_widget_set_halign(pj_l, GTK_ALIGN_START);
        g_proj_combo = gtk_combo_box_text_new();
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_proj_combo), TR("仅电脑屏幕"));
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_proj_combo), TR("复制屏幕"));
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_proj_combo), TR("扩展桌面"));
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_proj_combo), TR("仅第二屏幕"));
        gtk_combo_box_set_active(GTK_COMBO_BOX(g_proj_combo), 2);
        const char *env_pj = g_getenv("QY_SETTINGS_PROJECT");
        if (env_pj && strstr(env_pj, "mode:extend"))
            gtk_combo_box_set_active(GTK_COMBO_BOX(g_proj_combo), 2);
        else if (env_pj && strstr(env_pj, "mode:mirror"))
            gtk_combo_box_set_active(GTK_COMBO_BOX(g_proj_combo), 1);
        GtkWidget *pj_btn = gtk_button_new_with_label(TR("应用"));
        qy_add_class(pj_btn, "qy-btn");
        g_signal_connect(pj_btn, "clicked", G_CALLBACK(on_project_apply), NULL);
        gtk_box_pack_start(GTK_BOX(pj_row), pj_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(pj_row), g_proj_combo, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(pj_row), pj_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vpj), pj_row, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vpj, gtk_label_new(TR("投影")));
        if (env_pj)
            g_timeout_add(1550, auto_project_apply, NULL);
    }

    /* HD Color 页: HDR 开关 + 颜色配置文件（写 /etc/qyhdr.conf） */
    {
        GtkWidget *vhd = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
        gtk_container_set_border_width(GTK_CONTAINER(vhd), 14);
        gtk_box_pack_start(GTK_BOX(vhd), row(TR("HD Color"), TR("高动态范围颜色与显示配置文件")), FALSE, FALSE, 0);
        GtkWidget *hdr_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *hdr_l = gtk_label_new(TR("HDR 视频"));
        gtk_widget_set_size_request(hdr_l, 180, -1);
        gtk_widget_set_halign(hdr_l, GTK_ALIGN_START);
        GtkWidget *hdr_sw = gtk_switch_new();
        g_hdr_loading = 1;
        gchar *content = NULL;
        gsize len = 0;
        int cur_on = 0;
        if (g_file_get_contents(HDR_CONF, &content, &len, NULL)) {
            char *line = content;
            while (line && *line) {
                if (strncmp(line, "hdr=", 4) == 0) {
                    cur_on = strncmp(line + 4, "off", 3) != 0;
                    break;
                }
                char *nl = strchr(line, '\n');
                line = nl ? nl + 1 : NULL;
            }
            g_free(content);
        }
        const char *env_hdr = g_getenv("QY_SETTINGS_HDR");
        if (env_hdr)
            cur_on = strcmp(env_hdr, "off") != 0;
        gtk_switch_set_active(GTK_SWITCH(hdr_sw), cur_on);
        g_signal_connect(hdr_sw, "state-set", G_CALLBACK(on_hdr_toggled), NULL);
        gtk_box_pack_start(GTK_BOX(hdr_row), hdr_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(hdr_row), hdr_sw, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vhd), hdr_row, FALSE, FALSE, 0);
        g_hdr_loading = 0;
        GtkWidget *pf_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        GtkWidget *pf_l = gtk_label_new(TR("颜色配置文件"));
        gtk_widget_set_size_request(pf_l, 180, -1);
        gtk_widget_set_halign(pf_l, GTK_ALIGN_START);
        g_hdr_combo = gtk_combo_box_text_new();
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_hdr_combo), "sRGB");
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_hdr_combo), "Display P3");
        gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(g_hdr_combo), TR("鲜艳"));
        gtk_combo_box_set_active(GTK_COMBO_BOX(g_hdr_combo), 0);
        GtkWidget *pf_btn = gtk_button_new_with_label(TR("应用"));
        qy_add_class(pf_btn, "qy-btn");
        g_signal_connect(pf_btn, "clicked", G_CALLBACK(on_hdr_profile_apply), NULL);
        gtk_box_pack_start(GTK_BOX(pf_row), pf_l, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(pf_row), g_hdr_combo, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(pf_row), pf_btn, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(vhd), pf_row, FALSE, FALSE, 0);
        gtk_notebook_append_page(GTK_NOTEBOOK(nb), vhd, gtk_label_new("HD Color"));
        if (env_hdr)
            g_timeout_add(1600, auto_hdr_apply, NULL);
    }

    gtk_widget_show_all(win);

    /* 日期时间每秒刷新 */
    g_timeout_add_seconds(1, update_dt, dt_label);

    /* 环境变量 QY_SETTINGS_PAGE=N 直达标签页（默认 0=关于） */
    const char *pg = g_getenv("QY_SETTINGS_PAGE");
    if (pg) {
        int n = atoi(pg);
        if (n >= 0 && n < gtk_notebook_get_n_pages(GTK_NOTEBOOK(nb))) {
            gtk_notebook_set_current_page(GTK_NOTEBOOK(nb), n);
            g_print("QYSETTINGS_DEBUG: set page=%d total=%d\n", n,
                     gtk_notebook_get_n_pages(GTK_NOTEBOOK(nb)));
        }
    }
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
