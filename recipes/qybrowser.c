/* qybrowser.c — 启元简易浏览器
 * libcurl 下载网页 → 提取纯文本 → GtkTextView 渲染
 * 适合轻量桌面（无 WebKit）：快速查看网页文字内容。
 */
#include <gtk/gtk.h>
#include <curl/curl.h>
#include <string.h>
#include <stdlib.h>
#include "qytheme.h"
#include "qyl10n.h"

static GtkWidget *url_entry = NULL;
static GtkWidget *view      = NULL;
static GtkWidget *status_label = NULL;
static GtkTextBuffer *buffer = NULL;

static gboolean finish_fetch(gpointer ud);   /* 前向声明 */

/* ---------- libcurl 写回调 ---------- */
struct curl_buf { char *data; size_t len; };
static size_t write_cb(void *ptr, size_t size, size_t nmemb, void *ud) {
    struct curl_buf *b = (struct curl_buf *)ud;
    size_t n = size * nmemb;
    char *p = (char *)realloc(b->data, b->len + n + 1);
    if (!p) return 0;
    b->data = p;
    memcpy(b->data + b->len, ptr, n);
    b->len += n;
    b->data[b->len] = 0;
    return n;
}

/* ---------- HTML → 纯文本 ---------- */
static void append_entity(GString *out, const char **pp) {
    const char *p = *pp;
    if      (!strncmp(p, "&amp;", 5))  g_string_append_c(out, '&');
    else if (!strncmp(p, "&lt;", 4))   g_string_append_c(out, '<');
    else if (!strncmp(p, "&gt;", 4))   g_string_append_c(out, '>');
    else if (!strncmp(p, "&quot;", 6)) g_string_append_c(out, '"');
    else if (!strncmp(p, "&nbsp;", 6)) g_string_append_c(out, ' ');
    else if (!strncmp(p, "&#", 3)) {
        const char *e = strchr(p + 2, ';');
        if (e) {
            char num[16];
            size_t L = e - (p + 2);
            if (L < sizeof num) {
                memcpy(num, p + 2, L); num[L] = 0;
                int code = atoi(num);
                if (code > 0 && code < 0x110000) g_string_append_unichar(out, code);
                *pp = e + 1;
                return;
            }
        }
    }
    *pp += 2;
}

static char *html_to_text(const char *html) {
    GString *out = g_string_new(NULL);
    const char *p = html;
    int in_tag = 0, in_skip = 0;
    while (*p) {
        if (in_skip) {
            const char *cl = strstr(p, in_skip == 1 ? "</script" : "</style");
            if (cl) { p = cl + 8; in_skip = 0; }
            else break;
        }
        if (in_tag) {
            const char *e = strchr(p, '>');
            if (!e) break;
            if (g_ascii_strncasecmp(p, "script", 6) == 0) in_skip = 1;
            else if (g_ascii_strncasecmp(p, "style", 5) == 0) in_skip = 2;
            p = e + 1;
            in_tag = 0;
            continue;
        }
        char c = *p;
        if (c == '<') { in_tag = 1; p++; continue; }
        if (c == '&') { append_entity(out, &p); continue; }
        if (c == '\n') g_string_append_c(out, '\n');
        else if (c == '\r') { /* skip */ }
        else if (c >= 0x20) g_string_append_c(out, c);
        p++;
    }
    /* 压缩 3+ 空行为 1 行 */
    char *txt = g_string_free(out, FALSE);
    GString *clean = g_string_new(NULL);
    int blanks = 0;
    for (char *q = txt; *q; q++) {
        if (*q == '\n') { blanks++; if (blanks <= 2) g_string_append_c(clean, '\n'); }
        else { blanks = 0; g_string_append_c(clean, *q); }
    }
    g_free(txt);
    return g_string_free(clean, FALSE);
}

/* ---------- 下载线程 ---------- */
typedef struct {
    char *url;
    char *text;
    char  err[256];
    long  http_code;
    size_t bytes;
} FetchResult;

static gpointer fetch_thread(gpointer ud) {
    FetchResult *r = (FetchResult *)ud;
    CURL *curl = curl_easy_init();
    struct curl_buf buf = { NULL, 0 };
    long code = 0;
    char errbuf[CURL_ERROR_SIZE] = "";
    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, r->url);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 8L);
        curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errbuf);
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "qybrowser/0.1 (Qiyuan Linux)");
        CURLcode res = curl_easy_perform(curl);
        if (res == CURLE_OK) {
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &code);
            r->http_code = code;
            r->bytes = buf.len;
            if (buf.data) {
                r->text = html_to_text(buf.data);
                g_free(buf.data);
            } else {
                g_strlcpy(r->err, TR("无数据"), sizeof r->err);
            }
        } else {
            g_strlcpy(r->err, errbuf[0] ? errbuf : curl_easy_strerror(res), sizeof r->err);
        }
        curl_easy_cleanup(curl);
    }
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, (GSourceFunc)finish_fetch, r, NULL);
    return NULL;
}

