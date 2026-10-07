#!/bin/sh
export XDG_RUNTIME_DIR=/tmp/xdg
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
/bin/busybox mkdir -p /tmp/xdg
/bin/busybox chmod 700 /tmp/xdg
echo BRANCH-TEST > /tmp/branch
if ls /sys/class/drm/ 2>/dev/null | grep -q "^card"; then
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
    /usr/bin/weston --backend=headless --idle-time=0 > /tmp/werr 2>&1 &
fi
