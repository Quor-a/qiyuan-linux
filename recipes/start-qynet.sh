#!/bin/sh
# 澜岫网络自启: 所有非 lo 接口 udhcpc (busybox 提供)
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
for IF in $(ls /sys/class/net | grep -v lo); do
    ip link set "$IF" up 2>/dev/null || busybox ip link set "$IF" up
    udhcpc -i "$IF" -q -t 8 -T 3 -b -p /run/udhcpc.$IF.pid >/dev/null 2>&1 &
done
wait
