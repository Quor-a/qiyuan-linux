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
\tFILE *f = fopen("/tmp/xdg/qy-windows.tmp", "w");
\tif (f) {
\t\twl_list_for_each(shsurf, &shell->shsurf_list, link) {
\t\t\tif (!shsurf->view || !weston_view_is_mapped(shsurf->view))\n\t\t\t\tcontinue;\n\t\t\tif (!shsurf->desktop_surface)\n\t\t\t\tcontinue;\n\t\t\tif (!shsurf->view->surface->role_name ||\n\t\t\t\tstrcmp(shsurf->view->surface->role_name, "xdg_toplevel") != 0)\n\t\t\t\tcontinue;\n\t\t\tconst char *title =
\t\t\t\tweston_desktop_surface_get_title(shsurf->desktop_surface);\n\t\t\tif (!title || !title[0])\n\t\t\t\tcontinue;
			struct weston_layer *ly = shsurf->view->layer_link.layer;
			fprintf(f, "%u\\t%s@%d,%d L%08x\\n", (unsigned)(uintptr_t)shsurf,
				title ? title : "window",
\t\t\t\t(int)shsurf->view->geometry.pos_offset.x,
\t\t\t\t(int)shsurf->view->geometry.pos_offset.y,
\t\t\t\t(unsigned)ly->position);
\t\t}
\t\tfclose(f);
\t\trename("/tmp/xdg/qy-windows.tmp", "/tmp/xdg/qy-windows");
\t}
\tf = fopen("/tmp/xdg/qy-focus", "r");
\tif (f) {
\t\tunsigned id = 0;
\t\tif (fscanf(f, "%u", &id) == 1) {
\t\t\tstruct shell_surface *sh = qy_find_shsurf_by_id(shell, id);
\t\t\tfclose(f);
\t\t\tunlink("/tmp/xdg/qy-focus");
\t\t\tif (sh)
\t\t\t\tweston_log("QY-ACTIVATE id=%u title=%s\\n", id,
\t\t\t\t\tsh->desktop_surface ?
\t\t\t\t\t(weston_desktop_surface_get_title(sh->desktop_surface) ?
\t\t\t\t\t weston_desktop_surface_get_title(sh->desktop_surface) : "(null)") : "(no ds)");
\t\t\tif (sh && sh->view && weston_view_is_mapped(sh->view) &&\n\t\t\t\t\tsh->view->surface->role_name &&\n\t\t\t\t\tstrcmp(sh->view->surface->role_name, "xdg_toplevel") == 0) {
\t\t\t\tstruct weston_seat *seat;
\t\t\t\twl_list_for_each(seat, &shell->compositor->seat_list, link) {
\t\t\t\t\tactivate(shell, sh->view, seat, 0);
\t\t\t\t\tbreak;
\t\t\t\t}
\t\t\t}
\t\t} else
\t\t\tfclose(f);
\t}
	f = fopen("/tmp/xdg/qy-winop", "r");
	if (f) {
		unsigned id = 0;
		char op[16] = {0};
		if (fscanf(f, "%u %15s", &id, op) == 2) {
			struct shell_surface *sh = qy_find_shsurf_by_id(shell, id);
			fclose(f);
			unlink("/tmp/xdg/qy-winop");
			if (sh && sh->desktop_surface &&\n\t\t\t\tsh->view && sh->view->surface->role_name &&\n\t\t\t\tstrcmp(sh->view->surface->role_name, "xdg_toplevel") == 0) {
				struct weston_surface *ws =
					weston_desktop_surface_get_surface(sh->desktop_surface);
				if (strcmp(op, "close") == 0) {
					weston_desktop_surface_close(sh->desktop_surface);
				} else if (strcmp(op, "minimize") == 0 && ws) {
					set_minimized(ws);
				}
			}
		} else
			fclose(f);
	}
{ struct wl_event_loop *l = wl_display_get_event_loop(shell->compositor->wl_display);
struct wl_event_source *t = wl_event_loop_add_timer(l, qy_taskbar_timer_cb, shell);
wl_event_source_timer_update(t, 500); }
	return 0;
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

# 7) activate(): 壳窗口 (qydesktop/dock/bar) 激活时不抬层, 防止全屏壁纸盖住应用窗口
raise_anchor = ('\t/* Update the surface\u2019s layer. This brings it to the top of the stacking\n'
                '\t * order as appropriate. */\n'
                '\tshell_surface_update_layer(shsurf);')
assert raise_anchor in s, 'raise anchor'
raise_guard = ('\t/* Update the surface\u2019s layer. This brings it to the top of the stacking\n'
               '\t * order as appropriate. */\n'
               '\t{\n'
               '\t\tconst char *qt = weston_desktop_surface_get_title(shsurf->desktop_surface);\n'
               '\t\tif (qt && (strcmp(qt, "qydesktop") == 0 ||\n'
               '\t\t\t   strcmp(qt, "qydesktop-dock") == 0 ||\n'
               '\t\t\t   strcmp(qt, "qydesktop-bar") == 0))\n'
               '\t\t\t; /* qiyuan shell window: skip raise */\n'
               '\t\telse\n'
               '\t\t\tshell_surface_update_layer(shsurf);\n'
               '\t}')
s = s.replace(raise_anchor, raise_guard, 1)

# 8) map(): qiyuan 壳窗口固定到 normal 层最底 (防止全屏壁纸盖住应用/面板)
map_anchor = ('\t/* Surface stacking order, see also activate(). */\n'
              '\tshell_surface_update_layer(shsurf);\n'
              '\n'
              '\tif (shsurf->state.maximized) {')
assert map_anchor in s, 'map anchor'
map_guard = ('\t/* Surface stacking order, see also activate(). */\n'
             '\tshell_surface_update_layer(shsurf);\n'
             '\n'
             '\t{\n'
             '\t\tconst char *qt = weston_desktop_surface_get_title(shsurf->desktop_surface);\n'
             '\t\tif (qt && (strcmp(qt, "qydesktop") == 0 ||\n'
             '\t\t\t   strcmp(qt, "qydesktop-dock") == 0 ||\n'
             '\t\t\t   strcmp(qt, "qydesktop-bar") == 0)) {\n'
             '\t\t\t/* qiyuan shell window: pin to BOTTOM of normal layer */\n'
             '\t\t\tstruct workspace *qws = get_current_workspace(shell);\n'
             '\t\t\twl_list_remove(&shsurf->view->layer_link.link);\n'
             '\t\t\twl_list_insert(&qws->layer.view_list, &shsurf->view->layer_link.link);\n'
             '\t\t}\n'
             '\t}\n'
             '\n'
             '\tif (shsurf->state.maximized) {')
s = s.replace(map_anchor, map_guard, 1)

open(p, 'w', encoding='utf-8').write(s)
print('taskbar compositor patch applied')
