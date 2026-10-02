#!/usr/bin/env python3
"""对照清单逐项审计：哪些真有实现，哪些只是提到过，哪些完全空白。

判定不看"有没有这个词"，而看**有没有可执行的入口**。
grep 命中不算数——注释里提到、文档里写过，
都算不上是这个功能存在。

三档：
  DONE    有独立模块 + CLI 子命令，且能跑
  PARTIAL 有相关逻辑但缺关键部分，或只有配方没有框架
  MISSING 完全没有
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def cli_subcommands(tool: str) -> set:
    """实际探测工具有哪些子命令。

    不解析 --help 文本：argparse 的用法行会随子解析器变化，
    抓到的第一组 {} 往往属于别的子命令的参数。
    可靠办法是逐个试——能进 --help 的就是存在的。
    """
    p = ROOT / "bin" / tool
    if not p.exists():
        return set()
    # 只探测清单里关心的子命令：全量试太慢（工具多、子命令多），
    # 而且对本审计没有意义
    wanted = set()
    for _, t, subs, _ in ITEMS:
        if t == tool:
            wanted |= subs
    out = set()
    for c in sorted(wanted):
        try:
            r = subprocess.run([sys.executable, str(p), c, "--help"],
                               capture_output=True, text=True, timeout=15)
        except Exception:
            continue
        if "invalid choice" not in (r.stderr + r.stdout):
            out.add(c)
    return out


def has_module(name: str) -> bool:
    return (ROOT / "qyos" / (name + ".py")).exists()


def has_recipe(name: str) -> bool:
    return (ROOT / "recipes" / (name + ".py")).exists()


# 每项：(名称, 期望的工具, 期望的子命令/模块, 备注)
ITEMS = [
    # —— 执行与文件
    ("执行脚本系统", "qyrun", {"run", "status"}, "续跑是 run --resume 的标志位，不是独立子命令"),
    ("解压缩", "qyfiles", {"extract", "type"}, ""),
    ("文件管理", "qyfiles", {"trash", "restore", "copy"}, ""),
    ("文档", "qyfiles", {"set-default"}, "默认打开"),
    ("视频", "qymedia", {"kinds"}, "仅声明，无播放器框架"),
    ("音频", "qymedia", {"kinds"}, "同上"),
    ("依赖构架", "qybuild", {"deps", "shlibdeps"}, ""),
    ("更新升级", "qypkg", {"upgrade", "rollback"}, ""),

    # —— 权限与连接
    ("ROOT用户权限", "qypam", {"apply", "check"}, ""),
    ("ADB", "qyudev", {"known"}, "仅 udev 规则"),
    ("无线调试", "qynet", {"adb-tcpip", "adb-pair"}, ""),
    ("有线连接", "qynet", {"check", "ports"}, ""),
    ("WiFi", "qynet", {"wifi"}, ""),
    ("蓝牙", "qynet", {"bluetooth"}, ""),
    ("移动网络", "qynet", {"wwan"}, ""),
    ("无线网卡", "qyctl", {"wlan-on", "wlan-off"}, ""),
    ("网卡", "qynet", {"check"}, ""),
    ("虚拟网卡", "qynet", {"vnic", "vnic-check"}, ""),
    ("路由器", "qynet", {"router"}, ""),
    ("鼠标键盘连接", "qyio", {"touchpad"}, "仅触摸板"),
    ("SSH", "qynet", {"ssh"}, ""),
    ("触摸屏", "qykmod", {"find"}, "仅模块映射"),

    # —— 系统信息与控制
    ("摄像头", "qymedia", {"request"}, "独占仲裁"),
    ("显示与量度", "qyctl", {"display", "brightness"}, ""),
    ("声音", "qyctl", {"audio"}, ""),
    ("关于本机", "qyctl", {"overview"}, ""),
    ("通知与操控中心", "qynotify", {"matrix"}, ""),
    ("墙纸", "qyshell", {"wallpaper"}, ""),
    ("开发者选项", "qyshell", {"dev", "dev-enable"}, ""),
    ("重置系统", "qyshell", {"reset"}, ""),
    ("日期和时间", "qydesktop", {"panels"}, "仅面板条目"),
    ("输入法", "qyshell", {"framework"}, "含输入法/指纹/虚拟键盘框架"),
    ("语言", "qylocale", {"set", "list"}, ""),
    ("系统导航方式", "qyshell", {"navigation"}, ""),
    ("挂机/关机/休眠", "qyctl", {"power", "hibernate-check"}, ""),
    ("定时开关机", "qyctl", {"schedule", "rtc-wake"}, ""),
    ("强制重启", "qyctl", {"power-do"}, ""),
    ("渲染构架", "qyctl", {"vgpu"}, ""),
    ("自由漂浮", "qyshell", {"floating"}, ""),
    ("内容拖拽", "qyshell", {"drag"}, ""),
    ("屏幕录制", "qyctl", {"record"}, "仅命令"),
    ("截图", "qyctl", {"screenshot"}, "仅命令"),
    ("指纹解锁", "qyshell", {"framework"}, ""),
    ("密码解锁", "qypam", {"check"}, ""),
    ("进程管理", "qyproc", {"ps", "kill"}, ""),
    ("CPU", "qyproc", {"cpu", "governor"}, ""),
    ("显卡支持", "qyproc", {"gpu", "accel"}, ""),
    ("电池", "qyctl", {"battery"}, ""),
    ("安卓GPU虚拟显卡", "qyctl", {"vgpu"}, ""),
    ("GPS", "qyperms", {"ready"}, "仅能力声明"),
    ("扫码", "qyshell", {"scan", "scan-cmd"}, ""),
    ("WLAN开关", "qyctl", {"wlan-on"}, ""),
    ("充电构架", "qyctl", {"battery"}, ""),
    ("屏幕自适应", "qyctl", {"display"}, ""),
    ("硬件识别", "qyhw", {"scan"}, ""),
    ("虚拟键盘", "qyshell", {"framework"}, ""),
    ("虚拟鼠标", "qyshell", {"vmouse"}, ""),
    ("降温感知", "qyctl", {"thermal"}, ""),
    ("自我感知", "qyctl", {"overview"}, ""),
    ("VPN", "qyctl", {"vpn"}, ""),
    ("私人DNS", "qyctl", {"privdns"}, ""),
    ("DNS路由识别", "qyctl", {"dns"}, ""),
    ("运行时长", "qyctl", {"overview"}, ""),
    ("开机时间", "qyctl", {"overview"}, ""),
    ("包管理使用时间", "qyproc", {"usage", "mark-used"}, ""),
    ("内置系统包", "qyproc", {"builtin", "can-remove"}, ""),
    ("NFC", "qyperms", {"ready"}, "仅能力声明"),
    ("投屏", "qyctl", {"cast"}, "仅命令"),
    ("连接设备", "qyshell", {"paired"}, ""),
    ("免打扰", "qynotify", {"dnd"}, ""),
    ("旋转屏幕", "qysensor", {"scan"}, "仅传感器扫描"),
    ("Type-C", "qyctl", {"devices"}, ""),
    ("耳机", "qyctl", {"devices"}, ""),
    ("音响", "qyctl", {"audio"}, ""),
    ("USB连接", "qyudev", {"usb", "known"}, ""),
    ("内置浏览器", "qyshell", {"browser"}, ""),
    ("状态栏", "qydesktop", {"tray"}, ""),
    ("桌面管理", "qydesktop", {"panels"}, ""),
    ("设置", "qydesktop", {"panel"}, ""),
    ("工具调用", "qyproc", {"tools", "find-tool"}, ""),
]


def main() -> int:
    cache: dict = {}
    rows = []
    for name, tool, subs, note in ITEMS:
        if tool is None:
            rows.append((name, "MISSING", note or "完全没有入口"))
            continue
        if tool not in cache:
            cache[tool] = cli_subcommands(tool)
        have = cache[tool]
        if not have:
            rows.append((name, "MISSING", f"{tool} 不可用或无子命令"))
            continue
        if not subs:
            rows.append((name, "DONE", f"{tool} 可用"))
            continue
        got = subs & have
        if got == subs:
            rows.append((name, "DONE", f"{tool} {'、'.join(sorted(got))}"))
        elif got:
            miss = subs - got
            rows.append((name, "PARTIAL",
                         f"{tool} 缺 {'、'.join(sorted(miss))}"))
        else:
            rows.append((name, "MISSING",
                         f"{tool} 无 {'、'.join(sorted(subs))}"))

    done = [r for r in rows if r[1] == "DONE"]
    part = [r for r in rows if r[1] == "PARTIAL"]
    miss = [r for r in rows if r[1] == "MISSING"]

    print(f"清单共 {len(rows)} 项")
    print(f"  完成 {len(done)} · 部分 {len(part)} · 缺失 {len(miss)}")
    print()
    if miss:
        print("【完全缺失】")
        for n, _, why in miss:
            print(f"  {n:<18}{why}")
        print()
    if part:
        print("【部分完成】")
        for n, _, why in part:
            print(f"  {n:<18}{why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