/* ---------- 主线程更新 ---------- */
static gboolean finish_fetch(gpointer ud) {
    FetchResult *r = (FetchResult *)ud;
    GtkTextIter end;
    gtk_text_buffer_get_end_iter(buffer, &end);
    if (r->text) {
        gchar *head = g_strdup_printf("%s\n%s\n", TR("页面内容"), "——————————————————");
        gtk_text_buffer_insert(buffer, &end, head, -1);
        gtk_text_buffer_insert(buffer, &end, r->text, -1);
        gtk_text_buffer_insert(buffer, &end, "\n", -1);
        g_free(head);
        g_free(r->text);
    }
    char st[256];
    if (r->http_code > 0)
        g_snprintf(st, sizeof st, "HTTP %ld · %zu %s", r->http_code, r->bytes, TR("字节"));
    else
        g_snprintf(st, sizeof st, "%s: %s", TR("下载失败"), r->err);
    gtk_label_set_text(GTK_LABEL(status_label), st);
    g_free(r->url);
    g_free(r);
    return G_SOURCE_REMOVE;
}

/* ---------- 打开 URL ---------- */
static void open_url(const char *url) {
    if (!url || !url[0]) return;
    gtk_label_set_text(GTK_LABEL(status_label), TR("正在下载..."));
    FetchResult *r = g_new0(FetchResult, 1);
    r->url = g_strdup(url);
    GThread *t = g_thread_new("qyb-fetch", fetch_thread, r);
    g_thread_unref(t);
}

static void on_open(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    const char *url = gtk_entry_get_text(GTK_ENTRY(url_entry));
    /* 自动补 http:// */
    char *full = NULL;
    if (strstr(url, "://") || g_str_has_prefix(url, "about:"))
        full = g_strdup(url);
    else
        full = g_strdup_printf("http://%s", url);
    open_url(full);
    g_free(full);
}

static gboolean on_entry_activate(GtkWidget *w, gpointer ud) {
    on_open(w, ud);
    return TRUE;
}

static void on_clear(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    gtk_text_buffer_set_text(buffer, "", -1);
}

/* ---------- 主窗口 ---------- */
static void activate(GtkApplication *app, gpointer ud) {
    (void)ud;
    qy_load_theme();
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元浏览器"));
    gtk_window_set_default_size(GTK_WINDOW(win), 720, 520);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_widget_set_margin_start(vbox, 10);
    gtk_widget_set_margin_end(vbox, 10);
    gtk_widget_set_margin_top(vbox, 8);
    gtk_widget_set_margin_bottom(vbox, 8);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    /* 工具栏: 地址栏 + 打开 + 清空 */
    GtkWidget *bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *lbl = gtk_label_new(TR("地址"));
    url_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(url_entry), "https://...");
    GtkWidget *btn = gtk_button_new_with_label(TR("打开"));
    qy_add_class(btn, "qy-btn");
    GtkWidget *btn2 = gtk_button_new_with_label(TR("清空"));
    g_signal_connect(btn, "clicked", G_CALLBACK(on_open), NULL);
    g_signal_connect(btn2, "clicked", G_CALLBACK(on_clear), NULL);
    g_signal_connect(url_entry, "activate", G_CALLBACK(on_entry_activate), NULL);
    gtk_box_pack_start(GTK_BOX(bar), lbl, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(bar), url_entry, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(bar), btn, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(bar), btn2, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), bar, FALSE, FALSE, 0);

    /* 正文: 纯文本视图 */
    GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sw), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    view = gtk_text_view_new();
    buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    gtk_text_view_set_editable(GTK_TEXT_VIEW(view), FALSE);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD);
    gtk_container_add(GTK_CONTAINER(sw), view);
    gtk_box_pack_start(GTK_BOX(vbox), sw, TRUE, TRUE, 0);

    /* 状态栏 */
    status_label = gtk_label_new(TR("就绪"));
    qy_add_class(status_label, "qy-mon-info");
    gtk_widget_set_halign(status_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 0);

    /* 自动化: QYBROWSER_URL 启动后自动打开 */
    const char *auto_url = g_getenv("QYBROWSER_URL");
    if (auto_url) {
        gtk_entry_set_text(GTK_ENTRY(url_entry), auto_url);
        open_url(auto_url);
    }

    gtk_widget_show_all(win);
}

int main(int argc, char **argv) {
    curl_global_init(CURL_GLOBAL_DEFAULT);
    GtkApplication *app = gtk_application_new("com.qiyuan.browser", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    char *own_argv[2] = { argv[0], NULL };
    int rc = g_application_run(G_APPLICATION(app), 1, own_argv);
    g_object_unref(app);
    curl_global_cleanup();
    return rc;
}