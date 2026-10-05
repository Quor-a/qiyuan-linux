#!/bin/sh
# qyuseradd - 创建用户并加入 wheel (可 qysudo)
# 用法: qyuseradd <用户名> [密码]
[ -z "$1" ] && { echo "用法: qyuseradd <用户名> [密码]"; exit 1; }
U="$1"
PW="$2"
grep -q "^$U:" /etc/passwd && { echo "用户 $U 已存在"; exit 1; }
UID_N=$(grep -oE ':x:[0-9]{4,}' /etc/passwd | grep -oE '[0-9]+' | sort -n | tail -1)
UID_N=$((UID_N + 1))
echo "$U:x:$UID_N:$UID_N:$U:/home/$U:/bin/sh" >> /etc/passwd
echo "$U:x:$UID_N:" >> /etc/group
mkdir -p "/home/$U"
chmod 700 "/home/$U"
chown "$UID_N:$UID_N" "/home/$U"
grep -q "^$U:" /etc/shadow 2>/dev/null || echo "$U:!::0:99999:7:::" >> /etc/shadow
chmod 600 /etc/shadow
if [ -n "$PW" ]; then
    echo "$U:$PW" | busybox chpasswd
else
    echo "$U:!::0:99999:7:::" >> /etc/shadow
    echo "用户 $U 已创建（密码未设置，用 busybox passwd $U 设置）"
fi
# 加入 wheel
sed -i "s/^wheel:x:10:\(.*\)$/wheel:x:10:\1,$U/" /etc/group
echo "完成: $U (uid=$UID_N, wheel 组, 可 qysudo)"
