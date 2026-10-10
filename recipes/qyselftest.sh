#!/bin/sh
# 澜岫启动自检：把系统状态打到串口控制台（无 GUI 也能验证）
C=/dev/console
{
echo "===QYSELFTEST==="
echo "--- uname:"; uname -a
echo "--- 服务状态 (qyctl list):"; qyctl list
echo "--- qydesktop 单元:"; qyctl status qydesktop
echo "--- 网络接口:"; ip addr show | grep -E "^[0-9]|inet "
echo "--- 磁盘:"; df -h / | tail -1
echo "--- 内存:"; free -m | head -2
echo "--- /etc/ssh:"; ls -la /etc/ssh/ | head -12
echo "--- sshd -t:"; sshd -t 2>&1; echo "rc=$?"
echo "--- /var/empty:"; ls -ld /var/empty
echo "--- 进程数:"; ls /proc | grep -c "^[0-9]"
echo "===QYSELFTEST-END==="
} > $C 2>&1
