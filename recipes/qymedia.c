/* qymedia.c — 启元音乐播放器
 * 播放 WAV（ALSA aplay 后台），支持播放/暂停/继续/停止/打开文件。
 * 自动化: QYMEDIA_AUTO=WAV路径 启动后自动加载并播放。
 */
#include <gtk/gtk.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include "qytheme.h"
#include "qyl10n.h"

static GtkWidget *file_label = NULL;
static GtkWidget *status_label = NULL;
static GtkWidget *btn_play = NULL;
static GtkWidget *btn_pause = NULL;
static GtkWidget *btn_stop = NULL;
static GPid player_pid = -1;
static gchar *current_file = NULL;
static gboolean paused = FALSE;

/* 停止当前播放 */
static void stop_player(void) {
    if (player_pid > 0) {
        kill(player_pid, SIGKILL);
        g_spawn_close_pid(player_pid);
        player_pid = -1;
    }
    paused = FALSE;
    gtk_button_set_label(GTK_BUTTON(btn_pause), TR("暂停"));
}

/* 播放文件 */
static void play_file(const char *path) {
    stop_player();
    if (!path || !path[0]) return;
    g_free(current_file);
    current_file = g_strdup(path);
    gtk_label_set_text(GTK_LABEL(file_label), path);
    char st[512];
    g_snprintf(st, sizeof st, "%s: %s...", TR("正在播放"), path);
    gtk_label_set_text(GTK_LABEL(status_label), st);

    /* 按扩展名选择解码器：WAV 用 aplay；MP3/OGG 用 mpg123/mpv/ffplay；FLAC 用 mpv/ffplay */
    const char *ext = "";
    const char *dot = strrchr(path, '.');
    if (dot) ext = dot + 1;
    const char *player = "aplay";
    const char *extra = NULL;
    if (g_ascii_strcasecmp(ext, "mp3") == 0 || g_ascii_strcasecmp(ext, "ogg") == 0 ||
        g_ascii_strcasecmp(ext, "oga") == 0) {
        if (g_find_program_in_path("mpg123")) player = "mpg123";
        else if (g_find_program_in_path("mpv")) { player = "mpv"; extra = "--no-video"; }
        else if (g_find_program_in_path("ffplay")) { player = "ffplay"; extra = "-nodisp -autoexit"; }
        else player = NULL;
    } else if (g_ascii_strcasecmp(ext, "flac") == 0) {
        if (g_find_program_in_path("mpv")) { player = "mpv"; extra = "--no-video"; }
        else if (g_find_program_in_path("ffplay")) { player = "ffplay"; extra = "-nodisp -autoexit"; }
        else player = NULL;
    }
    if (!player) {
        g_printerr("QYMEDIADBG: play %s no decoder\n", path);
        g_snprintf(st, sizeof st, "%s: %s", TR("无法播放"), TR("未找到解码器（请安装 mpg123/ffmpeg）"));
        gtk_label_set_text(GTK_LABEL(status_label), st);
        return;
    }
    gchar *cmd;
    if (extra)
        cmd = g_strdup_printf("%s %s %s", player, extra, path);
    else
        cmd = g_strdup_printf("%s -q %s", player, path);
    g_printerr("QYMEDIADBG: play %s player=%s\n", path, player);
    gchar **argv = NULL;
    g_shell_parse_argv(cmd, NULL, &argv, NULL);
    g_free(cmd);
    GError *err = NULL;
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, &player_pid, &err)) {
        g_snprintf(st, sizeof st, "%s: %s", TR("无法播放"), err ? err->message : "?");
        gtk_label_set_text(GTK_LABEL(status_label), st);
        g_clear_error(&err);
        player_pid = -1;
    } else {
        g_spawn_close_pid(player_pid);
        paused = FALSE;
        gtk_button_set_label(GTK_BUTTON(btn_pause), TR("暂停"));
    }
    g_strfreev(argv);
}

