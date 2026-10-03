#!/usr/bin/env python3
"""weston 任务栏补丁 (client 侧): panel 顶栏中部渲染窗口按钮, 点击写 /tmp/xdg/qy-focus."""
p = 'clients/desktop-shell.c'
s = open(p, encoding='utf-8').read()

# 1) panel 结构加字段
a = '\tuint32_t color;\n};'
assert a in s, 'panel struct anchor'
s = s.replace(a, '\tstruct qy_taskbar tb;\n' + a, 1)

# 2) 定义结构+读取+定时回调 (放在 struct panel 前)
tb_code = '''
/* ---- qiyuan taskbar (client side) ---- */
#define QY_TB_MAX 12
struct qy_tb_item { unsigned id; char title[64]; };
struct qy_taskbar {
\tstruct qy_tb_item items[QY_TB_MAX];
\tint count;
\tfloat x0, y0, x1, y1;
};

static void
qy_tb_read(struct qy_taskbar *tb)
{
\ttb->count = 0;
\tFILE *f = fopen("/tmp/xdg/qy-windows", "r");
\tif (!f) return;
\tchar line[160];
\twhile (tb->count < QY_TB_MAX && fgets(line, sizeof line, f)) {
\t\tunsigned id; char *tab = strchr(line, '\\t');
\t\tif (!tab) continue;
\t\t*tab = 0; id = (unsigned)strtoul(line, NULL, 10);
\t\tchar *t = tab + 1; char *nl = strchr(t, '\\n'); if (nl) *nl = 0;
\t\tif (!t[0]) continue;
\t\ttb->items[tb->count].id = id;
\t\tsnprintf(tb->items[tb->count].title, 64, "%s", t);
\t\ttb->count++;
\t}
\tfclose(f);
}

'''
a2 = 'struct panel {\n\tstruct surface base;'
assert a2 in s, 'panel def anchor'
s = s.replace(a2, tb_code + '\n' + a2, 1)

# 3) redraw 画按钮 (插在 painted=1 前)
a3 = '\tset_hex_color(cr, panel->color);\n\tcairo_paint(cr);\n\n\tcairo_destroy(cr);'
assert a3 in s, 'redraw anchor'
draw_code = '''\tset_hex_color(cr, panel->color);\n\tcairo_paint(cr);\n\n\t/* qiyuan taskbar buttons: centered */
\t{
\t\tstruct rectangle alloc;
\t\twindow_get_allocation(panel->window, &alloc);
\t\tcairo_select_font_face(cr, "Noto Sans CJK SC", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
\t\tcairo_set_font_size(cr, 13);
\t\tint x = alloc.width / 2, y = alloc.height / 2;
\t\tcairo_text_extents_t te;
\t\tint total = 0, i;
\t\tfor (i = 0; i < panel->tb.count; i++) {
\t\t\tcairo_text_extents(cr, panel->tb.items[i].title, &te);
\t\t\ttotal += (int)te.width + 24;
\t\t}
\t\tpanel->tb.x0 = x - total / 2; panel->tb.y0 = 0;
\t\tpanel->tb.x1 = x + total / 2; panel->tb.y1 = alloc.height;
\t\tx = (int)panel->tb.x0 + 12;
\t\tfor (i = 0; i < panel->tb.count; i++) {
\t\t\tcairo_set_source_rgb(cr, 0.92, 0.92, 0.95);
\t\t\tcairo_text_extents(cr, panel->tb.items[i].title, &te);
\t\t\tcairo_move_to(cr, x, y + 5);
\t\t\tcairo_show_text(cr, panel->tb.items[i].title);
\t\t\tx += (int)te.width + 24;
\t\t}
\t}
\tcairo_destroy(cr);'''
s = s.replace(a3, draw_code, 1)

# 4) click handler
click_code = '''
static int
qy_tb_timer_cb(void *data)
{
	struct panel *panel = data;
	qy_tb_read(&panel->tb);
	widget_schedule_redraw(panel->widget);
	return 1;
}

static void
qy_panel_button_handler(struct widget *widget, struct input *input,
\t\t\tuint32_t time, uint32_t button,
\t\t\tenum wl_pointer_button_state state, void *data)
{
\tstruct panel *panel = data;
\tfloat x, y;
\tif (button != BTN_LEFT || state != WL_POINTER_BUTTON_STATE_PRESSED)
\t\treturn;
\tinput_get_position(input, &x, &y);
\tif (x < panel->tb.x0 || x > panel->tb.x1 || panel->tb.count == 0)
\t\treturn;
\tint idx = (int)((x - panel->tb.x0) / ((panel->tb.x1 - panel->tb.x0) / panel->tb.count));
\tif (idx < 0) idx = 0;
\tif (idx >= panel->tb.count) idx = panel->tb.count - 1;
\tFILE *f = fopen("/tmp/xdg/qy-focus", "w");
\tif (f) { fprintf(f, "%u\\n", panel->tb.items[idx].id); fclose(f); }
}
'''
a4 = '\nstatic int\npanel_launcher_enter_handler'
assert a4 in s, 'click anchor'
s = s.replace(a4, click_code + a4, 1)

# 5) panel_create: 挂 button handler + 初始读取 + 500ms 定时
a5 = '\twidget_set_redraw_handler(panel->widget, panel_redraw_handler);'
assert a5 in s, 'create anchor'
s = s.replace(a5, a5 + '\n\twidget_set_button_handler(panel->widget, qy_panel_button_handler);', 1)
a6 = '\twl_list_init(&panel->launcher_list);'
assert a6 in s, 'init anchor'
s = s.replace(a6, a6 + '\n\tqy_tb_read(&panel->tb);', 1)
a7 = '\tpanel_add_launchers(panel, desktop);'
assert a7 in s, 'launcher anchor'
s = s.replace(a7, a7, 1)
# 5b) 挂到 clock_func (每秒 toytimer, 官方安全路径): 时钟刷新时顺带刷新任务栏
import re as _re
m = _re.search(r'(clock_func\(struct toytimer \*tt\)\n\{\n)', s)
assert m, 'clock_func anchor'

# 在 clock_func 里 clock_timer_reset(clock) 之后加任务栏刷新: 找函数体
m2 = _re.search(r'(clock_func\(struct toytimer \*tt\)\n\{.*?)(\n\})', s, _re.S)
assert m2, 'clock_func body'
qyhook = '''
\t/* qiyuan taskbar refresh (1Hz, ride on clock timer) */
\t{
\t\tstruct panel *qy_panel = clock->panel;
\t\tqy_tb_read(&qy_panel->tb);
\t\twidget_schedule_redraw(qy_panel->widget);
\t}'''
s = s.replace(m2.group(0), m2.group(1) + qyhook + m2.group(2), 1)

open(p, 'w', encoding='utf-8').write(s)
print('taskbar client patch applied')
