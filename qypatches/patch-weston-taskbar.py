#!/usr/bin/env python3
"""weston 任务栏补丁 (合成器侧): shell.c 每 500ms 把窗口列表写 /tmp/xdg/qy-windows, 读 /tmp/xdg/qy-focus 激活对应窗口."""
p = 'desktop-shell/shell.c'
s = open(p, encoding='utf-8').read()

anchor = 'void\nactivate(struct desktop_shell *shell, struct weston_view *view,\n\t struct weston_seat *seat, uint32_t flags)\n{'
assert anchor in s, 'activate anchor'

addition = '''
/* ---- qiyuan taskbar support (export window list / activate by id) ---- */
static struct shell_surface *
qy_find_shsurf_by_id(struct desktop_shell *shell, unsigned id)
{
\tstruct shell_surface *shsurf;
\twl_list_for_each(shsurf, &shell->shsurf_list, link) {
\t\tif ((unsigned)(uintptr_t)shsurf == id)
\t\t\treturn shsurf;
\t}
\treturn NULL;
}

static int
qy_taskbar_timer_cb(void *data)
{
\tstruct desktop_shell *shell = data;
\tstruct shell_surface *shsurf;
\tFILE *f = fopen("/tmp/xdg/qy-windows", "w");
\tif (f) {
\t\twl_list_for_each(shsurf, &shell->shsurf_list, link) {
\t\t\tif (!shsurf->view || !weston_view_is_mapped(shsurf->view))\n\t\t\t\tcontinue;\n\t\t\tif (!shsurf->desktop_surface)\n\t\t\t\tcontinue;\n\t\t\tconst char *title =
\t\t\t\tweston_desktop_surface_get_title(shsurf->desktop_surface);
\t\t\tfprintf(f, "%u\\t%s\\n", (unsigned)(uintptr_t)shsurf,
\t\t\t\ttitle ? title : "window");
\t\t}
\t\tfclose(f);
\t}
\tf = fopen("/tmp/xdg/qy-focus", "r");
\tif (f) {
\t\tunsigned id = 0;
\t\tif (fscanf(f, "%u", &id) == 1) {
\t\t\tstruct shell_surface *sh = qy_find_shsurf_by_id(shell, id);
\t\t\tfclose(f);
\t\t\tunlink("/tmp/xdg/qy-focus");
\t\t\tif (sh && sh->view && weston_view_is_mapped(sh->view)) {
\t\t\t\tstruct weston_seat *seat;
\t\t\t\twl_list_for_each(seat, &shell->compositor->seat_list, link) {
\t\t\t\t\tactivate(shell, sh->view, seat, 0);
\t\t\t\t\tbreak;
\t\t\t\t}
\t\t\t}
\t\t} else
\t\t\tfclose(f);
\t}
{ struct wl_event_loop *l = wl_display_get_event_loop(shell->compositor->wl_display);
struct wl_event_source *t = wl_event_loop_add_timer(l, qy_taskbar_timer_cb, shell);
wl_event_source_timer_update(t, 500); }
\treturn 0;
}

static void
qy_taskbar_start(struct desktop_shell *shell)
{
\tmkdir("/tmp/xdg", 0755);
{ struct wl_event_loop *l = wl_display_get_event_loop(shell->compositor->wl_display);
struct wl_event_source *t = wl_event_loop_add_timer(l, qy_taskbar_timer_cb, shell);
wl_event_source_timer_update(t, 500); }
}

'''
s = s.replace(anchor, addition + anchor, 1)

start_anchor = '\tclock_gettime(CLOCK_MONOTONIC, &shell->startup_time);\n\n\treturn 0;\n}'
assert start_anchor in s, 'init anchor'
s = s.replace(start_anchor,
 '\tclock_gettime(CLOCK_MONOTONIC, &shell->startup_time);\n\n\tqy_taskbar_start(shell);\n\n\treturn 0;\n}', 1)

open(p, 'w', encoding='utf-8').write(s)
print('taskbar compositor patch applied')
