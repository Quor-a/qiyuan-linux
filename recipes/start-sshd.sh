#!/bin/sh
# sshd 启动包装
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
ls /etc/ssh/ssh_host_ed25519_key >/dev/null 2>&1 || ssh-keygen -A
mkdir -p /var/empty /var/lib/sshd /var/run
chmod 711 /var/empty 0755 /var/lib/sshd 2>/dev/null || chmod 711 /var/empty
chmod 0755 /var/lib/sshd
exec /usr/sbin/sshd -D -e 2>/dev/console
