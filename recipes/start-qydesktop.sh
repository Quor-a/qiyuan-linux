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
# v0.1.0-240: 等待 weston 的 Wayland socket 就绪。
# weston 启动前需先等 seatd socket + udev 设备就绪（release 240 新增），
# TCG 下可能 10-30s；固定 sleep 2 会在 socket 出现前就启动 qydesktop，
# 导致 "cannot open display" 直接退出、桌面只剩壁纸。改为轮询（最多 90s）。
i=0
while [ $i -lt 90 ] && [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]; do
    sleep 1
    i=$((i+1))
done
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
    # 允许自动登录用户访问 root 会话的 wayland socket（收紧权限：不再全局 777）
    chmod 755 /tmp/xdg 2>/dev/null
    chown root:"$AU" /tmp/xdg/wayland-1 2>/dev/null
    chmod 660 /tmp/xdg/wayland-1 2>/dev/null
    env XDG_RUNTIME_DIR=/tmp/xdg WAYLAND_DISPLAY=wayland-1 GDK_BACKEND=wayland LD_LIBRARY_PATH=/usr/lib:/lib HOME=$UH USER=$AU LOGNAME=$AU /bin/busybox su $AU -c "/usr/bin/qydesktop" > /dev/console 2>&1 &
else
    /usr/bin/qydesktop > /dev/console 2>&1 &
fi
# release 242: 不再随桌面自启 weston-terminal / qymon —— 这些窗口在 Wayland 下
# 默认堆叠在顶栏/左侧 Dock 之上，遮挡 logo 与开始菜单。改为从开始菜单/Dock 手动打开。
# 桌面已起 → 停开机动画 (qyboot 淡出退出)
pkill -TERM qyboot 2>/dev/null
sleep 3
echo "===SETUP===" > /dev/console
echo "QYFILES-LAUNCHED" > /dev/console
( sleep 2; ls -la "$H/.local/share/Trash/files/" > /dev/console 2>&1; echo "===TRASH-DUMP==="; cat "$H/.local/share/Trash/info/"*.trashinfo > /dev/console 2>&1 ) &
echo "===END===" > /dev/console
# v0.1.0-240: 桌面服务保持运行（原 600s 后脚本正常退出，qyinit 视为服务结束，
# 实测会导致桌面进程连带退出、只剩壁纸）。改为常驻循环，桌面可持续工作。
while true; do
    sleep 3600
done