static void on_open(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    GtkWidget *dlg = gtk_file_chooser_dialog_new(
        TR("打开音频"), NULL, GTK_FILE_CHOOSER_ACTION_OPEN,
        TR("取消"), GTK_RESPONSE_CANCEL, TR("打开"), GTK_RESPONSE_ACCEPT, NULL);
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT) {
        char *path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
        if (path) {
            play_file(path);
            g_free(path);
        }
    }
    gtk_widget_destroy(dlg);
}

static void on_play(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (current_file)
        play_file(current_file);
}

static void on_pause(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    if (player_pid <= 0) return;
    if (!paused) {
        kill(player_pid, SIGSTOP);
        paused = TRUE;
        gtk_button_set_label(GTK_BUTTON(btn_pause), TR("继续"));
        gtk_label_set_text(GTK_LABEL(status_label), TR("已暂停"));
    } else {
        kill(player_pid, SIGCONT);
        paused = FALSE;
        gtk_button_set_label(GTK_BUTTON(btn_pause), TR("暂停"));
        gtk_label_set_text(GTK_LABEL(status_label), TR("正在播放"));
    }
}

static void on_stop(GtkWidget *w, gpointer ud) {
    (void)w; (void)ud;
    stop_player();
    gtk_label_set_text(GTK_LABEL(status_label), TR("已停止"));
}

/* 自动化: QYMEDIA_AUTO */
static gboolean auto_play(gpointer p) {
    const char *path = (const char *)p;
    play_file(path);
    g_free(p);
    return G_SOURCE_REMOVE;
}

static void build_ui(void) {
    qy_load_theme();
    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), TR("启元音乐"));
    gtk_window_set_default_size(GTK_WINDOW(win), 480, 320);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_margin_start(vbox, 12);
    gtk_widget_set_margin_end(vbox, 12);
    gtk_widget_set_margin_top(vbox, 10);
    gtk_widget_set_margin_bottom(vbox, 10);
    gtk_container_add(GTK_CONTAINER(win), vbox);

    GtkWidget *title = gtk_label_new("🎵");
    gtk_widget_set_halign(title, GTK_ALIGN_CENTER);
    gtk_box_pack_start(GTK_BOX(vbox), title, FALSE, FALSE, 0);

    file_label = gtk_label_new(TR("未选择音频"));
    qy_add_class(file_label, "qy-mon-info");
    gtk_widget_set_halign(file_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), file_label, FALSE, FALSE, 0);

    GtkWidget *bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_widget_set_halign(bar, GTK_ALIGN_CENTER);
    GtkWidget *b_open = gtk_button_new_with_label(TR("打开音频"));
    qy_add_class(b_open, "qy-btn");
    btn_play = gtk_button_new_with_label(TR("播放"));
    btn_pause = gtk_button_new_with_label(TR("暂停"));
    btn_stop = gtk_button_new_with_label(TR("停止"));
    g_signal_connect(b_open, "clicked", G_CALLBACK(on_open), NULL);
    g_signal_connect(btn_play, "clicked", G_CALLBACK(on_play), NULL);
    g_signal_connect(btn_pause, "clicked", G_CALLBACK(on_pause), NULL);
    g_signal_connect(btn_stop, "clicked", G_CALLBACK(on_stop), NULL);
    gtk_box_pack_start(GTK_BOX(bar), b_open, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(bar), btn_play, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(bar), btn_pause, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(bar), btn_stop, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), bar, FALSE, FALSE, 0);

    status_label = gtk_label_new(TR("就绪"));
    qy_add_class(status_label, "qy-mon-info");
    gtk_widget_set_halign(status_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(vbox), status_label, FALSE, FALSE, 0);

    gtk_widget_show_all(win);

    const char *auto_path = g_getenv("QYMEDIA_AUTO");
    if (auto_path)
        g_timeout_add(800, auto_play, g_strdup(auto_path));
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    build_ui();
    gtk_main();
    return 0;
}