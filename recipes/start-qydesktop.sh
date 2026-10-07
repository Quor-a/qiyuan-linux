#!/bin/sh
export XDG_RUNTIME_DIR=/tmp/xdg
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib:/lib
export GDK_BACKEND=wayland
# 关键: GLib g_get_home_dir() 优先读 $HOME; 若 init 环境未设/为 "/", GTK 应用与
# getent 得到的真实 home 会不一致 → 回收站等 ~/.local 路径全部错位. 强制归一:
export HOME=$(getent passwd $(id -u) | cut -d: -f6)
[ -z "$HOME" ] && export HOME=/root
sleep 4
export WAYLAND_DISPLAY=wayland-1
export GIO_MODULE_DIR=/usr/lib/x86_64-linux-gnu/gio/modules
export GDK_PIXBUF_MODULE_FILE=/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache
export GLIBC_TUNABLES=glibc.malloc.check=0:glibc.malloc.tcache_count=0
sleep 2
H=$(getent passwd $(id -u) | cut -d: -f6)
[ -z "$H" ] && H=/root
# 回收站样本
mkdir -p "$H/文档" "$H/下载"
echo "这是一份文档样本" > "$H/文档/报告草稿.txt"
mkdir -p "$H/.local/share/Trash/files" "$H/.local/share/Trash/info"
rm -rf "$H/.local/share/Trash/files/"* "$H/.local/share/Trash/info/"*
echo "被误删的报告" > "$H/.local/share/Trash/files/报告草稿.txt"
echo "被误删的笔记" > "$H/.local/share/Trash/files/notes.txt"
printf '[Trash Info]\nPath=%s/文档/报告草稿.txt\nDeletionDate=2026-10-04T20:00:00\n' "$H" > "$H/.local/share/Trash/info/报告草稿.txt.trashinfo"
printf '[Trash Info]\nPath=%s/下载/notes.txt\nDeletionDate=2026-10-04T20:05:00\n' "$H" > "$H/.local/share/Trash/info/notes.txt.trashinfo"
echo "TRASH-SEEDED" > /dev/console
# 普通用户自动登录 (/etc/qyautologin 存用户名): 桌面应用以该用户身份运行
AU=""
[ -f /etc/qyautologin ] && AU=$(head -1 /etc/qyautologin | tr -d " \n")
if [ -n "$AU" ] && getent passwd "$AU" >/dev/null; then
    UH=$(getent passwd "$AU" | cut -d: -f6)
    mkdir -p "$UH" && chown "$AU" "$UH"
    # 允许普通用户连 root 会话的 wayland socket (单用户共享 compositor)
    chmod 777 /tmp/xdg 2>/dev/null
    chmod o+rw /tmp/xdg/wayland-1 2>/dev/null
    echo "$AU:$AU" | busybox chpasswd >/dev/null 2>&1 || true
    env XDG_RUNTIME_DIR=/tmp/xdg WAYLAND_DISPLAY=wayland-1 GDK_BACKEND=wayland LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib:/lib HOME=$UH USER=$AU LOGNAME=$AU /bin/busybox su $AU -c "/usr/bin/qydesktop" > /dev/console 2>&1 &
else
    /usr/bin/qydesktop > /dev/console 2>&1 &
fi
weston-terminal > /dev/console 2>&1 &
/usr/bin/qymon > /dev/console 2>&1 &
# 桌面已起 → 停开机动画 (qyboot 淡出退出)
pkill -TERM qyboot 2>/dev/null
sleep 3
echo "===SETUP===" > /dev/console
echo "QYFILES-LAUNCHED" > /dev/console
( sleep 2; ls -la "$H/.local/share/Trash/files/" > /dev/console 2>&1; echo "===TRASH-DUMP==="; cat "$H/.local/share/Trash/info/"*.trashinfo > /dev/console 2>&1 ) &
echo "===END===" > /dev/console
sleep 600
