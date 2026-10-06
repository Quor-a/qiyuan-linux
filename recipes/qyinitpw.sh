#!/bin/sh
# 首启用 qyinstall 预填密码
[ -f /etc/.initpw ] || exit 0
U=$(cut -d: -f1 /etc/.initpw)
P=$(cut -d: -f2 /etc/.initpw)
[ -n "$U" ] && [ -n "$P" ] && echo "$U:$P" | busybox chpasswd
rm -f /etc/.initpw
