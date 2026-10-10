#!/bin/sh
export XDG_RUNTIME_DIR=/tmp/xdg
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
/bin/busybox mkdir -p /tmp/xdg
/bin/busybox chmod 700 /tmp/xdg
echo BRANCH-TEST > /tmp/branch

# v0.1.0-240: seatd/udev 输入就绪处理
# weston DRM 后端经 libseat 打开 /dev/input 设备，必须先有 seatd。
# 若 qyinit 未拉起 seatd（或早期崩溃/重启中），在此兜底启动。
if [ -x /usr/bin/seatd ] && ! /bin/busybox pidof seatd >/dev/null 2>&1 && [ ! -S /run/seatd.sock ]; then
    /usr/bin/seatd -g video > /tmp/seatd.log 2>&1 &
    echo "SEATD-STARTED" >> /tmp/branch
fi
# 等待 seatd socket 出现（最多 5s）
i=0
while [ $i -lt 20 ] && [ ! -S /run/seatd.sock ]; do
    sleep 0.25
    i=$((i+1))
done
if [ -S /run/seatd.sock ]; then
    echo "SEATD-OK" >> /tmp/branch
else
    echo "SEATD-MISSING" >> /tmp/branch
fi

# 确保输入设备节点已创建且可访问（root 通常无权限问题，显式放行更稳）
/usr/bin/udevadm trigger --type=devices --action=add 2>/dev/null
/usr/bin/udevadm settle --timeout=5 2>/dev/null
/bin/busybox chmod 666 /dev/input/event* 2>/dev/null

# v0.1.0-136: 解析设置中心写入的自定义分辨率 (weston.ini [output] mode=)
# headless 后端用它作为输出尺寸; DRM 后端本身读取 weston.ini。
MODE=
if [ -f /etc/xdg/weston/weston.ini ]; then
    MODE=$(/bin/busybox grep -o '^mode=[0-9]*x[0-9]*' /etc/xdg/weston/weston.ini 2>/dev/null | /bin/busybox head -1 | /bin/busybox cut -d= -f2)
fi
W_ARGS=
if [ -n "$MODE" ]; then
    W_W=$(echo "$MODE" | /bin/busybox cut -dx -f1)
    W_H=$(echo "$MODE" | /bin/busybox cut -dx -f2)
    if [ -n "$W_W" ] && [ -n "$W_H" ]; then
        W_ARGS="--width=$W_W --height=$W_H"
        echo "MODE=$MODE" >> /tmp/branch
    fi
fi

if [ -e /sys/class/drm/card0 ]; then
    echo DRM-BRANCH >> /tmp/branch
    /usr/bin/weston --backend=drm --renderer=pixman --idle-time=0 > /tmp/werr 2>&1 &
    echo "WESTON-RC=$?" >> /tmp/branch
    # 等输入设备就绪; 若 weston 因无输入设备退出则重试 (udev 竞速)
    i=0
    while [ $i -lt 10 ]; do
      sleep 3
      if ls /dev/input/event* >/dev/null 2>&1 && kill -0 $(pidof weston) 2>/dev/null; then break; fi
      if ! kill -0 $(pidof weston) 2>/dev/null; then
        echo WESTON-RETRY-$i >> /tmp/branch
        /usr/bin/udevadm trigger --type=devices --action=add 2>/dev/null
        /usr/bin/udevadm settle --timeout=10 2>/dev/null
        /usr/bin/weston --backend=drm --renderer=pixman --idle-time=0 >> /tmp/werr 2>&1 &
      fi
      i=$((i+1))
    done
else
    echo HEADLESS-BRANCH >> /tmp/branch
    /usr/bin/weston --backend=headless $W_ARGS --idle-time=0 > /tmp/werr 2>&1 &
fi
